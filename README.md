# BirdLog

Voice-in, CSV-out birding log built for the Cornell Local AI Hackathon.

**Pipeline** (all on-device / local):

```
voice ──Argmax SDK (Swift)──▶ transcript ──▶ BirdLog backend ──▶ Bonsai-2 (MLX) ──▶ eBird taxonomy match ──▶ eBird Record Format CSVs
```

Voice commands drive eBird checklists: **"Start checklist at Beebe Lake"**
(GPS is captured once, here) → sightings → **"End checklist, windy this
morning"** (duration backfilled, header-less file exported, ready to upload at
[ebird.org/importData](https://ebird.org/submit/importData)).

- **Argmax Pro SDK** — on-device speech-to-text (Swift, Apple Silicon), with the
  NY species list as custom vocabulary (served by the backend at `/vocab`).
- **Bonsai-2 (PrismML, ternary LLM)** — parses transcripts into structured
  sightings, served locally via `mlx_vlm.server` (OpenAI-compatible, port 8080).
- **eBird taxonomy** — species names are normalized to canonical
  `primary_com_name` / `species_code` / `sci_name` before being logged.
- **eBird Record Format** — output CSVs follow the official import template
  exactly (19 columns, M/D/YYYY dates, military times, `X` counts).

## Layout

| Path | What it is |
|---|---|
| [argmax-client/](argmax-client/) | Swift voice client (`birdlog listen`): Argmax STT → backend (needs Argmax keys) |
| [backend/](backend/) | FastAPI backend: transcript → sightings → eBird CSVs (`uvicorn app:app --port 8000`) |
| [backend/test.html](backend/test.html) | Quick manual test client (type instead of speak) |
| [taxonomy/](taxonomy/) | eBird taxonomy (worldwide) + `new_york_species.csv` regional subset |
| [scripts/build_ny_checklist.py](scripts/build_ny_checklist.py) | Rebuilds the NY checklist from Wikipedia |
| [docs/model-setup.md](docs/model-setup.md) | How to run Argmax + Bonsai, API details |

## Quick start

```bash
# 1. Bonsai model server (Apple Silicon; needs Python 3.10+, e.g. via uv)
uv venv --python 3.12 .bonsai-venv && uv pip install --python .bonsai-venv/bin/python "mlx-vlm>=0.7.8"
.bonsai-venv/bin/hf download prism-ml/Ternary-Bonsai-2-4B-mlx-2bit --local-dir models/bonsai2-4b-mlx
.bonsai-venv/bin/python -m mlx_vlm.server --model models/bonsai2-4b-mlx --port 8080

# 2. Backend (works without Bonsai too, using a rule-based fallback parser)
python3 -m venv .venv && .venv/bin/pip install -r backend/requirements.txt
cd backend && ../.venv/bin/python -m uvicorn app:app --reload --port 8000

# 3. Log a full eBird checklist session
curl -X POST http://localhost:8000/sightings -H "Content-Type: application/json" \
  -d '{"transcript":"Start checklist at Beebe Lake","latitude":42.4534,"longitude":-76.4803}'
curl -X POST http://localhost:8000/sightings -H "Content-Type: application/json" \
  -d '{"transcript":"Two male wood ducks and a belted kingfisher"}'
curl -X POST http://localhost:8000/sightings -H "Content-Type: application/json" \
  -d '{"transcript":"End checklist, windy this morning"}'

# 4. (Optional) Real voice input: see argmax-client/README.md for Argmax setup,
#    then: swift run -c release birdlog listen
```

Outputs: `data/birdlog.csv` (raw log), `data/ebird_records.csv` (eBird Record
Format), `data/checklists/ebird-upload-<id>.csv` (header-less, ready for eBird).

API docs at `http://localhost:8000/docs`. See [backend/README.md](backend/README.md)
for all endpoints, including `/vocab` (Argmax custom vocabulary) and
`/species/search`.
