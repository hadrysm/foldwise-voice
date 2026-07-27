#!/usr/bin/env python3
"""Summarize durable Dictation session timings from history.jsonl."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from statistics import median
from typing import Any

DEFAULT_HISTORY = (
    Path.home()
    / "Library"
    / "Application Support"
    / "FoldWise Voice"
    / "history.jsonl"
)

STAGES = {
    "total": "totalMilliseconds",
    "queued": "queuedMilliseconds",
    "transcribe": "transcribeMilliseconds",
    "polish": "polishMilliseconds",
    "serverTotal": "polishServerMilliseconds",
    "modelLoad": "polishModelLoadMilliseconds",
    "promptEval": "polishPromptEvalMilliseconds",
    "generation": "polishGenerationMilliseconds",
    "insert": "insertMilliseconds",
    "serialTail": "serialTailMilliseconds",
}


def observed_statistics(samples: list[float]) -> dict[str, float]:
    ordered = sorted(samples)
    p95_index = max(0, math.ceil(len(ordered) * 0.95) - 1)
    return {
        "medianMilliseconds": float(median(ordered)),
        "p95Milliseconds": ordered[p95_index],
        "worstMilliseconds": ordered[-1],
    }


def stage_report(entries: list[dict[str, Any]]) -> dict[str, object]:
    stages: dict[str, object] = {}
    for name, field in STAGES.items():
        samples = [
            float(value)
            for entry in entries
            if isinstance((value := entry["timing"].get(field)), (int, float))
            and math.isfinite(value)
            and value >= 0
        ]
        if not samples:
            continue
        stages[name] = {
            "samplesMilliseconds": samples,
            "statistics": observed_statistics(samples),
        }
    return {
        "sampleCount": len(entries),
        "stages": stages,
    }


def build_report(history_path: Path) -> dict[str, object]:
    measured: list[dict[str, Any]] = []
    skipped = 0
    with history_path.open(encoding="utf-8") as history:
        for line in history:
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                skipped += 1
                continue
            if not isinstance(entry, dict) or not isinstance(entry.get("timing"), dict):
                skipped += 1
                continue
            measured.append(entry)

    voice_to_text = [
        entry for entry in measured if entry.get("modeName") == "Voice to Text"
    ]
    polished = [
        entry
        for entry in measured
        if isinstance(entry["timing"].get("polishMilliseconds"), (int, float))
    ]

    return {
        "schemaVersion": 1,
        "source": str(history_path.resolve()),
        "measuredSessions": len(measured),
        "skippedSessions": skipped,
        "groups": {
            "all": stage_report(measured),
            "voiceToText": stage_report(voice_to_text),
            "polish": stage_report(polished),
        },
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Report median, observed p95, and worst per-stage Dictation "
            "session timings from FoldWise history."
        ),
    )
    parser.add_argument(
        "history",
        type=Path,
        nargs="?",
        default=DEFAULT_HISTORY,
        help=f"history.jsonl path (default: {DEFAULT_HISTORY})",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="write the JSON report to this path instead of stdout",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    report = build_report(args.history)
    encoded = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output is None:
        print(encoded, end="")
        return
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(encoded, encoding="utf-8")


if __name__ == "__main__":
    main()
