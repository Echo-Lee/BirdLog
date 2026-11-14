// License activation and WhisperKitPro setup.
// Modeled on the hackathon sample argmax-pro-sdk/native/Sources/MeetingScribe/Bootstrap.swift.

import Argmax
import Foundation

enum Bootstrap {
    /// Activates the Pro SDK. The key is checked against api.argmaxinc.com on
    /// first use, then a per-device license is cached in the Keychain.
    static func activateSDK(apiKey: String?) async throws {
        let key = apiKey
            ?? ProcessInfo.processInfo.environment["ARGMAX_API_KEY"]
            ?? ""
        guard key.hasPrefix("ax_") else {
            throw ValidationError(
                "Set ARGMAX_API_KEY (or pass --api-key) to your ax_ key from https://app.argmaxinc.com")
        }
        await ArgmaxSDK.with(ArgmaxConfig(apiKey: key))
    }

    /// Creates WhisperKitPro with the BirdLog custom vocabulary (NY species
    /// from the backend's /vocab endpoint). Parakeet v3 supports custom
    /// vocabulary; Whisper models do not.
    static func makeWhisperKitPro(model: String, vocabulary: [String]) async throws -> WhisperKitPro {
        print("Loading ASR model \(model) (first run downloads it)...")
        let config = vocabulary.isEmpty
            ? WhisperKitProConfig(model: model)
            : WhisperKitProConfig(model: model,
                                  customVocabularyConfig: .init(words: vocabulary))
        let whisperKitPro = try await WhisperKitPro(config)
        if !vocabulary.isEmpty {
            print("Custom vocabulary loaded: \(vocabulary.count) bird species.")
        }
        return whisperKitPro
    }
}