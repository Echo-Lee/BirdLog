// birdlog — BirdLog voice client entry point.
//
// Usage:
//   birdlog listen                       # live mic -> backend -> eBird CSVs
//   birdlog transcribe clip.wav          # audio file -> backend (test path)
//
// Engine: Argmax open-source WhisperKit (no API key needed). Pro SDK upgrade:
// see pro-variant/ and README.md. Requires the BirdLog backend on --url.

import ArgumentParser

@main
struct BirdLogClient: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "birdlog",
        abstract: "Voice input for BirdLog: on-device transcription via Argmax, "
            + "parsed locally by Bonsai, logged in the eBird Record Format.",
        subcommands: [Listen.self, Transcribe.self]
    )
}