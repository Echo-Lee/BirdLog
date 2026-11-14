// `birdlog listen`: live microphone transcription -> BirdLog backend.
//
// Stream: LiveTranscriber yields .confirm (final) and .hypothesis (interim)
// text. Every confirmed utterance is POSTed to the backend, which handles the
// "start checklist" / "end checklist" voice commands, Bonsai parsing, eBird
// taxonomy matching, and the eBird Record Format CSVs.
//
// Modeled on the hackathon sample argmax-pro-sdk/native (LiveCommand.swift).

import Argmax
import ArgumentParser
import Foundation

struct Listen: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "listen",
        abstract: "Listen to the microphone and log bird sightings. Ctrl+C to stop."
    )

    @Option(help: "BirdLog backend URL.")
    var url: String = "http://localhost:8000"

    @Option(help: "Argmax ASR model. parakeet-v3_494MB supports custom vocabulary.")
    var model: String = "parakeet-v3_494MB"

    @Option(help: "Argmax ax_ API key (defaults to $ARGMAX_API_KEY).")
    var apiKey: String?

    @Flag(help: "Don't load the bird species custom vocabulary.")
    var noVocabulary = false

    func run() async throws {
        let backend = Backend(url)

        try await Bootstrap.activateSDK(apiKey: apiKey)

        let vocabulary = noVocabulary ? [] : (try? await backend.fetchVocabulary()) ?? []
        let whisperKitPro = try await Bootstrap.makeWhisperKitPro(model: model, vocabulary: vocabulary)

        let options = DecodingOptionsPro(
            base: .init(task: .transcribe, wordTimestamps: true, chunkingStrategy: .vad),
            transcribeInterval: 0.1,
            streamTranscriptionMode: .voiceTriggered(minProcessInterval: 0.3),
            alignTimestampsToGlobal: true
        )

        let liveTranscriber = LiveTranscriber(whisperKit: whisperKitPro)
        let mic = ArgmaxSource(streamType: .device(nil))  // nil = default input device

        try await liveTranscriber.registerStream(streamSource: mic, options: options)
        let results = try await liveTranscriber.startTranscription(for: mic)

        installCtrlCHandler()
        print("\n🎤 Listening... Say e.g. \"Start checklist at Beebe Lake\", then sightings, "
              + "then \"End checklist, windy this morning\". (Ctrl+C to stop)\n")

        for try await result in results {
            switch result {
            case .confirm(let text, _, _):
                await handle(text, backend: backend)
            case .hypothesis(let text, _, _):
                Terminal.render(interim: text)
            default:
                break
            }
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
        let transcript = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard transcript.count >= 2 else { return }

        var latitude: Double?
        var longitude: Double?
        let range = NSRange(transcript.startIndex..., in: transcript)
        if Self.startCommand.firstMatch(in: transcript, options: [], range: range) != nil {
            print("  📍 capturing GPS for new checklist...")
            if let location = await LocationProvider().currentLocation() {
                latitude = location.coordinate.latitude
                longitude = location.coordinate.longitude
                print(String(format: "     %.5f, %.5f", latitude!, longitude!))
            }
        }

        do {
            let response = try await backend.post(transcript: transcript,
                                                 latitude: latitude, longitude: longitude)
            print("  ✔ \(response.summary)")
        } catch {
            print("  ✖ backend error: \(error.localizedDescription)")
        }
    }

    /// Ctrl+C stops the stream cleanly instead of killing the process, so the
    /// backend ends up with complete transcripts.
    private func installCtrlCHandler() {
        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        source.setEventHandler {
            print("\nStopping...")
            exit(0)
        }
        source.resume()
    }
}

enum Terminal {
    private static var lastInterim = ""

    /// Rewrite the current line with the in-progress hypothesis.
    static func render(interim: String) {
        guard interim != lastInterim, !interim.isEmpty else { return }
        lastInterim = interim
        print("  … \(interim)", terminator: "\r")
        fflush(stdout)
    }
}