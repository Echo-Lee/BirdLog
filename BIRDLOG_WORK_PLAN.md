# BirdLog — 2-Person Work Plan (24h Hackathon)

Everything non-UI lives in the `BirdCore` Swift package (`swift test` on macOS is the merge gate).
The iOS app target holds only UI, audio, location, and intents.

---

## Current status

- **Step 1 (models) — code complete, not yet merged.** Revised per decisions:
  `Species` non-optional on `Observation` (ambiguous match → synthesized species holding
  the spoken text + `needsReview`), count enum with **X as the default** (a later spoken
  number upgrades X in the engine), straight-line start↔end distance (no continuous GPS
  accumulation), frozen `startClock`, always Traveling + All Obs Reported Y at export.
- **Gate:** `cd BirdCore && swift test` → 8 tests green, then merge Step 1 and freeze
  `Sources/BirdCore/Models/**` (changes after this point only by agreement/PR).
- **Data:** IN THE REPO — `tools/make_taxonomy.py` regenerates `BirdLog/taxonomy.json`
  (ABA-filtered: 1,155 species, 30 curated shorthands). Sources live in `data/`
  (eBird taxonomy CSV + ABA checklist), eBird templates in `samples/`.

---

## Decisions (all RESOLVED)

| # | Resolution |
|---|------------|
| D1 | Export = wide spreadsheet layout from the eBird template (one column per checklist), emitted as CSV with proper quoting |
| D2 | Species comments fold into the checklist Notes row as `Name: comment`, joined by `; ` |
| D3 | Export the real straight-line distance, rounded to 0.1 mi, **floored at 0.1 mi** (applied in the Step 6 exporter) |
| D4 | **No `commonness` field anywhere.** Matcher ties break by edit distance; ambiguous exact hits → `needsReview`. Shorthand support comes from aliases (D5) |
| D5 | Aliases = auto-derived (trailing word, unique within the final set) + 30 curated NY roadside shorthands. **Done:** `tools/make_taxonomy.py` |
| D6 | Count token stays uppercase `X` |
| D7 | Taxonomy defaults to the **ABA area** filter (`data/ABA_Checklist-8.19.csv`): 11,028 global species → 1,155 North American (better matching quality, ~10x smaller JSON). ABA entries with no match are expected (extinct species, `(sp.)` forms). `--all` bypasses |

---

## Track A — "Voice in": text → parse → speech layer

| Step | Deliverable | Tests A owns |
|------|-------------|--------------|
| **2** | `Text/` normalization (lowercase, strip apostrophes, hyphens→spaces, grey→gray, simple plurals incl. geese) + `NumberWords` (digits, "two", "twenty five", "a dozen", trailing counts) | Number words incl. edge cases; normalization table |
| **3** | `Parsing/` `VoiceCommand` model + deterministic `CommandParser` (species phrase, count, comma/`comment` split, filler words, `scratch that`, `end checklist`) | Every utterance example from the spec |
| **7a** | App: `Speech/SpeechListener` (`SpeechListening` protocol, SFSpeechRecognizer `requiresOnDeviceRecognition = true`, contextualStrings, never server), `Speech/Speaker` (AVSpeechSynthesizer), mute recognizer while speaking, `Intents/` Start/End checklist + AppShortcuts phrase, Info.plist keys + background modes | Manual (can't run on macOS) — see device checklist |

**First priority: Step 2 — B is blocked on it for the matcher.** Deliver it within the
first hour, alone, before starting Step 3.

## Track B — "Data out": match → engine → export → location

| Step | Deliverable | Tests B owns |
|------|-------------|--------------|
| **4** | `Matching/SpeciesMatcher`: exact / edit-distance / Soundex-style scoring, alias shorthands (no commonness — D4), ambiguity → `needsReview` with spoken text | Mishearings: "yellow rump warbler", "cooper hawk", "morning dove", "grey jay", plural "geese" |
| **5** | `Engine/ChecklistEngine`: start, add (X default, spoken number upgrades/replaces), merge duplicate species, comment attach, `scratch that` undo, end, persistence hooks | Add/merge/upgrade/undo/end sequences |
| **6** | `Export/` wide-format exporter + warnings (< 1 MB, strip quotes, commas→semicolons in free text, no line breaks), distance floored at 0.1 mi (D3), Rock Pigeon written as "Rock Pigeon (Feral Pigeon)", one place defining layout constants | Exact expected CSV string for a fixture checklist |
| **7b** | App: `Location/LocationTracker` (one best-accuracy fix at start with retroactive fill-in, one at end — no continuous tracking), JSON state save on every mutation + restore on launch, ShareLink export | Manual — see device checklist |

## Shared / integration (both, final ~6 hours)

- `AppModel`: recognizer result → parser → matcher → engine → spoken confirmation.
  Concurrency rule: audio tap / recognition callbacks are built in nonisolated contexts,
  then hop to `@MainActor`.
- `Views/ChecklistView` + share sheet export.
- Trial upload to ebird.org with one throwaway checklist to verify the CSV is accepted
  (settles D1's file-type question and date-format risk in one shot).

## File ownership map (conflict avoidance)

- **A:** `Sources/BirdCore/Text/**`, `Sources/BirdCore/Parsing/**`, their tests,
  app `Speech/`, `Intents/`
- **B:** `Sources/BirdCore/Matching/**`, `Sources/BirdCore/Engine/**`,
  `Sources/BirdCore/Export/**`, their tests, app `Location/`, state persistence
- **Frozen after Step 1 (change only via agreed PR):** `Sources/BirdCore/Models/**`
- **Co-owned (pair or careful coordination):** `AppModel.swift`, `Views/`, Info.plist,
  `taxonomy.json` generator script

## Suggested clock (24h)

| Hours | A | B |
|-------|---|---|
| 0–1 | Merge Step 1 together (structure, models, data all in repo now) | Same |
| 1–2 | **Step 2** (text + numbers) + tests | Review Step 2; scaffold matcher, prep real `taxonomy.json` |
| 2–5 | Step 3 (parser) + tests | Step 4 (matcher) + tests |
| 5–8 | Start 7a: SpeechListening + Speaker | Step 5 (engine) + tests |
| 8–14 | Finish 7a: intents, AppShortcuts, Info.plist | Step 6 (exporter) + tests |
| 14–18 | AppModel wiring with B (pair) | LocationTracker + persistence |
| 18–20 | Views + ShareLink | eBird trial upload (settles D1, D6, date format) |
| 20–24 | Device checklist + bug fixes | Device checklist + bug fixes |

## Merge rules

- One branch per step (`feat/parser`, `feat/matcher`, …), reviewed by the other dev.
- Every PR must leave `cd BirdCore && swift test` green; app-target code is gated by the
  manual device checklist below instead.
- Don't refactor shared files opportunistically; hackathon, keep diffs small.

## Manual device test checklist (both, at the end)

1. "Hey Siri, start checklist in BirdLog" opens app, checklist starts, start time correct.
2. "two black-capped chickadees, one singing" → spoken "Black-capped Chickadee, 2", comment captured.
3. "robin" → "American Robin, X" — then "robin two" upgrades X → 2 (single row, not two).
4. "a flock of geese" → X count, correct species (plural handling).
5. "comment singing from a spruce" attaches to the last entry.
6. "yellow rump warbler" (deliberate mishearing) → needsReview, exported as spoken text.
7. "scratch that" removes last entry; app says what it removed.
8. App stays silent on noise / unmatched babble (no error speech).
9. Recognizer does not transcribe the app's own spoken confirmations.
10. Background: lock screen, checklist keeps recording for 10+ min of driving.
11. Force-quit mid-checklist → relaunch restores the in-progress checklist.
12. "End checklist" closes it; GPS start fix backfilled if first fix was late.
13. Export multiple checklists → one CSV, opens in Numbers/Excel matching the eBird template shape; upload trial succeeds.
