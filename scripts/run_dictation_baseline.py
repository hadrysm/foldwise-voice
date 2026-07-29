#!/usr/bin/env python3
"""Run the private-fixture Dictation latency baseline in a packaged Release app."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import subprocess
import wave
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[1]
BUILD_SCRIPT = REPO / "scripts" / "build_swift_app.py"
BUNDLE = (
    REPO
    / "dist"
    / "dictation-baseline-bundle"
    / "FoldWise Voice Native.app"
)
EXECUTABLE = BUNDLE / "Contents" / "MacOS" / "FoldWiseVoice"
PLAN_ENVIRONMENT_KEY = "FOLDWISE_DICTATION_BASELINE_PLAN"


def make_plan(
    *,
    short_audio: Path,
    short_transcript: str,
    long_audio: Path,
    long_transcript: str,
    output: Path,
    samples: int,
    asr_model: str,
    polish_model: str,
) -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "asrModel": asr_model,
        "polishModel": polish_model,
        "sampleCount": samples,
        "outputURL": output.resolve().as_uri(),
        "fixtures": [
            {
                "length": "short",
                "audioURL": short_audio.resolve().as_uri(),
                "expectedTranscript": short_transcript,
            },
            {
                "length": "long",
                "audioURL": long_audio.resolve().as_uri(),
                "expectedTranscript": long_transcript,
            },
        ],
    }


def authority_violations(
    *,
    samples: int,
    asr_model: str,
    polish_model: str,
    fixtures: list[dict[str, object]],
) -> list[str]:
    violations: list[str] = []
    if samples != 20:
        violations.append("recorded samples per class must equal 20")
    if asr_model != "whisper-small":
        violations.append("ASR model must equal whisper-small")
    if polish_model != "qwen2.5:3b":
        violations.append("Polish model must equal qwen2.5:3b")

    fixture_contracts = [
        ("Short", 4.0, 7.0, 45, 70, 8, 12),
        ("Long", 14.0, 20.0, 135, 185, 25, 35),
    ]
    if len(fixtures) != len(fixture_contracts):
        violations.append("fixture matrix must contain Short and Long exactly once")
        return violations

    for fixture, contract in zip(fixtures, fixture_contracts, strict=True):
        label, minimum_duration, maximum_duration, minimum_chars, maximum_chars, \
            minimum_words, maximum_words = contract
        duration = float(fixture["durationSeconds"])
        transcript = str(fixture["expectedTranscript"])
        character_count = len(transcript)
        word_count = len(transcript.split())
        if not minimum_duration <= duration <= maximum_duration:
            violations.append(
                f"{label} duration must be {minimum_duration:g}–{maximum_duration:g} seconds"
            )
        if not minimum_chars <= character_count <= maximum_chars:
            violations.append(
                f"{label} transcript must be {minimum_chars}–{maximum_chars} characters"
            )
        if not minimum_words <= word_count <= maximum_words:
            violations.append(
                f"{label} transcript must be {minimum_words}–{maximum_words} words"
            )
    return violations


def validate_fixture(path: Path, label: str) -> dict[str, object]:
    resolved = path.resolve()
    private_root = (REPO / ".context").resolve()
    if not resolved.is_relative_to(private_root):
        raise SystemExit(f"{label} fixture must live under {private_root}")
    if not resolved.is_file():
        raise SystemExit(f"{label} fixture does not exist: {resolved}")
    ignored = subprocess.run(
        ["git", "check-ignore", "--quiet", str(resolved)],
        cwd=REPO,
        check=False,
    )
    if ignored.returncode != 0:
        raise SystemExit(f"{label} fixture is not gitignored: {resolved}")
    try:
        with wave.open(str(resolved), "rb") as audio:
            channels = audio.getnchannels()
            sample_rate = audio.getframerate()
            frames = audio.getnframes()
    except (EOFError, wave.Error) as error:
        raise SystemExit(f"{label} fixture is not a readable WAV: {error}") from error
    if channels != 1 or sample_rate != 16_000:
        raise SystemExit(
            f"{label} fixture must be 16000 Hz mono; "
            f"found {sample_rate} Hz, {channels} channels"
        )
    if frames < 1_600:
        raise SystemExit(f"{label} fixture must contain at least 0.1 seconds of audio")
    return {
        "path": str(resolved),
        "channels": channels,
        "sampleRate": sample_rate,
        "frames": frames,
        "durationSeconds": round(frames / sample_rate, 6),
    }


def validate_transcript(transcript: str, label: str) -> None:
    if len(transcript) <= 40:
        raise SystemExit(
            f"{label} expected transcript must exceed the 40-character Polish floor"
        )


def build_bundle() -> None:
    subprocess.run(
        [
            "python3",
            str(BUILD_SCRIPT),
            "--dictation-baseline-bundle-only",
        ],
        cwd=REPO,
        check=True,
    )


def clear_previous_run(output: Path) -> None:
    output.unlink(missing_ok=True)
    output.with_suffix(".failure.txt").unlink(missing_ok=True)


def run_plan(plan_path: Path, output: Path, timeout: int) -> dict[str, Any]:
    clear_previous_run(output)
    environment = os.environ.copy()
    environment[PLAN_ENVIRONMENT_KEY] = str(plan_path.resolve())
    result = subprocess.run(
        [str(EXECUTABLE)],
        cwd=REPO,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    output.parent.joinpath("app.stdout.txt").write_text(result.stdout)
    output.parent.joinpath("app.stderr.txt").write_text(result.stderr)
    if not output.exists():
        failure = output.with_suffix(".failure.txt")
        detail = failure.read_text() if failure.exists() else result.stderr
        raise SystemExit(detail or "Dictation baseline app produced no report")
    return json.loads(output.read_text())


def print_summary(report: dict[str, Any], output: Path) -> None:
    print(f"Report: {output}")
    print(
        "shape       length  total median/p95/worst ms    "
        "transcribe median/p95/worst ms"
    )
    for result in report["classes"]:
        total = result["stages"]["total"]["statistics"]
        transcribe = result["stages"]["transcribe"]["statistics"]

        def values(statistics: dict[str, float]) -> str:
            return "/".join(
                f"{statistics[field]:.1f}"
                for field in [
                    "medianMilliseconds",
                    "p95Milliseconds",
                    "worstMilliseconds",
                ]
            )

        print(
            f"{result['shape']:<11} {result['length']:<7} "
            f"{values(total):<28} {values(transcribe)}"
        )


def parse_arguments() -> argparse.Namespace:
    timestamp = dt.datetime.now(dt.UTC).strftime("%Y%m%dT%H%M%SZ")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--short-audio", type=Path, required=True)
    parser.add_argument("--short-transcript", required=True)
    parser.add_argument("--long-audio", type=Path, required=True)
    parser.add_argument("--long-transcript", required=True)
    parser.add_argument(
        "--output-directory",
        type=Path,
        default=REPO / ".context" / f"dictation-baseline-{timestamp}",
    )
    parser.add_argument("--samples", type=int, default=20)
    parser.add_argument("--asr-model", default="whisper-small")
    parser.add_argument("--polish-model", default="qwen2.5:3b")
    parser.add_argument("--timeout", type=int, default=3_600)
    parser.add_argument("--no-build", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_arguments()
    if args.samples <= 0:
        raise SystemExit("--samples must be greater than zero")
    validate_transcript(args.short_transcript, "Short")
    validate_transcript(args.long_transcript, "Long")
    fixture_validation = [
        validate_fixture(args.short_audio, "Short"),
        validate_fixture(args.long_audio, "Long"),
    ]

    output_directory = args.output_directory.resolve()
    output_directory.mkdir(parents=True, exist_ok=True)
    output = output_directory / "dictation-baseline-report.json"
    plan_path = output_directory / "plan.json"
    plan = make_plan(
        short_audio=args.short_audio,
        short_transcript=args.short_transcript,
        long_audio=args.long_audio,
        long_transcript=args.long_transcript,
        output=output,
        samples=args.samples,
        asr_model=args.asr_model,
        polish_model=args.polish_model,
    )
    plan_path.write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n")

    if not args.no_build:
        build_bundle()
    if not EXECUTABLE.exists():
        raise SystemExit(f"Packaged Release executable not found: {EXECUTABLE}")

    report = run_plan(plan_path, output, args.timeout)
    authoritative_fixtures = [
        {
            **fixture_validation[0],
            "expectedTranscript": args.short_transcript,
        },
        {
            **fixture_validation[1],
            "expectedTranscript": args.long_transcript,
        },
    ]
    authority_problems = authority_violations(
        samples=args.samples,
        asr_model=args.asr_model,
        polish_model=args.polish_model,
        fixtures=authoritative_fixtures,
    )
    report["authoritative"] = not authority_problems
    report["authorityViolations"] = authority_problems
    report["fixtureValidation"] = fixture_validation
    report["measurementConfiguration"] = {
        "buildConfiguration": "Release",
        "debugger": False,
        "codeCoverage": False,
        "insertion": "stubbed",
        "realPipeline": True,
        "realEffectiveASRModel": True,
        "realOllama": True,
        "warmUpSamplesDiscardedPerClass": 1,
    }
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print_summary(report, output)
    if not report["authoritative"]:
        print("Non-authoritative run:")
        for problem in authority_problems:
            print(f"- {problem}")


if __name__ == "__main__":
    main()
