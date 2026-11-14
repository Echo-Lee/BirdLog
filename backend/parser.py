"""Turn a free-text transcript into structured sightings.

Primary path: Bonsai (local LLM) with a strict-JSON prompt.
Fallback path: rule-based regex parser, used when the Bonsai server is not
running so the rest of the backend can be developed and demoed standalone.
"""
from __future__ import annotations

import json
import re
from typing import Optional

SYSTEM_PROMPT = (
    "You extract bird sighting records from spoken birding notes.\n"
    "Return ONLY a JSON array, with no markdown, no code fences, and no extra text.\n"
    "Each element is an object with keys:\n"
    '  "species": string, the bird common name as spoken (e.g. "wood duck");\n'
    '  "count": integer or null, number of birds if stated;\n'
    '  "location": string or null, place if stated;\n'
    '  "notes": string or null, any other detail (behavior, sex, age, time of day).\n'
    "If the text contains no bird sightings, return [].\n"
    "Example input: \"Saw two male wood ducks at Beebe Lake this morning, plus a heron\"\n"
    'Example output: [{"species":"wood duck","count":2,"location":"Beebe Lake",'
    '"notes":"male"},{"species":"heron","count":null,"location":"Beebe Lake","notes":null}]'
)

WORD_NUMBERS = {
    "a": 1, "an": 1, "one": 1, "single": 1, "two": 2, "a pair": 2, "pair": 2,
    "couple": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
    "eight": 8, "nine": 9, "ten": 10, "dozen": 12,
    "fifteen": 15, "twenty": 20, "thirty": 30, "fifty": 50, "hundred": 100,
}


class Parser:
    def __init__(self, bonsai, regional_names: list[str]):
        self.bonsai = bonsai
        self.regional_names = regional_names  # for the fallback parser

    def parse(self, transcript: str) -> tuple[list[dict], str]:
        """Returns (sightings, parser_used)."""
        try:
            return self._parse_bonsai(transcript), "bonsai"
        except Exception:
            return self._parse_fallback(transcript), "fallback"

    # ------------------------------------------------------------------ Bonsai
    def _parse_bonsai(self, transcript: str) -> list[dict]:
        content = self.bonsai.chat(SYSTEM_PROMPT, transcript)
        return json.loads(self._extract_json(content))

    @staticmethod
    def _extract_json(text: str) -> str:
        """Tolerate models that wrap JSON in prose or code fences."""
        text = re.sub(r"```(?:json)?", "", text)
        start, end = text.find("["), text.rfind("]")
        if start == -1 or end == -1:
            raise ValueError(f"no JSON array found in model output: {text[:200]!r}")
        return text[start:end + 1]

    # ---------------------------------------------------------------- fallback
    def _parse_fallback(self, transcript: str) -> list[dict]:
        """Rule-based parser: scan the transcript for known regional species.

        Finds each species mention (longest names first, plurals handled),
        attaches the nearest preceding number, and grabs a Titlecase location
        after 'at/near/by/on/in'.
        """
        text = " " + re.sub(r"[^a-zA-Z0-9'-]", " ", transcript).lower() + " "
        found: list[dict] = []

        # location: up to 4 Titlecase words after a preposition
        loc_match = re.search(
            r"\b(?:at|near|by|on|in|over)\s+((?:[A-Z][\w'-]+)(?:\s+[A-Z][\w'-]+){0,3})",
            transcript)
        location = loc_match.group(1) if loc_match else None

        for name in sorted(self.regional_names, key=len, reverse=True):
            low = name.lower()
            pattern = re.compile(rf"\s(?:{re.escape(low)}|{re.escape(self._plural(low))})\s")
            for m in pattern.finditer(text):
                window = text[max(0, m.start() - 30):m.start()]
                count: Optional[int] = None
                # Closest number to the species name wins.
                for word in reversed(window.split()):
                    if word.isdigit():
                        count = int(word)
                        break
                    if word in WORD_NUMBERS:
                        count = WORD_NUMBERS[word]
                        break
                if any(f["species"] == name for f in found):
                    continue
                found.append({"species": name, "count": count,
                              "location": location, "notes": None})
        return found

    @staticmethod
    def _plural(name: str) -> str:
        words = name.split()
        last = words[-1]
        irregular = {"goose": "geese", "swan": "swans"}
        if last in irregular:
            words[-1] = irregular[last]
        elif last.endswith("s") or last.endswith("x"):
            words[-1] = last  # assume already plural-safe (e.g. 'siskin' handled below)
        else:
            words[-1] = last + "s"
        return " ".join(words)