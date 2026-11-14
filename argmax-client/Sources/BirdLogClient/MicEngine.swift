// Microphone capture with a simple energy VAD that segments utterances.
// Yields each finished utterance as 16 kHz mono Float samples, ready for
// WhisperKit.transcribe(audioArray:).
//
// (The Pro SDK replaces this with LiveTranscriber + ArgmaxSource; see
// pro-variant/ProListenCommand.swift.)

import AVFoundation

enum MicError: Error, CustomStringConvertible {
    case noInput

    var description: String {
        switch self {
        case .noInput:
            return """
            No microphone input available. Grant microphone access to your \
            terminal app in System Settings → Privacy & Security → Microphone, \
            then rerun.
            """
        }
    }
}

final class MicEngine {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var continuation: AsyncStream<[Float]>.Continuation?

    // Utterance segmentation state (units = 2048-frame buffers ≈ 43 ms).
    private var preSpeech: [Float] = []
    private var utterance: [Float] = []
    private var inSpeech = false
    private var silenceStreak = 0
    private var speechStreak = 0
    private var noiseFloor: Float = 0.002

    private static let framesPerBuffer: AVAudioFrameCount = 2048
    private let silenceBuffersToSplit = 24   // ~1.0 s of trailing silence
    private let minSpeechBuffers = 6         // ~0.25 s minimum utterance
    private let preSpeechBuffers = 7         // ~0.3 s of leading context

    /// Async sequence of completed utterances (16 kHz mono float samples).
    var utterances: AsyncStream<[Float]> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    func start() throws {
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0 else { throw MicError.noInput }

        guard let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16000,
            channels: 1, interleaved: false) else { throw MicError.noInput }
        converter = AVAudioConverter(from: inFormat, to: outFormat)

        input.installTap(onBus: 0, bufferSize: Self.framesPerBuffer,
                         format: inFormat) { [weak self] buffer, _ in
            self?.process(buffer, to: outFormat)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
    }

    // MARK: - Tap processing

    private func process(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) {
        guard let converter else { return }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }

        var fed = false
        var conversionError: NSError?
        converter.convert(to: out, error: &conversionError) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard out.frameLength > 0,
              let channel = out.floatChannelData?[0] else { return }

        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
        let rms = Self.rms(of: samples)

        // Adaptive-ish threshold: 4x the observed quiet floor, clamped.
        if inSpeech {
            if rms > max(0.006, noiseFloor * 4) {
                silenceStreak = 0
                utterance.append(contentsOf: samples)
                speechStreak += 1
            } else {
                silenceStreak += 1
                utterance.append(contentsOf: samples)
                if silenceStreak >= silenceBuffersToSplit {
                    emitUtterance()
                }
            }
        } else {
            if rms > max(0.006, noiseFloor * 4) {
                inSpeech = true
                speechStreak = 1
                silenceStreak = 0
                utterance = preSpeech + samples
                preSpeech = []
            } else {
                noiseFloor = min(0.002, noiseFloor * 0.97 + rms * 0.03)
                preSpeech.append(contentsOf: samples)
                let keepSamples = Int(Self.framesPerBuffer) * preSpeechBuffers
                if preSpeech.count > keepSamples {
                    preSpeech.removeFirst(preSpeech.count - keepSamples)
                }
            }
        }
    }

    private func emitUtterance() {
        defer {
            utterance = []
            inSpeech = false
            silenceStreak = 0
            speechStreak = 0
        }
        guard speechStreak >= minSpeechBuffers,
              let continuation,
              !utterance.isEmpty else { return }
        // Trim the trailing silence from the emitted utterance.
        let keep = max(1600, utterance.count - 16000 / 2)
        continuation.yield(Array(utterance.prefix(keep)))
    }

    private static func rms(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return (sum / Float(samples.count)).squareRoot()
    }
}