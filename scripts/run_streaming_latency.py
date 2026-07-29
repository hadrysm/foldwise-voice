#!/usr/bin/env python3
"""Run the fixed-Mac streaming latency release gate (issue #358).

One packaged Release process per Streaming ASR model, so each model's integrated
peak footprint and maximum RSS belong to that model alone. The per-model reports
are merged into one gate report; every pass/fail decision lives in the Swift
`StreamingLatencyGate`, which this script invokes through `swift test`.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import plistlib
import subprocess
import wave
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[1]
BUILD_SCRIPT = REPO / "scripts" / "build_swift_app.py"
BUNDLE = REPO / "dist" / "streaming-latency-bundle" / "FoldWise Voice Native.app"
EXECUTABLE = BUNDLE / "Contents" / "MacOS" / "FoldWiseVoice"
DEFAULT_BASELINES = REPO / "docs" / "streaming-latency-baselines.json"
PLAN_ENVIRONMENT_KEY = "FOLDWISE_STREAMING_LATENCY_PLAN"

STREAMING_MODELS = ["parakeet-eou-320", "nemotron-560"]
REFERENCE_MAC = "foldwise-streaming-reference"
REQUIRED_SAMPLE_COUNT = 20
# The unconditional clipboard settle in TextInsertionSystem.postPaste.
MINIMUM_INSERT_CONSTANT_MILLISECONDS = 50.0


def make_plan(
    *,
    asr_model: str,
    polish_model: str,
    samples: int,
    insert_constant_milliseconds: float,
    output: Path,
    short_audio: Path,
    long_audio: Path,
) -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "asrModel": asr_model,
        "polishModel": polish_model,
        "sampleCount": samples,
        "insertConstantMilliseconds": insert_constant_milliseconds,
        "outputURL": output.resolve().as_uri(),
        "fixtures": [
            {"length": "short", "audioURL": short_audio.resolve().as_uri()},
            {"length": "long", "audioURL": long_audio.resolve().as_uri()},
        ],
    }


def authority_violations(
    *,
    samples: int,
    models: list[str],
    reference_mac: str,
    polish_model: str,
) -> list[str]:
    """Why this run may not claim to be authoritative.

    Duration limits, matrix completeness, and evidence are judged by the Swift
    gate. This list only covers what the launcher itself chose.
    """
    violations: list[str] = []
    if samples != REQUIRED_SAMPLE_COUNT:
        violations.append(
            f"recorded samples per class must equal {REQUIRED_SAMPLE_COUNT}"
        )
    if models != STREAMING_MODELS:
        violations.append(
            "both shipped Streaming ASR models must be measured: "
            + ", ".join(STREAMING_MODELS)
        )
    if reference_mac != REFERENCE_MAC:
        violations.append(f"reference Mac must be {REFERENCE_MAC}")
    if polish_model != "qwen2.5:3b":
        violations.append("Polish model must equal qwen2.5:3b")
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


def run_text(command: list[str]) -> str:
    result = subprocess.run(command, check=False, capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else ""


def environment_metadata(reference_mac: str) -> dict[str, object]:
    info = plistlib.loads((BUNDLE / "Contents" / "Info.plist").read_bytes())
    return {
        "referenceMac": reference_mac,
        "buildConfiguration": "Release",
        "debuggerAttached": False,
        "codeCoverage": False,
        "sanitizers": False,
        "commit": run_text(["git", "-C", str(REPO), "rev-parse", "HEAD"]),
        "appVersion": str(info.get("CFBundleVersion", "")),
        "bundlePath": str(BUNDLE.resolve()),
        "hardwareModel": run_text(["sysctl", "-n", "hw.model"]),
        "chip": run_text(["sysctl", "-n", "machdep.cpu.brand_string"]),
        "memoryBytes": run_text(["sysctl", "-n", "hw.memsize"]),
        "macOS": run_text(["sw_vers"]),
        "xcode": run_text(["xcodebuild", "-version"]),
        "power": run_text(["pmset", "-g", "batt"]),
        "thermal": run_text(["pmset", "-g", "therm"]),
    }


def build_bundle() -> None:
    subprocess.run(
        ["python3", str(BUILD_SCRIPT), "--streaming-latency-bundle-only"],
        cwd=REPO,
        check=True,
    )


def run_plan(plan_path: Path, output: Path, timeout: int) -> dict[str, Any]:
    output.unlink(missing_ok=True)
    output.with_suffix(".failure.txt").unlink(missing_ok=True)
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
        raise SystemExit(detail or "Streaming latency app produced no report")
    return json.loads(output.read_text())


def merge_reports(
    runs: list[dict[str, Any]],
    *,
    samples: int,
    environment: dict[str, object],
    standalone_maximum_resident_bytes: int,
    memory_ceiling_reviewed: bool,
    authoritative: bool,
    violations: list[str],
) -> dict[str, Any]:
    """One gate report from the per-model runs.

    Fixture identity is taken from the first run and cross-checked against the
    others: two models that measured different audio are not one matrix.
    """
    fixtures = [
        {
            "length": fixture["length"],
            "sha256": fixture["sha256"],
            "durationSeconds": fixture["durationSeconds"],
            "speechOnsetSeconds": fixture["speechOnsetSeconds"],
        }
        for fixture in runs[0]["fixtures"]
    ]
    for run in runs[1:]:
        observed = [
            {
                "length": fixture["length"],
                "sha256": fixture["sha256"],
                "durationSeconds": fixture["durationSeconds"],
                "speechOnsetSeconds": fixture["speechOnsetSeconds"],
            }
            for fixture in run["fixtures"]
        ]
        if observed != fixtures:
            violations.append(
                f"{run['asrModel']} measured different fixtures from "
                f"{runs[0]['asrModel']}"
            )
    return {
        "schemaVersion": 1,
        "authoritative": authoritative and not violations,
        "authorityViolations": sorted(violations),
        "recordedSamplesPerClass": samples,
        "warmUpSamplesDiscardedPerClass": 1,
        "environment": environment,
        "fixtures": fixtures,
        "memoryCeiling": {
            "standaloneMaximumResidentBytes": standalone_maximum_resident_bytes,
            "humanReviewed": memory_ceiling_reviewed,
            "source": (
                "docs/research/streaming-asr-path-evaluation.md — Nemotron 560 "
                "standalone peak footprint / max RSS 1.092 / 1.227 GB"
            ),
        },
        "models": [
            {
                "asrModel": run["asrModel"],
                "effectiveASRModel": run["effectiveASRModel"],
                "polishModel": run["polishModel"],
                "insertion": run["insertion"],
                "insertConstantMilliseconds": run["insertConstantMilliseconds"],
                "residency": run["residency"],
                "classes": run["classes"],
            }
            for run in runs
        ],
    }


def verify_through_xctest(report: Path, baselines: Path) -> int:
    """The same limits, re-read from the retained artifact by the Swift gate."""
    environment = os.environ.copy()
    environment["FOLDWISE_STREAMING_LATENCY_REPORT"] = str(report.resolve())
    environment["FOLDWISE_STREAMING_LATENCY_BASELINES"] = str(baselines.resolve())
    result = subprocess.run(
        [
            "swift", "test", "-c", "release", "--filter",
            "StreamingLatencyGateTests/testFixedMacReportMeetsTheLockedLatencyBudget",
        ],
        cwd=REPO,
        env=environment,
        check=False,
    )
    return result.returncode


def print_summary(report: dict[str, Any], output: Path) -> None:
    print(f"Report: {output}")
    print("model              length  shape        first-feedback p95  post-release p95")
    for model in report["models"]:
        for measured in model["classes"]:
            first = statistic(measured.get("firstFeedback"))
            post = statistic(measured.get("postRelease"))
            gate = "" if measured.get("postReleaseLimitMilliseconds") else "  (recorded)"
            print(
                f"{model['asrModel']:<18} {measured['length']:<7} "
                f"{measured['shape']:<12} {first:>18} {post:>17}{gate}"
            )
        residency = model["residency"]
        print(
            f"{model['asrModel']:<18} residency: peak footprint "
            f"{residency['peakFootprintBytes']} B, maximum RSS "
            f"{residency['maximumResidentBytes']} B, "
            f"{residency['residentASREngineCount']} resident engine(s)"
        )


def statistic(statistics: dict[str, float] | None) -> str:
    if not statistics:
        return "n/a"
    return f"{statistics['p95Milliseconds']:.1f}"


def parse_arguments() -> argparse.Namespace:
    timestamp = dt.datetime.now(dt.UTC).strftime("%Y%m%dT%H%M%SZ")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--short-audio", type=Path, required=True)
    parser.add_argument("--long-audio", type=Path, required=True)
    parser.add_argument(
        "--insert-constant-milliseconds", type=float, required=True,
        help="the separately measured Accessibility paste constant, added to "
             "every post-release total (see docs/streaming-latency-harness.md)",
    )
    parser.add_argument(
        "--output-directory",
        type=Path,
        default=REPO / ".context" / f"streaming-latency-{timestamp}",
    )
    parser.add_argument("--baselines", type=Path, default=DEFAULT_BASELINES)
    parser.add_argument("--samples", type=int, default=REQUIRED_SAMPLE_COUNT)
    parser.add_argument("--models", nargs="+", default=STREAMING_MODELS)
    parser.add_argument("--reference-mac", default=REFERENCE_MAC)
    parser.add_argument("--polish-model", default="qwen2.5:3b")
    parser.add_argument(
        "--memory-ceiling-reviewed", action="store_true",
        help="a maintainer has reviewed the documented memory ceiling for this run",
    )
    parser.add_argument("--timeout", type=int, default=7_200)
    parser.add_argument("--no-build", action="store_true")
    parser.add_argument("--skip-xctest", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_arguments()
    if args.samples <= 0:
        raise SystemExit("--samples must be greater than zero")
    if args.insert_constant_milliseconds < MINIMUM_INSERT_CONSTANT_MILLISECONDS:
        raise SystemExit(
            "--insert-constant-milliseconds must be at least "
            f"{MINIMUM_INSERT_CONSTANT_MILLISECONDS:g}; a smaller value proves "
            "Accessibility insertion was never exercised"
        )
    fixture_validation = [
        validate_fixture(args.short_audio, "Short"),
        validate_fixture(args.long_audio, "Long"),
    ]

    output_directory = args.output_directory.resolve()
    output_directory.mkdir(parents=True, exist_ok=True)
    if not args.no_build:
        build_bundle()
    if not EXECUTABLE.exists():
        raise SystemExit(f"Packaged Release executable not found: {EXECUTABLE}")

    runs: list[dict[str, Any]] = []
    for model in args.models:
        model_directory = output_directory / "raw" / model
        model_directory.mkdir(parents=True, exist_ok=True)
        model_output = model_directory / "result.json"
        plan_path = model_directory / "plan.json"
        plan = make_plan(
            asr_model=model,
            polish_model=args.polish_model,
            samples=args.samples,
            insert_constant_milliseconds=args.insert_constant_milliseconds,
            output=model_output,
            short_audio=args.short_audio,
            long_audio=args.long_audio,
        )
        plan_path.write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n")
        runs.append(run_plan(plan_path, model_output, args.timeout))

    baselines = json.loads(args.baselines.read_text())
    report = merge_reports(
        runs,
        samples=args.samples,
        environment=environment_metadata(args.reference_mac),
        standalone_maximum_resident_bytes=baselines[
            "standaloneMaximumResidentBytes"
        ],
        memory_ceiling_reviewed=args.memory_ceiling_reviewed,
        authoritative=True,
        violations=authority_violations(
            samples=args.samples,
            models=list(args.models),
            reference_mac=args.reference_mac,
            polish_model=args.polish_model,
        ),
    )
    report["fixtureValidation"] = fixture_validation
    output = output_directory / "streaming-latency-report.json"
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print_summary(report, output)
    if not report["authoritative"]:
        print("Non-authoritative run:")
        for problem in report["authorityViolations"]:
            print(f"- {problem}")
    if args.skip_xctest:
        return
    code = verify_through_xctest(output, args.baselines)
    if code != 0:
        raise SystemExit(
            "The streaming latency gate rejected this run; read the report's "
            "violations and investigate rather than rerunning to discard samples"
        )


if __name__ == "__main__":
    main()
