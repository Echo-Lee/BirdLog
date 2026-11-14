#!/usr/bin/env python3
"""Build a New York State bird checklist (eBird taxonomy subset) from Wikipedia.

Scrapes https://en.wikipedia.org/wiki/List_of_birds_of_New_York_(state) and
intersects it with the local eBird taxonomy CSV by scientific name, falling
back to common-name matching. Writes taxonomy/new_york_species.csv.

This subset (~500 names) fits comfortably inside Argmax's 3000-term custom
vocabulary limit, unlike the full 18.6k-name worldwide taxonomy.
"""
import csv
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TAXONOMY_CSV = ROOT / "taxonomy" / "eBird_Taxonomy_v2026-october-2026.csv"
OUT_CSV = ROOT / "taxonomy" / "new_york_species.csv"
WIKI_URL = ("https://en.wikipedia.org/w/index.php?title="
            "List_of_birds_of_New_York_(state)&action=raw")

# Wikipedia names that eBird renamed (splits/lumps): Wikipedia -> eBird primary_com_name
ALIASES = {
    "cattle egret": "Western Cattle-Egret",
    "hoary redpoll": "Redpoll",
}

# *[[Common name]] or *[[Article title|Common name]], ''Scientific name''
ENTRY_RE = re.compile(
    r"^\*\[\[(?:[^\]|]+\|)?([^\]]+)\]\],?\s*''([A-Za-z][^']+)''")

def fetch_wikitext() -> str:
    req = urllib.request.Request(WIKI_URL, headers={"User-Agent": "BirdLog/0.1"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8")

def parse_entries(wikitext):
    for line in wikitext.splitlines():
        m = ENTRY_RE.match(line.strip())
        if m:
            common = m.group(1).strip()
            sci = m.group(2).strip()
            yield common, sci

def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s.lower()).strip()

def main() -> int:
    with open(TAXONOMY_CSV, newline="", encoding="utf-8-sig") as f:
        rows = list(csv.DictReader(f))

    by_sci = {}
    by_com = {}
    for r in rows:
        if r["category"] != "species":
            continue
        by_sci.setdefault(norm(r["sci_name"]), r)
        by_com.setdefault(norm(r["primary_com_name"]), r)

    entries = list(parse_entries(fetch_wikitext()))
    matched, unmatched = [], []
    for common, sci in entries:
        row = (by_sci.get(norm(sci)) or by_com.get(norm(common))
               or by_com.get(norm(ALIASES.get(norm(common), ""))))
        if row:
            matched.append(row)
        else:
            unmatched.append((common, sci))

    # de-dup by species_code, keep taxonomy order
    seen = set()
    final = []
    for r in matched:
        if r["species_code"] not in seen:
            seen.add(r["species_code"])
            final.append(r)
    final.sort(key=lambda r: float(r["taxon_order"]))

    fields = ["taxon_order", "species_code", "primary_com_name", "sci_name",
              "family", "species_group"]
    with open(OUT_CSV, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        w.writerows(final)

    print(f"Wikipedia entries: {len(entries)}")
    print(f"Matched to eBird taxonomy: {len(final)} -> {OUT_CSV}")
    if unmatched:
        print(f"Unmatched ({len(unmatched)}):")
        for c, s in unmatched:
            print(f"  - {c} ({s})")
    return 0

if __name__ == "__main__":
    sys.exit(main())
