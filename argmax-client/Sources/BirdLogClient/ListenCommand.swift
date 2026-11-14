// `birdlog listen`: live microphone transcription -> BirdLog backend.
//
// Mic capture is segmented into utterances by energy VAD (MicEngine); each
// utterance is transcribed by WhisperKit and POSTed to the backend, which
// handles the "start checklist" / "end checklist" voice commands, Bonsai
// parsing, eBird taxonomy matching, and the eBird Record Format CSVs.
//
// Pro SDK upgrade: see pro-variant/ProListenCommand.swift (LiveTranscriber +
// ArgmaxSource replace MicEngine; customVocabularyConfig replaces the prompt).

import ArgumentParser
import Foundation
import WhisperKit

struct Listen: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "listen",
        abstract: "Listen to the microphone and log bird sightings. Ctrl+C to stop."
    )

    @Option(help: "BirdLog backend URL.")
    var url: String = "http://localhost:8000"

    @Option(help: "WhisperKit ASR model (large-v3-v20240930_626MB recommended).")
    var model: String = "large-v3-v20240930_626MB"

    @Flag(help: "Don't use the birding vocabulary prompt.")
    var noVocabulary = false

    func run() async throws {
        let backend = Backend(url)
        let whisperKit = try await Bootstrap.makeWhisperKit(model: model)
        let options = Bootstrap.decodingOptions(
            tokenizer: noVocabulary ? nil : whisperKit.tokenizer,
            promptTokensFrom: noVocabulary ? nil : Bootstrap.birdingPrompt)

        let mic = MicEngine()
        try mic.start()
        installCtrlCHandler(mic)

        print("\n🎤 Listening... Say e.g. \"Start checklist at Beebe Lake\", then sightings, "
              + "then \"End checklist, windy this morning\". (Ctrl+C to stop)\n")

        for await samples in mic.utterances {
            let seconds = Double(samples.count) / 16000
            print(String(format: "  … transcribing %.1fs of speech", seconds))
            let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
            let text = results.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            print("  🗣 \(text)")
            await handle(text, backend: backend)
        }
    }

    // MARK: - Utterance handling

    /// GPS is only captured for the utterance that starts a checklist.
    /// Mirrors backend/ebird.py START_RE (modifiers allowed: "start a
    /// traveling checklist").
    private static let startCommand = try! NSRegularExpression(
        pattern: #"\b(?:start|begin|new)\s+(?:an?\s+|the\s+|this\s+)?(?:[a-z'\-]+\s+){0,3}checklist\b"#,
        options: [.caseInsensitive])

    private func handle(_ text: String, backend: Backend) async {
        var latitude: Double?
        var longitude: Double?
        let range = NSRange(text.startIndex..., in: text)
        if Self.startCommand.firstMatch(in: text, options: [], range: range) != nil {
            print("  📍 capturing GPS for new checklist...")
            if let location = await LocationProvider().currentLocation() {
                latitude = location.coordinate.latitude
                longitude = location.coordinate.longitude
                print(String(format: "     %.5f, %.5f", latitude!, longitude!))
            }
        }

        do {
            let response = try await backend.post(transcript: text,
                                                 latitude: latitude, longitude: longitude)
            print("  ✔ \(response.summary)")
        } catch {
            print("  ✖ backend error: \(error.localizedDescription)")
        }
    }

    /// Ctrl+C stops the stream cleanly instead of killing the process.
    private func installCtrlCHandler(_ mic: MicEngine) {
        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        source.setEventHandler {
            print("\nStopping...")
            mic.stop()
        }
        source.resume()
    }
}