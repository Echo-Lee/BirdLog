"""BirdLog backend: transcript -> structured sightings -> CSV.

Endpoints:
  GET  /health      server + Bonsai status
  POST /sightings   {transcript, latitude?, longitude?} -> parse + write CSVs
  GET  /sightings   raw log CSV contents
  GET  /checklist   active eBird checklist session, if any
  GET  /records     eBird Record Format CSV contents
  GET  /vocab       Argmax custom vocabulary (NY species, <= 3000 terms)

Voice commands (handled before parsing, deterministically):
  "Start checklist [at <Place>] [traveling|stationary] [with N observers] [X miles]"
      -> opens a checklist; GPS (latitude/longitude in the request) is stored
         once, here. It is never stored for plain sightings.
  "End checklist [, <comments>]"
      -> backfills duration across the checklist's rows and exports a
         header-less eBird-upload file.

Run:
  uvicorn app:app --reload --port 8000
"""
from __future__ import annotations

import asyncio
import csv
import os
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, PlainTextResponse
from pydantic import BaseModel, Field

from bonsai import BonsaiClient
from ebird import (EbirdCsv, checklist_from_command, comments_after_end,
                   looks_like_end, looks_like_start)
from parser import Parser
from taxonomy import Taxonomy, clean_location

ROOT = Path(__file__).resolve().parents[1]
# Swift CLI (birdlog transcribe) used for on-device ASR. Prefer release build.
_ASR_RELEASE = ROOT / "argmax-client" / ".build" / "release" / "birdlog"
_ASR_DEBUG = ROOT / "argmax-client" / ".build" / "debug" / "birdlog"
ASR_BIN = Path(os.environ.get("BIRDLOG_ASR_BIN",
                              _ASR_RELEASE if _ASR_RELEASE.exists() else _ASR_DEBUG))
RAW_CSV = Path(os.environ.get("BIRDLOG_CSV", ROOT / "data" / "birdlog.csv"))
EBIRD_CSV = Path(os.environ.get("BIRDLOG_EBIRD_CSV", ROOT / "data" / "ebird_records.csv"))
EBIRD_EXPORTS = EBIRD_CSV.parent / "checklists"
DEFAULT_STATE = os.environ.get("BIRDLOG_STATE", "NY")
DEFAULT_COUNTRY = os.environ.get("BIRDLOG_COUNTRY", "US")
FALLBACK = os.environ.get("BIRDLOG_ALLOW_FALLBACK", "1") == "1"

CSV_FIELDS = [
    "logged_at", "species_code", "primary_com_name", "sci_name", "family",
    "species_group", "count", "location", "notes", "raw_transcript",
    "match_confidence", "match_scope", "parser",
]

taxonomy = Taxonomy()
bonsai = BonsaiClient()
parser = Parser(bonsai, taxonomy.vocab())
ebird = EbirdCsv(EBIRD_CSV, EBIRD_EXPORTS)

# One checklist session at a time, held in memory.
active_checklist = None

app = FastAPI(title="BirdLog backend", version="0.2")
app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


class SightingRequest(BaseModel):
    transcript: str = Field(..., description="Raw spoken/typed birding note")
    latitude: Optional[float] = None
    longitude: Optional[float] = None


def append_raw(rows: list[dict]) -> None:
    RAW_CSV.parent.mkdir(parents=True, exist_ok=True)
    new_file = not RAW_CSV.exists()
    with open(RAW_CSV, "a", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=CSV_FIELDS)
        if new_file:
            w.writeheader()
        for row in rows:
            w.writerow({k: row.get(k, "") for k in CSV_FIELDS})


@app.get("/health")
def health():
    return {
        "status": "ok",
        "bonsai_url": bonsai.base_url,
        "bonsai_available": bonsai.available(),
        "regional_species": len(taxonomy.regional),
        "worldwide_species": len(taxonomy.worldwide),
        "raw_csv": str(RAW_CSV),
        "ebird_csv": str(EBIRD_CSV),
        "active_checklist": active_checklist.summary() if active_checklist else None,
        "fallback_allowed": FALLBACK,
    }


def process_transcript(transcript: str, latitude: float | None,
                       longitude: float | None) -> dict:
    """The shared pipeline: voice commands -> Bonsai parse -> taxonomy -> CSVs."""
    global active_checklist

    commands: list[str] = []
    finalized = None

    # 1. "Start checklist" — GPS is captured here and only here.
    if looks_like_start(transcript):
        if active_checklist:
            # Close the dangling one before starting a new session.
            active_checklist.submission_comments = "superseded by a new checklist"
            export = ebird.finalize(active_checklist)
            finalized = {**active_checklist.summary(), "export": str(export)}
        cid = datetime.now().strftime("%Y%m%d-%H%M%S")
        active_checklist = checklist_from_command(
            transcript, cid, latitude, longitude,
            DEFAULT_STATE, DEFAULT_COUNTRY)
        commands.append("start_checklist")

    # 2. Species sightings (Bonsai, or regex fallback).
    parsed, parser_used = parser.parse(transcript)
    if not parsed and parser_used == "fallback" and not FALLBACK:
        raise HTTPException(503, "Bonsai server unavailable and fallback disabled")

    raw_rows = []
    ebird_rows = []
    for s in parsed:
        species_raw = str(s.get("species") or "").strip()
        match = taxonomy.match(species_raw) if species_raw else None
        if species_raw and match:
            name, sci = match.primary_com_name, match.sci_name
            match_scope, confidence = match.scope, match.confidence
        else:
            name, sci = species_raw, ""
            match_scope, confidence = "unmatched", 0.0

        row = {
            "logged_at": datetime.now().isoformat(timespec="seconds"),
            "species_code": match.species_code if match else "",
            "primary_com_name": name, "sci_name": sci,
            "family": match.family if match else "",
            "species_group": match.species_group if match else "",
            "count": s.get("count"),
            "location": clean_location(s.get("location")),
            "notes": s.get("notes"), "raw_transcript": transcript,
            "match_confidence": confidence, "match_scope": match_scope,
            "parser": parser_used,
        }
        raw_rows.append(row)

        if active_checklist:
            ebird_rows.append(active_checklist.observation_row(
                name, sci, s.get("count"), s.get("notes")))

    append_raw(raw_rows)
    ebird.append(ebird_rows)

    # 3. "End checklist" — backfill duration + comments, export upload file.
    if looks_like_end(transcript):
        commands.append("end_checklist")
        if active_checklist:
            active_checklist.submission_comments = comments_after_end(transcript)
            export = ebird.finalize(active_checklist)
            finalized = {**active_checklist.summary(), "export": str(export)}
            active_checklist = None

    return {
        "commands": commands,
        "checklist": active_checklist.summary() if active_checklist else None,
        "checklist_finalized": finalized,
        "parser": parser_used,
        "sightings_found": len(parsed),
        "rows_written": len(raw_rows),
        "ebird_rows_written": len(ebird_rows),
        "rows": raw_rows,
    }


@app.post("/sightings")
def add_sightings(req: SightingRequest):
    transcript = req.transcript.strip()
    if not transcript:
        raise HTTPException(422, "transcript must not be empty")
    return process_transcript(transcript, req.latitude, req.longitude)


# ----------------------------------------------------------------- voice ASR
def run_asr(wav_path: str) -> str | None:
    """On-device ASR via the Swift birdlog CLI (Argmax WhisperKit)."""
    cmd = [str(ASR_BIN), "transcribe", wav_path,
           "--dry-run", "--transcript-only"]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    except Exception as e:
        print(f"ASR failed to run: {e}", file=sys.stderr)
        return None
    if proc.returncode != 0:
        print(f"ASR error: {proc.stderr[-800:]}", file=sys.stderr)
        return None
    return proc.stdout.strip()


@app.post("/voice")
async def add_voice(request: Request, latitude: Optional[float] = None,
                   longitude: Optional[float] = None):
    """Raw 16 kHz WAV body -> on-device ASR (Swift) -> the sighting pipeline."""
    body = await request.body()
    if not body:
        raise HTTPException(422, "empty audio body")
    if not ASR_BIN.exists():
        raise HTTPException(503, f"ASR binary not found at {ASR_BIN} — build argmax-client first")

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        f.write(body)
        wav_path = f.name
    try:
        transcript = await asyncio.to_thread(run_asr, wav_path)
    finally:
        os.unlink(wav_path)

    if not transcript:
        raise HTTPException(500, "ASR returned no transcript (see backend log)")

    print(f"[voice] transcript: {transcript!r}", flush=True)
    result = process_transcript(transcript, latitude, longitude)
    result["transcript"] = transcript
    if result["rows"]:
        print(f"[voice] parsed {len(result['rows'])} sighting(s)", flush=True)
    else:
        print("[voice] no sightings parsed from this transcript", flush=True)
    return result


@app.get("/sightings")
def list_sightings():
    if not RAW_CSV.exists():
        return {"rows": []}
    with open(RAW_CSV, newline="", encoding="utf-8") as f:
        return {"rows": list(csv.DictReader(f))}


@app.get("/checklist")
def get_checklist():
    return {"checklist": active_checklist.summary() if active_checklist else None}


@app.get("/test", response_class=FileResponse)
def test_page():
    """Serves the test client over http://localhost:8000 — getUserMedia needs
    a secure context, which file:// pages aren't in some browsers."""
    return FileResponse(Path(__file__).parent / "test.html")


@app.get("/records")
def list_records():
    if not EBIRD_CSV.exists():
        return {"rows": []}
    with open(EBIRD_CSV, newline="", encoding="utf-8") as f:
        return {"rows": list(csv.DictReader(f))}


@app.get("/vocab")
def vocab(limit: int = 3000, format: str = "json"):
    names = taxonomy.vocab(min(limit, 3000))
    if format == "text":
        return PlainTextResponse("\n".join(names))
    return {"count": len(names), "terms": names}


@app.get("/species/search")
def species_search(q: str, scope: str = "regional"):
    n = q.lower()
    pool = taxonomy.regional if scope == "regional" else taxonomy.worldwide
    hits = [r for name, r in pool.items() if n in name][:25]
    return {"query": q, "results": hits}