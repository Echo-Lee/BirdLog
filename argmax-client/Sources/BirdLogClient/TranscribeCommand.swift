// `birdlog transcribe <audio>`: transcribe an audio file and send it to the
// BirdLog backend. This is the file-based twin of `listen` (like the hackathon
// sample's `meeting-scribe file`), useful for testing the full pipeline without
// the microphone — e.g. with synthesized speech.

import ArgumentParser
import Foundation
import WhisperKit

struct Transcribe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Transcribe an audio file (wav, m4a, aiff, mp3, flac) and log it to BirdLog."
    )

    @Argument(help: "Path to the audio file.")
    var audioPath: String

    @Option(help: "BirdLog backend URL.")
    var url: String = "http://localhost:8000"

    @Option(help: "WhisperKit ASR model (large-v3-v20240930_626MB recommended).")
    var model: String = "large-v3-v20240930_626MB"

    @Option(help: "Latitude, for the utterance that starts a checklist.")
    var latitude: Double?

    @Option(help: "Longitude, for the utterance that starts a checklist.")
    var longitude: Double?

    @Flag(help: "Print the transcript but don't POST to the backend.")
    var dryRun = false

    @Flag(help: "Print ONLY the transcript to stdout (status to stderr); for scripting.")
    var transcriptOnly = false

    @Flag(help: "Don't use the birding vocabulary prompt.")
    var noVocabulary = false

    func run() async throws {
        let whisperKit = try await Bootstrap.makeWhisperKit(model: model)
        let options = Bootstrap.decodingOptions(
            tokenizer: noVocabulary ? nil : whisperKit.tokenizer,
            promptTokensFrom: noVocabulary ? nil : Bootstrap.birdingPrompt)

        Bootstrap.eprint("Transcribing \(audioPath)...")
        let results = try await whisperKit.transcribe(audioPath: audioPath, decodeOptions: options)
        let transcript = results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if transcriptOnly {
            print(transcript)
        } else {
            print("Transcript: \(transcript)")
        }

        guard !dryRun, !transcript.isEmpty else { return }

        let response = try await Backend(url).post(transcript: transcript,
                                                   latitude: latitude, longitude: longitude)
        print("Backend: \(response.summary)")
    }
}