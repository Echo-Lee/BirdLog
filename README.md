# BirdLog

Hands-free voice checklisting for drivers. Fully offline.

- `BirdCore/` — all non-UI logic (parser, matcher, engine, exporter). Run tests: `cd BirdCore && swift test`
- `BirdLog/` — iOS app target (speech, location, Siri intents, UI)
- `tools/make_taxonomy.py` — regenerates `BirdLog/taxonomy.json` from the CSVs in `data/`
- `BIRDLOG_WORK_PLAN.md` — 2-person work split, decisions (D1–D7), device test checklist

## Regenerate taxonomy (ABA-filtered by default)

    python3 tools/make_taxonomy.py data/eBird_Taxonomy_v2026-october-2026.csv \
        -o BirdLog/taxonomy.json

Stdlib only, no network. `--all` gives the unfiltered global taxonomy.

## Data provenance

- `data/eBird_Taxonomy_v2026-october-2026.csv` — eBird/Clements taxonomy (source of truth for names)
- `data/ABA_Checklist-8.19.csv` — ABA area species list (region filter; copyrighted by the ABA, kept here for the hackathon only)
- `samples/ebird_checklist_format_*.xls` — eBird's own blank template and sample; the Step 6 exporter's ground truth
