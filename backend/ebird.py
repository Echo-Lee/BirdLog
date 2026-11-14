"""eBird Record Format output and voice-command checklist sessions.

Format per https://support.ebird.org/en/support/solutions/articles/48000907878:
19 fixed columns, month/day/year dates, military start times, duration in
minutes, count can be a number or X, GPS in decimal degrees. The header row
must be removed before uploading, so we also export a header-less file per
checklist when it is finalized.

Voice commands handled here (detected deterministically, not by the LLM):
  "Start checklist [at <Place>] [traveling|stationary] [N observers] [X miles]"
  "End checklist [, <submission comments>]"
"""
from __future__ import annotations

import csv
import re
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

# Column order must match the eBird Record Format template exactly.
EBIRD_FIELDS = [
    "Common Name", "Genus", "Species", "Number", "Species Comments",
    "Location Name", "Latitude", "Longitude", "Date", "Start Time",
    "State/Province", "Country", "Protocol", "Number of Observers",
    "Duration", "All observations reported?", "Effort Distance",
    "Effort area acres", "Submission Comments",
]

# eBird import asks for these spellings (see "Additional notes" in the guide).
EBIRD_NAME_FIXES = {
    "Rock Pigeon": "Rock Pigeon (Feral Pigeon)",
}

# (?:...\s+){0,3} allows modifiers: "start a traveling checklist",
# "end the stationary checklist at the marsh", etc.
START_RE = re.compile(
    r"\b(?:start|begin|beginning|new|starting)\s+"
    r"(?:an?\s+|the\s+|this\s+)?(?:[a-z'\-]+\s+){0,3}checklist\b",
    re.IGNORECASE)
END_RE = re.compile(
    r"\b(?:end|ending|finish|finishing|close|closing|stop|wrap\s+up)\s+"
    r"(?:the\s+|this\s+|my\s+|our\s+)?(?:[a-z'\-]+\s+){0,3}checklist\b",
    re.IGNORECASE)

PROTOCOLS = ("Traveling", "Stationary", "Incidental", "Historical")
WORD_OBSERVERS = {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
                  "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10}


@dataclass
class Checklist:
    id: str
    location_name: str
    latitude: float | None
    longitude: float | None
    start: datetime
    protocol: str = "Stationary"
    state: str = "NY"
    country: str = "US"
    observers: int = 1
    effort_distance: str = ""        # miles; Traveling only
    submission_comments: str = ""
    row_count: int = 0

    @property
    def date_str(self) -> str:
        return f"{self.start.month}/{self.start.day}/{self.start.year}"

    @property
    def time_str(self) -> str:
        return self.start.strftime("%H:%M")

    def metadata(self) -> dict:
        return {
            "Location Name": self.location_name,
            "Latitude": "" if self.latitude is None else f"{self.latitude:.5f}",
            "Longitude": "" if self.longitude is None else f"{self.longitude:.5f}",
            "Date": self.date_str,
            "Start Time": self.time_str,
            "State/Province": self.state,
            "Country": self.country,
            "Protocol": self.protocol,
            "Number of Observers": str(self.observers),
            "All observations reported?": "Y",
            "Effort Distance": self.effort_distance,
            "Effort area acres": "",
        }

    def observation_row(self, common_name: str, sci_name: str, count,
                        notes: str | None) -> dict:
        genus, species = split_sci_name(sci_name)
        row = {
            "Common Name": EBIRD_NAME_FIXES.get(common_name, common_name),
            "Genus": genus,
            "Species": species,
            "Number": "X" if count in (None, "", 0) else str(count),
            "Species Comments": notes or "",
        }
        row.update(self.metadata())
        row.update({"Duration": "", "Submission Comments": ""})
        self.row_count += 1
        return row

    def summary(self) -> dict:
        return {
            "id": self.id, "location_name": self.location_name,
            "latitude": self.latitude, "longitude": self.longitude,
            "date": self.date_str, "start_time": self.time_str,
            "protocol": self.protocol, "observers": self.observers,
            "effort_distance": self.effort_distance,
            "rows": self.row_count,
        }


def split_sci_name(sci_name: str) -> tuple[str, str]:
    parts = (sci_name or "").split()
    return (parts[0] if parts else "", parts[1] if len(parts) > 1 else "")


def looks_like_start(transcript: str) -> bool:
    return bool(START_RE.search(transcript))


def looks_like_end(transcript: str) -> bool:
    return bool(END_RE.search(transcript))


def checklist_from_command(transcript: str, checklist_id: str,
                           latitude: float | None, longitude: float | None,
                           state: str, country: str) -> Checklist:
    """Parse "start checklist ..." options from the command utterance."""
    start = datetime.now()

    protocol = "Stationary"
    for p in PROTOCOLS:
        if re.search(rf"\b{p.lower()}\b", transcript, re.IGNORECASE):
            protocol = p
            break

    m = re.search(
        r"checklist\s+(?:at|near|by|in|on)\s+"
        r"((?:[A-Z][\w'-]*)(?:\s+[A-Z][\w'-]*){0,4})", transcript)
    location_name = m.group(1) if m else f"Voice Checklist {checklist_id}"

    distance = ""
    if protocol == "Traveling":
        d = re.search(r"(\d+(?:\.\d+)?)\s*(?:miles?\b|mi\b)", transcript,
                      re.IGNORECASE)
        distance = d.group(1) if d else ""

    m = re.search(r"(?:with\s+)?(\d+|one|two|three|four|five|six|seven|"
                  r"eight|nine|ten)\s*(?:other\s+)?(?:people\s+)?observers?\b",
                  transcript, re.IGNORECASE)
    observers = 1
    if m:
        observers = int(m.group(1)) if m.group(1).isdigit() \
            else WORD_OBSERVERS[m.group(1).lower()]

    return Checklist(
        id=checklist_id, location_name=location_name,
        latitude=latitude, longitude=longitude, start=start,
        protocol=protocol, state=state, country=country,
        observers=observers, effort_distance=distance)


def comments_after_end(transcript: str) -> str:
    """'End checklist, windy and warm' -> 'windy and warm'."""
    m = END_RE.search(transcript)
    tail = transcript[m.end():].strip(" ,.")
    return tail


class EbirdCsv:
    """Appends observation rows to the master CSV and finalizes checklists."""

    def __init__(self, path: Path, export_dir: Path):
        self.path = path
        self.export_dir = export_dir

    def append(self, rows: list[dict]) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        new_file = not self.path.exists()
        with open(self.path, "a", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=EBIRD_FIELDS)
            if new_file:
                w.writeheader()
            for row in rows:
                w.writerow({k: row.get(k, "") for k in EBIRD_FIELDS})

    def finalize(self, checklist: Checklist) -> Path:
        """Backfill Duration + Submission Comments for the checklist's rows,
        then export a header-less file ready for eBird import."""
        with open(self.path, newline="", encoding="utf-8") as f:
            all_rows = list(csv.DictReader(f))

        # eBird expects at least 1 minute of effort.
        duration = str(max(1, int((datetime.now() - checklist.start)
                                  .total_seconds() // 60)))
        checklist_rows = []
        for row in all_rows:
            is_ours = (row.get("Date") == checklist.date_str
                       and row.get("Start Time") == checklist.time_str
                       and row.get("Location Name") == checklist.location_name
                       and row.get("Duration") == "")
            if is_ours:
                row["Duration"] = duration
                row["Submission Comments"] = checklist.submission_comments
                checklist_rows.append(row)

        with open(self.path, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=EBIRD_FIELDS)
            w.writeheader()
            w.writerows(all_rows)

        # Header-less export, per the eBird import requirements.
        self.export_dir.mkdir(parents=True, exist_ok=True)
        export = self.export_dir / f"ebird-upload-{checklist.id}.csv"
        with open(export, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=EBIRD_FIELDS)
            w.writerows(checklist_rows)
        return export