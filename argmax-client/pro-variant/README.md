# Argmax Pro SDK — Pro variant of the Swift client

The buildable client in `../Sources` uses the **Argmax open-source SDK**
(WhisperKit, no credentials needed). This folder holds the **Pro SDK** variant
of the same code, ready to swap in once you have credentials.

## What Pro adds

| Open-source (current) | Pro SDK |
|---|---|
| `WhisperKit` via GitHub | `Argmax` via Argmax's private Swift registry |
| Mic: `MicEngine` (AVAudioEngine + energy VAD) | `LiveTranscriber` + `ArgmaxSource` (`.confirm`/`.hypothesis` streaming) |
| Vocabulary: `DecodingOptions.promptTokens` prompt conditioning | `WhisperKitProConfig(customVocabularyConfig:)` — true keyword spotting over the 508 NY species (up to 3000 terms) |
| Models: Whisper large-v3 turbo | `parakeet-v3_494MB` (custom vocab), `large-v3-v20240930_626MB` (default) |
| No credentials | Needs `axst_...` registry token (build) + `ax_...` API key (runtime) |

## Files

- `ProBootstrap.swift` — `ArgmaxSDK.with(ArgmaxConfig(apiKey:))` activation +
  `WhisperKitPro` with the species vocabulary fetched from the backend's
  `/vocab` endpoint.
- `ProListenCommand.swift` — `birdlog listen` built on `LiveTranscriber` and
  `DecodingOptionsPro`, with `.confirm` text POSTed to `/sightings` and GPS
  captured only on "start checklist" utterances.

## Switching to Pro (once you have both credentials)

```bash
# 0. One-time (sudo): accept the Xcode license
sudo xcodebuild -license accept

# 1. One-time registry login with the SECRET token (axst_...)
swift package-registry set --global --scope argmaxinc https://api.argmaxinc.com/v1/sdk
swift package-registry login https://api.argmaxinc.com/v1/sdk/login --token "$ARGMAX_SECRET_TOKEN"

# 2. Runtime key (already in ../.env, gitignored)
export ARGMAX_API_KEY=ax_...     # 34-char runtime key

# 3. Swap the engine:
#    - Replace Package.swift with the Pro manifest below
#    - Copy ProBootstrap.swift + ProListenCommand.swift over the ones in
#      ../Sources/BirdLogClient/ (Backend.swift, LocationProvider.swift,
#      BirdLogClient.swift stay unchanged; MicEngine.swift becomes unused)
#    - Port TranscribeCommand.swift to AudioProcessor.loadAudioAsFloatArray +
#      whisperKitPro.transcribe(audioArray:decodeOptions:)
#    - swift build -c release
```

If the OSS WhisperKit package is still resolved anywhere, clear it first —
`swift package resolve` must only see the Argmax registry package. If a
signature doesn't match (SDK versions 2.0.9 vs 3.0.6 differ in the docs),
check https://app.argmaxinc.com/docs/changelog.
