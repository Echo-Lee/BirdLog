# BirdLog backend

A tiny FastAPI service that turns birding transcripts into eBird-ready CSV rows.

```
voice/typed transcript ──POST /sightings──▶ parse (Bonsai, or regex fallback)
                                        ──▶ match species against eBird taxonomy
                                        ──▶ data/birdlog.csv          (raw log, always)
                                        ──▶ data/ebird_records.csv   (eBird Record Format)
                                        ──▶ data/checklists/*.csv     (per-checklist, header-less,
                                                                       ready for eBird upload)
```

## Run

```bash
cd ../          # repo root
python3 -m venv .venv
.venv/bin/pip install -r backend/requirements.txt
cd backend
../.venv/bin/python -m uvicorn app:app --reload --port 8000
```

Optional: start the Bonsai model server first (see [docs/model-setup.md](../docs/model-setup.md))
and the backend automatically uses it for parsing. Without it, a rule-based
fallback parser is used (good enough for plumbing tests, not for the real thing).

```bash
# Bonsai server (Apple Silicon): from the hackathon samples repo
bonsai-models/mlx/start.sh 4B     # serves OpenAI-compatible API on :8080
```

Bonsai URL can be overridden with `BONSAI_URL=http://localhost:8080`.
Raw CSV with `BIRDLOG_CSV=...`, eBird CSV with `BIRDLOG_EBIRD_CSV=...`.
State/Country defaults with `BIRDLOG_STATE`/`BIRDLOG_COUNTRY`.
Disable the fallback with `BIRDLOG_ALLOW_FALLBACK=0`.

## Checklist sessions (eBird Record Format)

The eBird Record Format groups rows into checklists by shared metadata
(one date, one location, one protocol). Voice commands drive it:

| Utterance | What happens |
|---|---|
| `"Start checklist at Beebe Lake"` (± `traveling/stationary`, `N observers`, `X miles`) | Opens a session. **GPS (`latitude`/`longitude` in the request) is stored here and only here.** Location name comes from the utterance; protocol defaults to Stationary; observers default to 1. |
| any sightings | Appended to `data/ebird_records.csv` with the checklist's metadata (date, start time, location, lat/lon, protocol, observers). One row per species; `Number` is the count or `X`. |
| `"End checklist, windy this morning"` | Duration (minutes since start) is backfilled across the checklist's rows, the trailing text becomes the per-checklist Submission Comments, and a **header-less** `data/checklists/ebird-upload-<id>.csv` is exported for direct eBird import. |

Sightings with no active checklist still go to the raw log (`birdlog.csv`)
but not to the eBird file. Starting a new checklist while one is open
auto-finalizes the previous one.

Column order follows the eBird template exactly (19 columns: Common Name,
Genus, Species, Number, Species Comments, Location Name, Latitude, Longitude,
Date, Start Time, State/Province, Country, Protocol, Number of Observers,
Duration, All observations reported?, Effort Distance, Effort area acres,
Submission Comments). Dates are `M/D/YYYY`, times military, duration in
minutes, counts may be `X`. State/Country default to `NY`/`US` (override with
`BIRDLOG_STATE`/`BIRDLOG_COUNTRY`).

## Endpoints

| Method | Path | What it does |
|---|---|---|
| GET | `/health` | Backend + Bonsai status, species counts, active checklist |
| POST | `/sightings` | `{ "transcript": "...", "latitude": 42.45, "longitude": -76.48 }` → commands, parse, taxonomy-match, CSVs |
| POST | `/voice` | Raw 16 kHz WAV body (± `?latitude&longitude`) → on-device ASR via the Swift `birdlog` CLI (Argmax WhisperKit) → same pipeline. Note: the ASR model reloads per request (~20-30 s); `birdlog listen` keeps it resident. |
| GET | `/sightings` | Raw log CSV contents |
| GET | `/checklist` | Active checklist session |
| GET | `/records` | eBird Record Format CSV contents |
| GET | `/vocab?limit=3000&format=text` | Argmax **custom vocabulary** — NY species common names (508 terms, under the 3000 limit) |
| GET | `/species/search?q=heron&scope=regional\|worldwide` | Taxonomy search |

Interactive API docs: `http://localhost:8000/docs`.
Quick manual test: open `test.html` in a browser while the backend runs.
Use **🎤 Record** to speak (the browser resamples to 16 kHz WAV and posts it to
`/voice`), **Send text** for typed input, and **Toggle GPS** to attach real
browser geolocation (falls back to a mock point).

## Examples

```bash
# Full checklist session
curl -X POST http://localhost:8000/sightings -H "Content-Type: application/json" \
  -d '{"transcript":"Start checklist at Beebe Lake","latitude":42.4534,"longitude":-76.4803}'
curl -X POST http://localhost:8000/sightings -H "Content-Type: application/json" \
  -d '{"transcript":"Two male wood ducks and a belted kingfisher"}'
curl -X POST http://localhost:8000/sightings -H "Content-Type: application/json" \
  -d '{"transcript":"End checklist, windy this morning"}'
```

Response rows contain the **canonical** eBird fields (`species_code`,
`primary_com_name`, `sci_name`, `family`, `species_group`) plus `count`,
`location`, `notes`, `match_confidence`, and which parser was used.

## How species matching handles the 18k-name taxonomy

The eBird taxonomy has ~18.6k rows worldwide — too many for Argmax's 3000-term
custom vocabulary. So:

- **ASR side** (`/vocab`): only the 508 species on the New York checklist
  ([scripts/build_ny_checklist.py](../scripts/build_ny_checklist.py) builds it
  from Wikipedia's "List of birds of New York" intersected with the taxonomy).
- **Matching side**: after parsing, names are matched against the regional
  checklist first (exact, then fuzzy ≥ 0.85), then against the full worldwide
  taxonomy — so the system still recognizes a vagrant Snowy Owl spelling or
  any non-NY species.
- Unknown names are logged with `match_scope=unmatched` instead of being
  silently dropped.
