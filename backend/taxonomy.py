"""eBird taxonomy access: exact + fuzzy species-name matching.

Loads the worldwide eBird taxonomy and the New York checklist subset.
The worldwide list backs name matching after parsing (Argmax's 3000-term
custom vocabulary limit only constrains ASR, not our matching), while the
NY checklist feeds the Argmax custom vocabulary.
"""
from __future__ import annotations

import csv
import re
from dataclasses import dataclass
from difflib import get_close_matches
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FULL_CSV = ROOT / "taxonomy" / "eBird_Taxonomy_v2026-october-2026.csv"
NY_CSV = ROOT / "taxonomy" / "new_york_species.csv"


@dataclass(frozen=True)
class Match:
    species_code: str
    primary_com_name: str
    sci_name: str
    family: str
    species_group: str
    confidence: float
    scope: str  # "regional" | "worldwide"
    raw: str    # the name as the parser wrote it


# Irregular bird-name plurals the naive 'strip trailing s' rule can't handle.
IRREGULAR_PLURALS = {"geese": "goose"}


def norm(s: str) -> str:
    s = s.lower().replace("-", " ").replace("_", " ")
    return re.sub(r"\s+", " ", s).strip()


class Taxonomy:
    def __init__(self, full_csv: Path = FULL_CSV, ny_csv: Path = NY_CSV):
        self.regional = self._load_csv(ny_csv)
        self.worldwide = self._load_full(full_csv)
        self._regional_keys = list(self.regional)
        self._worldwide_keys = list(self.worldwide)

    @staticmethod
    def _load_csv(path: Path) -> dict:
        out = {}
        with open(path, newline="", encoding="utf-8-sig") as f:
            for r in csv.DictReader(f):
                row = {
                    "species_code": r["species_code"],
                    "primary_com_name": r["primary_com_name"],
                    "sci_name": r["sci_name"],
                    "family": r.get("family", ""),
                    "species_group": r.get("species_group", ""),
                    "taxon_order": float(r.get("taxon_order") or 0),
                }
                out[norm(r["primary_com_name"])] = row
        return out

    @staticmethod
    def _load_full(path: Path) -> dict:
        out = {}
        with open(path, newline="", encoding="utf-8-sig") as f:
            for r in csv.DictReader(f):
                if r["category"] == "species" and r["extinct"] == "0":
                    out[norm(r["primary_com_name"])] = {
                        "species_code": r["species_code"],
                        "primary_com_name": r["primary_com_name"],
                        "sci_name": r["sci_name"],
                        "family": r.get("family", ""),
                        "species_group": r.get("species_group", ""),
                    }
        return out

    @staticmethod
    def _singular(name: str) -> str:
        """Best-effort singular of a bird-name plural ('coots' -> 'coot')."""
        words = name.split()
        if words and words[-1].endswith("s") and not words[-1].endswith("ss"):
            words[-1] = words[-1][:-1]
        return " ".join(words)

    def _suffix_matches(self, n: str, pool: dict) -> list[tuple[float, dict]]:
        """Generic mentions like 'chickadee' or 'merganser' that are not full
        species names. Returns candidates ordered by taxon_order."""
        hits = []
        for key, row in pool.items():
            if key == n:
                continue
            if (len(n.split()) == 1 and key.split()[-1] == n) or key.endswith(" " + n):
                hits.append((row["taxon_order"], row))
        return [row for _, row in sorted(hits, key=lambda t: t[0])]

    def match(self, name: str, fuzzy_cutoff: float = 0.85) -> Match | None:
        """Match a free-text species name against NY checklist, then worldwide.

        Returns None if nothing scores at or above fuzzy_cutoff.
        """
        raw = name.strip()
        n = norm(raw)
        candidates = (n,
                      self._singular(n),
                      " ".join(IRREGULAR_PLURALS.get(w, w) for w in n.split()))
        for candidate in candidates:
            if candidate in self.regional:
                return self._match(self.regional[candidate], raw, 1.0, "regional")

        # Generic mentions: 'chickadee' -> Black-capped Chickadee (first in
        # taxon order among NY candidates), 'merganser' -> Common Merganser.
        generic = self._suffix_matches(candidates[1], self.regional)
        if len(generic) == 1:
            return self._match(generic[0], raw, 0.7, "regional")
        if generic:
            return self._match(generic[0], raw, 0.5, "regional")

        for candidate in candidates:
            if candidate in self.worldwide:
                return self._match(self.worldwide[candidate], raw, 1.0, "worldwide")

        for keys, scope in ((self._regional_keys, "regional"),
                            (self._worldwide_keys, "worldwide")):
            hits = get_close_matches(candidates[1], keys, n=1, cutoff=fuzzy_cutoff)
            if hits:
                return self._match(
                    (self.regional if scope == "regional" else self.worldwide)[hits[0]],
                    raw, get_close_matches_ratio(candidates[1], hits[0]), scope)
        return None

    @staticmethod
    def _match(row: dict, raw: str, confidence: float, scope: str) -> Match:
        return Match(
            species_code=row["species_code"],
            primary_com_name=row["primary_com_name"],
            sci_name=row["sci_name"],
            family=row["family"],
            species_group=row["species_group"],
            confidence=round(confidence, 3),
            scope=scope,
            raw=raw,
        )

    def vocab(self, limit: int = 3000) -> list[str]:
        """Argmax custom vocabulary: NY species primary common names."""
        names = [r["primary_com_name"] for r in self.regional.values()]
        return names[:limit]


def get_close_matches_ratio(query: str, candidate: str) -> float:
    from difflib import SequenceMatcher
    return SequenceMatcher(None, query, candidate).ratio()


def clean_location(location: str | None) -> str | None:
    """Strip leading prepositions/articles the LLM tends to include."""
    if not location:
        return location
    return re.sub(r"^(?:(?:at|near|by|on|in|around)\s+)?(?:the\s+)", "",
                  location.strip(), flags=re.IGNORECASE) or location