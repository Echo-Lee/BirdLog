# BirdLog — Local Model Setup (Argmax + Bonsai)

Reference for the two models required by the Cornell Local AI Hackathon, based on
[iBrushC/local-ai-hackathon-samples](https://github.com/iBrushC/local-ai-hackathon-samples)
and the hackathon "Technical Details" handout.

## Constraints (from the handout)

| | Constraint |
|---|---|
| Bonsai LLMs | Ternary (−1/0/+1) quantized, ~1.58 bits/weight. **Only Bonsai-2 2B / 4B / 9B allowed.** All < 4 GB RAM, but RAM grows 2–3× with context window. |
| Argmax | On-device STT/TTS/diarization with hardware acceleration. **Apple Silicon MLX (M1+) or recent Snapdragon only.** Must be accessed via **Swift or Kotlin**. The local server API is **not** available. |
| Implementation options | (a) fully native Swift/Kotlin app, (b) React Native, (c) a simple Swift/Kotlin server interfaced by Python/Node. |

Our target: Apple Silicon Mac → use **Argmax native Swift SDK** + **Bonsai via MLX**.

---

## Bonsai (LLM that parses voice transcripts into CSV rows)

Use the repo's `bonsai-models/mlx` sample.

### Start the server

```bash
cd bonsai-models/mlx
chmod +x start.sh
./start.sh 4B        # 2B | 4B | 9B (default 4B)
```

First run:
1. Creates `.venv/`, installs `mlx-vlm>=0.7.8` (**not** `mlx-lm` — released mlx-lm cannot load these ternary packs).
2. Downloads `prism-ml/Ternary-Bonsai-2-<SIZE>-mlx-2bit` into `models/`.
3. Starts `python -m mlx_vlm.server --model models/bonsai2-<size>-mlx --port 8080`.

### Call it (OpenAI-compatible, `http://localhost:8080/v1`)

```python
from openai import OpenAI

client = OpenAI(base_url="http://localhost:8080/v1", api_key="none")
# The model id is the absolute path passed to --model; pick the loaded one.
model = next(m.id for m in client.models.list().data if getattr(m, "loaded", False))

r = client.chat.completions.create(
    model=model,
    messages=[
        {"role": "system", "content": "You extract structured bird-sighting data. "
         "Return ONLY a JSON array of {species, count, location, notes}. Return [] if none."},
        {"role": "user", "content": "Saw two male wood ducks at Beebe Lake this morning"},
    ],
    temperature=0.7, top_p=0.8,
    extra_body={"top_k": 20, "min_p": 0, "presence_penalty": 1.5,
                "chat_template_kwargs": {"enable_thinking": False}},
)
print(r.choices[0].message.content)
```

### Gotchas

- **Python 3.10+ required.** The macOS system Python is 3.9, which `pip` cannot
  satisfy for `mlx-vlm`. Use `uv venv --python 3.12` (the sample's `start.sh`
  calls plain `python3` and will fail on 3.9).

- **Always send sampling settings.** Neither server reads `presence_penalty` / `min_p` from model metadata. Non-thinking presets from the model cards: `temperature 0.7, top_p 0.80, top_k 20, min_p 0, presence_penalty 1.5, repetition_penalty 1.0, max_tokens 2048`.
- `enable_thinking: False` (via `chat_template_kwargs`) for fast structured output.
- Server loads **one model at a time**; CORS is enabled, so a local HTML page can call it directly.
- GGUF alternative (`bonsai-models/gguf`, PrismML llama.cpp fork) also works on Mac (Metal) but MLX is the native path.

---

## Argmax (on-device speech-to-text)

Use the repo's `argmax-pro-sdk/native` sample. Requirements: **macOS 15+ on Apple Silicon**, Xcode 16+ / Swift 5.10+, Argmax dashboard credentials:

- `axst_...` **secret token** — one-time, to download the SDK from Argmax's private Swift package registry.
- `ax_...` **API key** — runtime, unlocks Pro features (DM the organizer for a Pro key).

### Setup

```bash
# One-time registry login (writes ~/.swiftpm/configuration/registries.json)
swift package-registry set --global --scope argmaxinc https://api.argmaxinc.com/v1/sdk
swift package-registry login https://api.argmaxinc.com/v1/sdk/login --token "$ARGMAX_SECRET_TOKEN"

export ARGMAX_API_KEY=ax_...
swift build -c release
```

`Package.swift` dependency:

```swift
.package(id: "argmaxinc.argmax-sdk-swift", from: "3.0.6"),
// target:
.product(name: "Argmax", package: "argmaxinc.argmax-sdk-swift")
```

> If you have the open-source `WhisperKit` package in another project, remove it first — the Pro SDK includes it. Docs pin `3.0.6`, but some examples use `2.0.9`; check the changelog if a signature doesn't match.

First run asks for **microphone access** for your terminal app (System Settings → Privacy & Security → Microphone).

### Core APIs (from the MeetingScribe sample)

```swift
import Argmax

// 1. Activate the SDK (license cached in Keychain after first check)
await ArgmaxSDK.with(ArgmaxConfig(apiKey: key))

// 2. Load the ASR model (downloads on first run)
let whisperKitPro = try await WhisperKitPro(WhisperKitProConfig(model: "large-v3-v20240930_626MB"))

// 3a. Live microphone transcription
let live = LiveTranscriber(whisperKit: whisperKitPro)
let mic = ArgmaxSource(streamType: .device(nil))   // default input device
try await live.registerStream(streamSource: mic, options: DecodingOptionsPro(
    base: .init(task: .transcribe, wordTimestamps: true, chunkingStrategy: .vad),
    transcribeInterval: 0.1,
    streamTranscriptionMode: .voiceTriggered(minProcessInterval: 0.3),  // or .alwaysOn
    alignTimestampsToGlobal: true
))
let results = try await live.startTranscription(for: mic)
for try await result in results {
    switch result {
    case .confirm(let text, _, _):   print("final:", text)      // append to log
    case .hypothesis(let text, _, _): print("interim:", text)   // live display
    default: break
    }
}

// 3b. Or transcribe an audio file
let audio = try AudioProcessor.loadAudioAsFloatArray(fromPath: path)
let results = try await whisperKitPro.transcribe(
    audioArray: audio,
    decodeOptions: DecodingOptions(detectLanguage: true, wordTimestamps: true, chunkingStrategy: .vad))
```

### Custom vocabulary — the killer feature for BirdLog

Up to **3000 terms** of domain vocabulary so species names are spelled correctly:

```swift
let config = WhisperKitProConfig(
    model: "parakeet-v3_494MB",                       // custom vocab is disabled for Whisper models
    customVocabularyConfig: .init(words: birdSpeciesNames))
let whisperKitPro = try await WhisperKitPro(config)
// change at runtime: try whisperKitPro.setCustomVocabulary([...])
```

The sample auto-switches from Whisper (`large-v3-v20240930_626MB`) to Parakeet v3 (`parakeet-v3_494MB`) when a vocabulary is passed. Terms under 4 characters reduce accuracy.

### Models

| Model | Argmax name | Use |
|---|---|---|
| Whisper large-v3 turbo | `large-v3-v20240930_626MB` | Default transcription (no custom vocab) |
| Parakeet v3 | `parakeet-v3_494MB` | Transcription with custom vocabulary |
| Sortformer / Pyannote | — | Speaker diarization (not needed for BirdLog) |

---

## Planned BirdLog pipeline

```
Swift (Argmax Pro SDK)                          Bonsai server (MLX)            CSV
────────────────────────                        ──────────────────────         ───
mic ──> LiveTranscriber ──> confirmed text ──HTTP──> /v1/chat/completions ──> append
        + bird-species custom vocab                 (system prompt: strict      rows
                                                      JSON: species, count,
                                                      location, notes, datetime)
```

1. Swift CLI/native app: mic → `LiveTranscriber`, custom vocabulary = bird species list.
2. On each `.confirm` (or a "log this sighting" trigger), POST the text to Bonsai.
3. Bonsai returns strict JSON (`enable_thinking: False`, low temperature) — validated in Swift.
4. Append a row to `birdlog.csv`.
