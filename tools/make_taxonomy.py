#!/usr/bin/env python3
"""Generate BirdLog's bundled taxonomy.json from the eBird taxonomy CSV.

Offline pipeline (stdlib only, no network, no third-party packages):

    data/eBird_Taxonomy_v2026-october-2026.csv
    data/ABA_Checklist-8.19.csv                     (region filter, optional)
        |
        v
    BirdLog/taxonomy.json

Default behavior (D7): the eBird taxonomy is filtered to the ABA (American
Birding Association) area — 11,028 global species become ~1,155 North
American ones. This matters for matching quality: a misheard name should
never land on an obscure global species. Use --all for the unfiltered
global taxonomy.

Matching ABA -> eBird: exact scientific name first, then normalized common
name (the ABA list prints eBird/Clements names as primary where they differ
from AOS, so the fallback is reliable). ABA taxa that match nothing are
EXPECTED to be extinct species (Passenger Pigeon, Hawaiian honeycreepers,
...) or odd (sp.)-level entries; they are reported informationally, not as
errors.

Design decisions baked in (see BIRDLOG_WORK_PLAN.md):
- D4: NO commonness field. The matcher (Step 4) breaks ties by edit distance
  and marks ambiguous exact hits needsReview instead.
- D5: Aliases are derived two ways:
  1. AUTO: the trailing word of a common name becomes an alias when exactly
     one species in the FINAL filtered set ends with that word.
  2. CURATED: a hand list of New York roadside shorthands fills the gaps
     where the trailing word is ambiguous even within the ABA set
     ("robin" -> American Robin). Extend CURATED as real-world speech
     testing reveals gaps; a renamed/excluded target prints a WARNING.

Only category == "species" rows are included (use --categories to widen),
and extinct species are dropped. report_as is ignored: for species rows it
is a self-reference (verified against the 2026-10 CSV).

Output is one JSON array of
    {"common": String, "sci": String?, "aliases": [String]?}
matching BirdCore's Species Codable shape exactly (no commonness).

Usage:
    python3 tools/make_taxonomy.py data/eBird_Taxonomy_v2026-october-2026.csv \\
        -o BirdLog/taxonomy.json
"""

import argparse
import csv
import json
import os
import sys
from collections import Counter

# Lowercase, spelled the way a driver would say them.
# The matcher normalizes again at compare time, so hyphens/possessives are loose.
CURATED = {
    "robin": "American Robin",
    "blue jay": "Blue Jay",
    "chickadee": "Black-capped Chickadee",
    "cardinal": "Northern Cardinal",
    "crow": "American Crow",
    "raven": "Common Raven",
    "goose": "Canada Goose",
    "canadian goose": "Canada Goose",
    "pigeon": "Rock Pigeon",
    "rock dove": "Rock Pigeon",
    "starling": "European Starling",
    "goldfinch": "American Goldfinch",
    "grackle": "Common Grackle",
    "cowbird": "Brown-headed Cowbird",
    "blackbird": "Red-winged Blackbird",
    "bluebird": "Eastern Bluebird",
    "junco": "Dark-eyed Junco",
    "titmouse": "Tufted Titmouse",
    "catbird": "Gray Catbird",
    "mockingbird": "Northern Mockingbird",
    "flicker": "Northern Flicker",
    "turkey": "Wild Turkey",
    "vulture": "Turkey Vulture",
    "phoebe": "Eastern Phoebe",
    "kestrel": "American Kestrel",
    "kingfisher": "Belted Kingfisher",
    "downy": "Downy Woodpecker",
    "hairy": "Hairy Woodpecker",
    "redtail": "Red-tailed Hawk",
    "heron": "Great Blue Heron",
}


def trailing_word(name):
    """Last word of the name, ignoring parenthetical groups."""
    core = name.split(" (")[0]
    words = core.split()
    return words[-1].lower() if words else None


def norm_name(name):
    """Lowercase, whitespace-collapsed, parentheticals stripped."""
    core = name.split(" (")[0]
    return " ".join(core.split()).lower()


def load_ebird(path, categories):
    with open(path, newline="", encoding="utf-8-sig") as f:
        rows = list(csv.DictReader(f))
    wanted = {c.strip() for c in categories.split(",") if c.strip()}
    kept = [r for r in rows if r["category"] in wanted and r.get("extinct") != "1"]
    kept.sort(key=lambda r: int(r["taxon_order"]))
    return kept


def load_aba(path):
    """ABA checklist CSV -> list of (english_name, scientific_name).

    Species rows have an empty first column; metadata and family headers
    have text there.
    """
    out = []
    with open(path, newline="", encoding="utf-8-sig") as f:
        for row in csv.reader(f):
            if len(row) >= 4 and not row[0].strip() and row[1].strip() and row[3].strip():
                out.append((row[1].strip(), row[3].strip()))
    return out


def apply_aba_filter(ebird_rows, aba_path):
    """Keep only eBird species occurring in the ABA area."""
    aba = load_aba(aba_path)
    by_sci = {r["sci_name"].lower(): r for r in ebird_rows}
    by_eng = {}
    for r in ebird_rows:
        by_eng.setdefault(norm_name(r["primary_com_name"]), r)

    keep = set()
    unmatched = []
    for eng, sci in aba:
        r = by_sci.get(sci.lower())
        if r is None:
            r = by_eng.get(norm_name(eng))
        if r is None:
            unmatched.append((eng, sci))
        else:
            keep.add(id(r))

    filtered = [r for r in ebird_rows if id(r) in keep]
    print(f"ABA filter: {len(aba)} ABA taxa -> kept {len(filtered)} eBird species "
          f"({len(unmatched)} ABA taxa have no living eBird 'species' match)")
    for eng, sci in unmatched[:15]:
        print(f"  (expected, excluded) {eng} | {sci}")
    if len(unmatched) > 15:
        print(f"  ... and {len(unmatched) - 15} more")
    return filtered


def main():
    ap = argparse.ArgumentParser(description="Generate taxonomy.json for BirdLog")
    ap.add_argument("csv_path", help="eBird taxonomy CSV")
    ap.add_argument("-o", "--output", default="taxonomy.json", help="output JSON path")
    ap.add_argument("--aba", default="data/ABA_Checklist-8.19.csv",
                    help="ABA checklist CSV for the region filter "
                         "(default: data/ABA_Checklist-8.19.csv)")
    ap.add_argument("--all", action="store_true",
                    help="disable the ABA filter (full global taxonomy)")
    ap.add_argument("--categories", default="species",
                    help="comma-separated eBird categories to include (default: species)")
    args = ap.parse_args()

    included = load_ebird(args.csv_path, args.categories)
    if not args.all:
        if not os.path.exists(args.aba):
            sys.exit(f"ABA checklist not found at {args.aba!r}; pass --all or --aba PATH")
        included = apply_aba_filter(included, args.aba)

    by_common = {r["primary_com_name"]: r for r in included}

    # Trailing-word counts across the FINAL set tell us which shorthands
    # are unambiguous.
    tail_counts = Counter()
    for name in by_common:
        t = trailing_word(name)
        if t:
            tail_counts[t] += 1

    entries = []
    for r in included:
        common = r["primary_com_name"]
        aliases = set()
        t = trailing_word(common)
        if t and tail_counts[t] == 1:
            aliases.add(t)
        entries.append({
            "common": common,
            "sci": r["sci_name"] or None,
            "aliases": sorted(aliases) or None,
        })

    by_common_entry = {e["common"]: e for e in entries}
    warnings = 0
    for alias, target in sorted(CURATED.items()):
        entry = by_common_entry.get(target)
        if entry is None:
            print(f"WARNING: curated alias {alias!r} -> {target!r} not in "
                  f"taxonomy (renamed, or excluded by the ABA filter); "
                  f"fix CURATED.", file=sys.stderr)
            warnings += 1
            continue
        existing = set(entry.get("aliases") or [])
        existing.add(alias)
        entry["aliases"] = sorted(existing)

    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(entries, f, ensure_ascii=False, separators=(",", ":"))

    n_alias = sum(1 for e in entries if e.get("aliases"))
    size = os.path.getsize(args.output)
    print(f"{len(entries)} species written to {args.output} "
          f"({size / 1_000_000:.2f} MB); {n_alias} have aliases "
          f"({len(CURATED)} curated); {warnings} warnings.")
    return 1 if warnings else 0


if __name__ == "__main__":
    raise SystemExit(main())
