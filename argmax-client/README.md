# BirdLog voice client (Swift + Argmax Pro SDK)

On-device speech-to-text for BirdLog. Streams microphone audio through Argmax
(`LiveTranscriber`) and POSTs each confirmed utterance to the BirdLog backend,
which parses it with Bonsai and writes the eBird CSVs.

```
mic ──▶ LiveTranscriber (Argmax, on-device) ──▶ confirmed text
            │                                     │
            │ custom vocabulary = 508 NY bird    ▼
            │ species (fetched from backend)   POST /sightings {transcript, lat?, lon?}
            │                                     │
            └── GPS is captured ONLY for the utterance that starts a checklist
```

## Requirements

- macOS 15+ on Apple Silicon (M1 or newer). Intel Macs are not supported.
- Xcode 16+ / Swift 5.10+.
- Argmax dashboard credentials:
  - `axst_...` **secret token** (one-time, to download the SDK from Argmax's
    private Swift package registry)
  - `ax_...` **API key** (runtime; DM the hackathon organizer for a Pro key)
- BirdLog backend running (`uvicorn app:app --port 8000`).

## Setup

```bash
# 1. One-time registry login (writes ~/.swiftpm/configuration/registries.json)
swift package-registry set --global --scope argmaxinc https://api.argmaxinc.com/v1/sdk
swift package-registry login https://api.argmaxinc.com/v1/sdk/login --token "$ARGMAX_SECRET_TOKEN"

# 2. Runtime key + build
export ARGMAX_API_KEY=ax_...
cd argmax-client
swift build -c release
```

> If you have the open-source `WhisperKit` package in another project, remove
> it before building here — the Pro SDK includes it.

## Run

```bash
swift run -c release birdlog listen
```

The first run asks for **microphone** and **location** access for your terminal
app — allow both in System Settings → Privacy & Security. If you skip location
access, say the place name in the command ("Start checklist at Beebe Lake") and
the checklist is still valid — eBird accepts a named location without
coordinates.

Say:

1. `"Start checklist at Beebe Lake"` — GPS is captured at this moment only
2. sightings, e.g. `"Two male wood ducks and a belted kingfisher"`
3. `"End checklist, windy this morning"` — duration is computed, the checklist
   is exported to `data/checklists/ebird-upload-<id>.csv` (header-less,
   ready for eBird import)

Ctrl+C stops cleanly.

## Notes and caveats

- Written against Argmax Pro SDK `3.0.6` docs; like the hackathon sample it
  was written from public docs **without compiling** (needs the registry
  token). Spots that may drift between SDK versions: `DecodingOptionsPro`
  field names, `LiveTranscriber` result case labels (`.confirm`/`.hypothesis`).
- The GPS rule: a location fix is requested only when the confirmed utterance
  matches a "start checklist" command locally. The backend also enforces this —
  it only stores coordinates when creating a checklist.
- `--model parakeet-v3_494MB` (default) supports custom vocabulary;
  Whisper models do not and silently ignore it.
