#!/usr/bin/env python3
"""Measure FoldWise pane navigation in the packaged Release application."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import plistlib
import subprocess
import sys
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse

REPO = Path(__file__).resolve().parents[1]
BUILD_SCRIPT = REPO / "scripts" / "build_swift_app.py"
BUNDLE = REPO / "dist" / "bundle" / "FoldWise Voice.app"
EXECUTABLE = BUNDLE / "Contents" / "MacOS" / "FoldWiseVoice"
PLAN_ENVIRONMENT_KEY = "FOLDWISE_PANE_PERFORMANCE_PLAN"
PANES = ["Home", "Modes", "Models", "History", "Stats", "Settings"]
PROFILES = ["empty", "10000"]
PRE_SPARKLE_MEDIANS = {
    "empty": {"Stats": 149.477},
    "10000": {
        "Home": 257.702,
        "History": 343.608,
        "Stats": 357.928,
    },
}


def make_plan(
    *,
    profile: str,
    output: Path,
    data_directory: Path,
    sample_count: int,
    destinations: list[str] | None = None,
) -> dict[str, object]:
    return {
        "profile": profile,
        "outputURL": output.resolve().as_uri(),
        "dataDirectory": data_directory.resolve().as_uri(),
        "sampleCount": sample_count,
        "destinations": destinations or PANES,
    }


def measurement_configuration() -> dict[str, object]:
    return {
        "buildConfiguration": "Release",
        "debugger": False,
        "codeCoverage": False,
        "screenshots": False,
        "sanitizers": False,
        "runtimeDiagnostics": False,
        "appNap": False,
        "windowVisibility": "foreground",
        "windowSizePoints": {"width": 980, "height": 720},
    }


def is_authoritative(sample_count: int, hitch_evidence_recorded: bool) -> bool:
    return sample_count == 20 and hitch_evidence_recorded


def baseline_comparison(runs: list[dict[str, Any]]) -> dict[str, object]:
    comparison: dict[str, object] = {}
    for profile, baselines in PRE_SPARKLE_MEDIANS.items():
        run = next(item for item in runs if item["profile"] == profile)
        cold_routes = {
            route["destination"]: route
            for route in run["routes"]
            if route["visit"] == "cold"
        }
        profile_result: dict[str, object] = {}
        for destination, before in baselines.items():
            after = cold_routes[destination]["statistics"]["medianMilliseconds"]
            profile_result[destination] = {
                "preSparkleMedianMilliseconds": before,
                "postSparkleMedianMilliseconds": after,
                "deltaMilliseconds": round(after - before, 6),
                "ratio": round(after / before, 6),
            }
        comparison[
            "profile10000" if profile == "10000" else "profileEmpty"
        ] = profile_result
    comparison["source"] = "docs/research/foldwise-pane-latency-baseline.md"
    return comparison


def run_text(command: list[str]) -> str:
    result = subprocess.run(
        command,
        check=False,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip() if result.returncode == 0 else ""


def defaults_value(domain: str, key: str, fallback: str) -> str:
    value = run_text(["defaults", "read", domain, key])
    return value or fallback


def environment_metadata() -> dict[str, object]:
    display_json = run_text(["system_profiler", "SPDisplaysDataType", "-json"])
    displays: object
    try:
        displays = json.loads(display_json)
    except json.JSONDecodeError:
        displays = display_json

    info = plistlib.loads((BUNDLE / "Contents" / "Info.plist").read_bytes())
    return {
        "commit": run_text(["git", "-C", str(REPO), "rev-parse", "HEAD"]),
        "appVersion": info.get("CFBundleVersion", "unknown"),
        "bundlePath": str(BUNDLE.resolve()),
        "hardwareModel": run_text(["sysctl", "-n", "hw.model"]),
        "chip": run_text(["sysctl", "-n", "machdep.cpu.brand_string"]),
        "memoryBytes": run_text(["sysctl", "-n", "hw.memsize"]),
        "macOS": run_text(["sw_vers"]),
        "xcode": run_text(["xcodebuild", "-version"]),
        "power": run_text(["pmset", "-g", "batt"]),
        "thermal": run_text(["pmset", "-g", "therm"]),
        "displays": displays,
        "appearance": defaults_value("-g", "AppleInterfaceStyle", "Light"),
        "reduceMotion": defaults_value(
            "com.apple.universalaccess", "reduceMotion", "0"
        ),
        "increaseContrast": defaults_value(
            "com.apple.universalaccess", "increaseContrast", "0"
        ),
        "locale": defaults_value("-g", "AppleLocale", "unknown"),
        "timeZone": run_text(["date", "+%Z"]),
    }


def build_bundle() -> None:
    subprocess.run(
        [sys.executable, str(BUILD_SCRIPT), "--bundle-only"],
        cwd=REPO,
        check=True,
    )


def run_plan(plan: dict[str, object], plan_path: Path, timeout: int) -> dict[str, Any]:
    plan_path.parent.mkdir(parents=True, exist_ok=True)
    plan_path.write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n")
    environment = os.environ.copy()
    environment[PLAN_ENVIRONMENT_KEY] = str(plan_path.resolve())
    subprocess.run(
        [str(EXECUTABLE)],
        cwd=REPO,
        env=environment,
        check=True,
        timeout=timeout,
    )
    output_url = urlparse(str(plan["outputURL"]))
    output = Path(unquote(output_url.path))
    if not output.exists():
        failure = output.with_suffix(".failure.txt")
        detail = failure.read_text() if failure.exists() else "no failure artifact"
        raise RuntimeError(f"Packaged app produced no result: {detail}")
    return json.loads(output.read_text())


def record_hitch_trace(evidence: Path, timeout: int) -> dict[str, object]:
    trace_directory = evidence / "hitches"
    trace_directory.mkdir(parents=True, exist_ok=True)
    trace_path = trace_directory / "stats-10000.trace"
    trace_output = trace_directory / "stats-10000.json"
    trace_plan_path = trace_directory / "plan.json"
    trace_plan = make_plan(
        profile="10000",
        output=trace_output,
        data_directory=trace_directory / "profile",
        sample_count=1,
        destinations=["Stats"],
    )
    trace_plan_path.write_text(json.dumps(trace_plan, indent=2, sort_keys=True) + "\n")
    command = [
        "xcrun",
        "xctrace",
        "record",
        "--template",
        "Animation Hitches",
        "--output",
        str(trace_path),
        "--no-prompt",
        "--env",
        f"{PLAN_ENVIRONMENT_KEY}={trace_plan_path.resolve()}",
        "--launch",
        "--",
        str(EXECUTABLE),
    ]
    result = subprocess.run(
        command,
        cwd=REPO,
        check=False,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    (trace_directory / "xctrace.stdout.txt").write_text(result.stdout)
    (trace_directory / "xctrace.stderr.txt").write_text(result.stderr)
    return {
        "template": "Animation Hitches",
        "representativeJourney": {
            "profile": "10000",
            "destination": "Stats",
            "visits": ["cold", "warm"],
        },
        "tracePath": str(trace_path.resolve()),
        "recorded": result.returncode == 0 and trace_path.exists(),
        "xctraceExitStatus": result.returncode,
    }


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    timestamp = dt.datetime.now(dt.UTC).strftime("%Y%m%dT%H%M%SZ")
    parser.add_argument(
        "--output-directory",
        type=Path,
        default=REPO / ".context" / f"pane-performance-{timestamp}",
    )
    parser.add_argument("--samples", type=int, default=20)
    parser.add_argument("--timeout", type=int, default=1_800)
    parser.add_argument("--no-build", action="store_true")
    parser.add_argument("--skip-trace", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_arguments()
    if args.samples <= 0:
        raise SystemExit("--samples must be greater than zero")
    output_directory = args.output_directory.resolve()
    output_directory.mkdir(parents=True, exist_ok=True)

    if not args.no_build:
        build_bundle()
    if not EXECUTABLE.exists():
        raise SystemExit(f"Packaged Release executable not found: {EXECUTABLE}")

    raw_runs: list[dict[str, Any]] = []
    for profile in PROFILES:
        profile_directory = output_directory / "raw" / profile
        raw_output = profile_directory / "result.json"
        plan = make_plan(
            profile=profile,
            output=raw_output,
            data_directory=profile_directory / "profile",
            sample_count=args.samples,
        )
        raw_runs.append(
            run_plan(plan, profile_directory / "plan.json", args.timeout)
        )

    if args.skip_trace:
        hitch_evidence: dict[str, object] = {
            "recorded": False,
            "reason": "Skipped explicitly with --skip-trace.",
        }
    else:
        hitch_evidence = record_hitch_trace(output_directory, args.timeout)
        if not hitch_evidence["recorded"]:
            raise RuntimeError(
                "Animation Hitches trace failed; see hitches/xctrace.stderr.txt"
            )

    report = {
        "schemaVersion": 1,
        "authoritative": is_authoritative(
            args.samples, bool(hitch_evidence["recorded"])
        ),
        "recordedAt": dt.datetime.now(dt.UTC).isoformat(),
        "measurementConfiguration": measurement_configuration(),
        "environment": environment_metadata(),
        "matrix": {
            "profiles": PROFILES,
            "destinations": PANES,
            "visitClasses": ["cold", "warm"],
            "discardedWarmUpsPerClass": 1,
            "recordedSamplesPerClass": args.samples,
        },
        "fixtureIsolation": {
            "root": str((output_directory / "raw").resolve()),
            "liveApplicationSupportAccess": False,
        },
        "runs": raw_runs,
        "hitchEvidence": hitch_evidence,
        "preSparkleComparison": baseline_comparison(raw_runs),
    }
    report_path = output_directory / "pane-performance-report.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(report_path)


if __name__ == "__main__":
    main()
