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
import tempfile
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse

REPO = Path(__file__).resolve().parents[1]
BUILD_SCRIPT = REPO / "scripts" / "build_swift_app.py"
BUNDLE = REPO / "dist" / "bundle" / "FoldWise Voice.app"
EXECUTABLE = BUNDLE / "Contents" / "MacOS" / "FoldWiseVoice"
DEFAULT_BASELINES = REPO / "docs" / "pane-performance-baselines.json"
PLAN_ENVIRONMENT_KEY = "FOLDWISE_PANE_PERFORMANCE_PLAN"
PANES = ["Home", "Modes", "Models", "History", "Stats", "Settings"]
PROFILES = ["empty", "10000"]
MAX_NAVIGATION_MILLISECONDS = 100.0
MAX_MAIN_THREAD_BURST_NANOSECONDS = 16_666_667
MIN_EXPLAINED_RENDERING_SAMPLE_PERCENT = 80.0
FRAME_RENDERING_MARKERS = (
    "AG::Graph",
    "GraphHost",
    "ViewGraph",
    "LayoutEngine",
    "sizeThatFits",
    "placeSubviews",
    "DisplayList",
    "RenderBox",
    "RB::",
    "CanvasDisplayList",
    "CA::",
    "CALayer",
)
PRE_SPARKLE_MEDIANS = {
    "empty": {"Stats": 149.477},
    "10000": {
        "Home": 257.702,
        "History": 343.608,
        "Stats": 357.928,
    },
}


def evaluate_duration_gate(
    runs: list[dict[str, Any]],
    baselines: dict[str, Any],
) -> dict[str, object]:
    absolute_violations: list[dict[str, object]] = []
    baseline_violations: list[dict[str, object]] = []
    missing_baselines: list[str] = []
    maximum_regression_percent = float(
        baselines.get("maximumRegressionPercent", 20.0)
    )
    baseline_routes = baselines.get("routes", {})
    for run in runs:
        for route in run["routes"]:
            for sample_index, milliseconds in enumerate(
                route["samplesMilliseconds"],
                start=1,
            ):
                if milliseconds <= MAX_NAVIGATION_MILLISECONDS:
                    continue
                absolute_violations.append(
                    {
                        "profile": run["profile"],
                        "destination": route["destination"],
                        "visit": route["visit"],
                        "sampleIndex": sample_index,
                        "milliseconds": milliseconds,
                        "limitMilliseconds": MAX_NAVIGATION_MILLISECONDS,
                    }
                )
            route_key = "/".join(
                [run["profile"], route["destination"], route["visit"]]
            )
            baseline = baseline_routes.get(route_key)
            if baseline is None:
                missing_baselines.append(route_key)
                continue
            baseline_median = float(baseline["medianMilliseconds"])
            limit = baseline_median * (1 + maximum_regression_percent / 100)
            median = float(route["statistics"]["medianMilliseconds"])
            if median <= limit:
                continue
            baseline_violations.append(
                {
                    "profile": run["profile"],
                    "destination": route["destination"],
                    "visit": route["visit"],
                    "medianMilliseconds": median,
                    "baselineMedianMilliseconds": baseline_median,
                    "limitMilliseconds": limit,
                    "maximumRegressionPercent": maximum_regression_percent,
                }
            )
    return {
        "passed": (
            not absolute_violations
            and not baseline_violations
            and not missing_baselines
        ),
        "absoluteViolations": absolute_violations,
        "baselineViolations": baseline_violations,
        "missingBaselines": missing_baselines,
    }


def evaluate_matrix_gate(
    runs: list[dict[str, Any]],
    expected_sample_count: int,
) -> dict[str, object]:
    fixture_identities = {
        "empty": "pane-empty-v1",
        "10000": "pane-10000-v1",
    }
    expected_routes = [
        f"{profile}/{destination}/{visit}"
        for profile in PROFILES
        for destination in PANES
        for visit in ["cold", "warm"]
    ]
    actual_route_list = [
        "/".join([run["profile"], route["destination"], route["visit"]])
        for run in runs
        for route in run["routes"]
    ]
    actual_routes = set(actual_route_list)
    expected_route_set = set(expected_routes)
    missing_routes = [
        route for route in expected_routes if route not in actual_routes
    ]
    unexpected_routes = sorted(actual_routes - expected_route_set)
    duplicate_routes = sorted(
        route
        for route, count in Counter(actual_route_list).items()
        if count > 1
    )
    sample_count_violations = []
    run_metadata_violations = []
    for run in runs:
        expected_metadata = {
            "fixtureIdentity": fixture_identities.get(run["profile"]),
            "warmUpSamplesDiscarded": 1,
            "recordedSamplesPerClass": expected_sample_count,
        }
        for field, expected in expected_metadata.items():
            actual = run.get(field)
            if actual == expected:
                continue
            run_metadata_violations.append(
                {
                    "profile": run["profile"],
                    "field": field,
                    "expected": expected,
                    "actual": actual,
                }
            )
        for route in run["routes"]:
            route_key = "/".join(
                [run["profile"], route["destination"], route["visit"]]
            )
            actual_count = len(route["samplesMilliseconds"])
            if actual_count == expected_sample_count:
                continue
            sample_count_violations.append(
                {
                    "route": route_key,
                    "expected": expected_sample_count,
                    "actual": actual_count,
                }
            )
    return {
        "passed": (
            not missing_routes
            and not unexpected_routes
            and not duplicate_routes
            and not sample_count_violations
            and not run_metadata_violations
        ),
        "missingRoutes": missing_routes,
        "unexpectedRoutes": unexpected_routes,
        "duplicateRoutes": duplicate_routes,
        "sampleCountViolations": sample_count_violations,
        "runMetadataViolations": run_metadata_violations,
    }


def post_sparkle_comparison(
    runs: list[dict[str, Any]],
    baselines: dict[str, Any],
) -> dict[str, dict[str, float]]:
    current_routes = {
        "/".join([run["profile"], route["destination"], route["visit"]]): float(
            route["statistics"]["medianMilliseconds"]
        )
        for run in runs
        for route in run["routes"]
    }
    comparison = {}
    for route_key, baseline in baselines.get("postSparkleRoutes", {}).items():
        if route_key not in current_routes:
            continue
        post_sparkle = float(baseline["medianMilliseconds"])
        current = current_routes[route_key]
        comparison[route_key] = {
            "postSparkleMedianMilliseconds": post_sparkle,
            "currentMedianMilliseconds": current,
            "deltaMilliseconds": round(current - post_sparkle, 6),
            "ratio": round(current / post_sparkle, 6),
        }
    return comparison


def trace_specifications() -> list[dict[str, object]]:
    specifications = []
    for profile, destinations in [
        ("empty", ["Modes", "Stats"]),
        ("10000", ["Home", "Modes", "History", "Stats"]),
    ]:
        specifications.append(
            {
                "profile": profile,
                "template": "SwiftUI",
                "instruments": ["os_signpost"],
                "destinations": destinations,
                "visitClasses": ["cold", "warm"],
                "components": [
                    "SwiftUI",
                    "Time Profiler",
                    "Hitches",
                    "PaneNavigation signposts",
                    "FirstWindowOpening signpost",
                ],
            }
        )
    return specifications


def trace_start_epoch(toc_xml: str) -> float:
    toc_root = ET.fromstring(toc_xml)
    trace_start = dt.datetime.fromisoformat(
        toc_root.findtext(".//start-date", default="")
    )
    return trace_start.timestamp()


def timed_trace_rows(trace_xml: str) -> list[tuple[int, int]]:
    root = ET.fromstring(trace_xml)
    values_by_id = {
        element.attrib["id"]: int(element.text)
        for element in root.iter()
        if "id" in element.attrib
        and element.text is not None
        and element.text.isdigit()
    }

    def nanoseconds(row: ET.Element, tag: str) -> int:
        element = row.find(tag)
        if element is None:
            return 0
        reference = element.attrib.get("ref")
        if reference is not None:
            return values_by_id[reference]
        return int(element.text or "0")

    return [
        (nanoseconds(row, "start-time"), nanoseconds(row, "duration"))
        for row in root.findall(".//row")
    ]


def overlapping_navigation_rows(
    run: dict[str, Any],
    toc_xml: str,
    trace_xml: str,
) -> list[dict[str, object]]:
    start_epoch = trace_start_epoch(toc_xml)
    rows = timed_trace_rows(trace_xml)
    overlaps = []
    for interval in run["navigationIntervals"]:
        if interval["sample"] != "recorded":
            continue
        interval_start = (
            float(interval["startedAtEpoch"]) - start_epoch
        ) * 1_000_000_000
        interval_end = (
            float(interval["endedAtEpoch"]) - start_epoch
        ) * 1_000_000_000
        for row_start, row_duration in rows:
            row_end = row_start + row_duration
            if row_start >= interval_end or row_end <= interval_start:
                continue
            overlaps.append(
                {
                    "profile": run["profile"],
                    "destination": interval["destination"],
                    "visit": interval["visit"],
                    "sample": interval["sample"],
                    "startMilliseconds": row_start / 1_000_000,
                    "durationMilliseconds": row_duration / 1_000_000,
                }
            )
    return overlaps


def evaluate_hitch_gate(
    run: dict[str, Any],
    toc_xml: str,
    hitches_xml: str,
) -> dict[str, object]:
    navigation_hitches = [
        {
            **overlap,
            "hitchStartMilliseconds": overlap["startMilliseconds"],
            "hitchDurationMilliseconds": overlap["durationMilliseconds"],
        }
        for overlap in overlapping_navigation_rows(run, toc_xml, hitches_xml)
    ]
    for hitch in navigation_hitches:
        del hitch["startMilliseconds"]
        del hitch["durationMilliseconds"]
    return {
        "passed": not navigation_hitches,
        "navigationHitches": navigation_hitches,
    }


def evaluate_causal_gate(
    run: dict[str, Any],
    toc_xml: str,
    update_groups_xml: str,
    potential_hangs_xml: str,
    time_profile_xml: str,
) -> dict[str, object]:
    navigation_update_groups = overlapping_navigation_rows(
        run,
        toc_xml,
        update_groups_xml,
    )
    navigation_potential_hangs = overlapping_navigation_rows(
        run,
        toc_xml,
        potential_hangs_xml,
    )
    navigation_main_thread_stalls = navigation_main_thread_stalls_for_run(
        run,
        toc_xml,
        time_profile_xml,
    )
    unexplained_main_thread_stalls = [
        stall
        for stall in navigation_main_thread_stalls
        if stall["classification"] == "unexplained"
    ]
    return {
        "passed": (
            not navigation_update_groups
            and not navigation_potential_hangs
            and not unexplained_main_thread_stalls
        ),
        "navigationUpdateGroupCount": len(navigation_update_groups),
        "navigationPotentialHangCount": len(navigation_potential_hangs),
        "navigationMainThreadStallCount": len(navigation_main_thread_stalls),
        "navigationExplainedMainThreadStallCount": (
            len(navigation_main_thread_stalls)
            - len(unexplained_main_thread_stalls)
        ),
        "navigationUnexplainedMainThreadStallCount": len(
            unexplained_main_thread_stalls
        ),
        "navigationUpdateGroups": navigation_update_groups,
        "navigationPotentialHangs": navigation_potential_hangs,
        "navigationMainThreadStalls": navigation_main_thread_stalls,
        "navigationUnexplainedMainThreadStalls": unexplained_main_thread_stalls,
    }


def navigation_main_thread_stalls_for_run(
    run: dict[str, Any],
    toc_xml: str,
    time_profile_xml: str,
) -> list[dict[str, object]]:
    root = ET.fromstring(time_profile_xml)
    elements_by_id = {
        element.attrib["id"]: element
        for element in root.iter()
        if "id" in element.attrib
    }

    def dereference(element: ET.Element | None) -> ET.Element | None:
        if element is None:
            return None
        reference = element.attrib.get("ref")
        return elements_by_id.get(reference, element)

    backtraces_by_id = {
        identifier: [
            dereference(frame).attrib.get("name", "Unknown")
            for frame in element.findall("frame")
            if dereference(frame) is not None
        ]
        for identifier, element in elements_by_id.items()
        if element.tag == "backtrace"
    }

    samples: list[tuple[int, int, list[str]]] = []
    for row in root.findall(".//row"):
        sample_time = dereference(row.find("sample-time"))
        thread = dereference(row.find("thread"))
        thread_state = dereference(row.find("thread-state"))
        weight = dereference(row.find("weight"))
        if (
            sample_time is None
            or thread is None
            or thread_state is None
            or weight is None
            or not thread.attrib.get("fmt", "").startswith("Main Thread")
            or (thread_state.text or thread_state.attrib.get("fmt")) != "Running"
        ):
            continue
        backtrace = row.find("backtrace")
        frames: list[str]
        if backtrace is None:
            frames = ["Unknown"]
        elif "ref" in backtrace.attrib:
            frames = backtraces_by_id.get(backtrace.attrib["ref"], ["Unknown"])
        else:
            frames = [
                dereference(frame).attrib.get("name", "Unknown")
                for frame in backtrace.findall("frame")
                if dereference(frame) is not None
            ]
        samples.append(
            (
                int(sample_time.text or "0"),
                int(weight.text or "0"),
                frames or ["Unknown"],
            )
        )

    start_epoch = trace_start_epoch(toc_xml)
    stalls: list[dict[str, object]] = []
    for interval in run["navigationIntervals"]:
        if interval["sample"] != "recorded":
            continue
        interval_start = int(
            (float(interval["startedAtEpoch"]) - start_epoch) * 1_000_000_000
        )
        interval_end = int(
            (float(interval["endedAtEpoch"]) - start_epoch) * 1_000_000_000
        )
        interval_samples = [
            sample
            for sample in samples
            if interval_start <= sample[0] < interval_end
        ]
        bursts: list[list[tuple[int, int, list[str]]]] = []
        current_burst: list[tuple[int, int, list[str]]] = []
        for sample in interval_samples:
            if current_burst:
                previous = current_burst[-1]
                maximum_gap = max(1_000_000, previous[1] * 4)
                if sample[0] - previous[0] > maximum_gap:
                    bursts.append(current_burst)
                    current_burst = []
            current_burst.append(sample)
        if current_burst:
            bursts.append(current_burst)

        for burst in bursts:
            duration = burst[-1][0] + burst[-1][1] - burst[0][0]
            if duration <= MAX_MAIN_THREAD_BURST_NANOSECONDS:
                continue
            total_weight = sum(sample[1] for sample in burst)
            rendering_weight = sum(
                sample[1]
                for sample in burst
                if any(
                    marker in frame
                    for frame in sample[2]
                    for marker in FRAME_RENDERING_MARKERS
                )
            )
            rendering_sample_percent = (
                rendering_weight / total_weight * 100
                if total_weight
                else 0
            )
            classification = (
                "explainedFrameRendering"
                if (
                    rendering_sample_percent
                    >= MIN_EXPLAINED_RENDERING_SAMPLE_PERCENT
                )
                else "unexplained"
            )
            stalls.append(
                {
                    "profile": run["profile"],
                    "destination": interval["destination"],
                    "visit": interval["visit"],
                    "sample": interval["sample"],
                    "startMilliseconds": burst[0][0] / 1_000_000,
                    "durationMilliseconds": duration / 1_000_000,
                    "dominantLeafFrame": Counter(
                        sample[2][0] for sample in burst
                    ).most_common(1)[0][0],
                    "classification": classification,
                    "renderingSamplePercent": round(
                        rendering_sample_percent,
                        1,
                    ),
                }
            )
    return stalls


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
        "windowActivation": "nonactivating",
        "windowSizePoints": {"width": 980, "height": 720},
    }


def is_authoritative(
    sample_count: int,
    matrix_gate_passed: bool,
    duration_gate_passed: bool,
    trace_gate_passed: bool,
) -> bool:
    return (
        sample_count == 20
        and matrix_gate_passed
        and duration_gate_passed
        and trace_gate_passed
    )


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


def load_baselines(path: Path) -> dict[str, Any]:
    baselines = json.loads(path.read_text())
    maximum_regression = float(baselines["maximumRegressionPercent"])
    if maximum_regression > 20:
        raise ValueError("Pane baseline regression allowance cannot exceed 20%.")
    return baselines


def export_trace(
    trace_path: Path,
    output_path: Path,
    *,
    toc: bool = False,
    schema: str | None = None,
) -> tuple[bool, str]:
    command = [
        "xcrun",
        "xctrace",
        "export",
        "--input",
        str(trace_path),
    ]
    if toc:
        command.append("--toc")
    elif schema is not None:
        command.extend(
            [
                "--xpath",
                (
                    "/trace-toc/run[@number=\"1\"]/data/"
                    f"table[@schema=\"{schema}\"]"
                ),
            ]
        )
    result = subprocess.run(
        command,
        cwd=REPO,
        check=False,
        capture_output=True,
        text=True,
    )
    output_path.write_text(result.stdout)
    return result.returncode == 0, result.stdout


def trace_record_command(
    specification: dict[str, Any],
    *,
    trace_path: Path,
    plan_path: Path,
    executable: Path,
) -> list[str]:
    command = [
        "xcrun",
        "xctrace",
        "record",
        "--template",
        specification["template"],
    ]
    for instrument in specification.get("instruments", []):
        command.extend(["--instrument", instrument])
    command.extend(
        [
            "--output",
            str(trace_path),
            "--no-prompt",
            "--env",
            f"{PLAN_ENVIRONMENT_KEY}={plan_path.resolve()}",
            "--launch",
            "--",
            str(executable),
        ]
    )
    return command


def record_trace(
    evidence: Path,
    specification: dict[str, Any],
    timeout: int,
) -> dict[str, object]:
    profile = specification["profile"]
    template_slug = specification["template"].lower().replace(" ", "-")
    trace_directory = evidence / "traces" / profile / template_slug
    trace_directory.mkdir(parents=True, exist_ok=True)
    trace_path = trace_directory / "capture.trace"
    trace_output = trace_directory / "run.json"
    trace_plan_path = trace_directory / "plan.json"
    trace_plan = make_plan(
        profile=profile,
        output=trace_output,
        data_directory=trace_directory / "profile",
        sample_count=1,
        destinations=specification["destinations"],
    )
    trace_plan_path.write_text(json.dumps(trace_plan, indent=2, sort_keys=True) + "\n")
    command = trace_record_command(
        specification,
        trace_path=trace_path,
        plan_path=trace_plan_path,
        executable=EXECUTABLE,
    )
    with tempfile.TemporaryDirectory(
        prefix="xctrace-",
        dir=trace_directory,
    ) as temporary_directory:
        environment = os.environ.copy()
        environment["TMPDIR"] = temporary_directory
        result = subprocess.run(
            command,
            cwd=REPO,
            env=environment,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    (trace_directory / "xctrace.stdout.txt").write_text(result.stdout)
    (trace_directory / "xctrace.stderr.txt").write_text(result.stderr)
    recorded = (
        result.returncode == 0
        and trace_path.exists()
        and trace_output.exists()
    )
    if not recorded:
        return {
            **specification,
            "tracePath": str(trace_path.resolve()),
            "recorded": False,
            "xctraceExitStatus": result.returncode,
            "requiredComponentsRecorded": False,
            "hitchGate": {
                "passed": False,
                "navigationHitches": [],
                "reason": "Trace or packaged-app run result is missing.",
            },
            "causalGate": {
                "passed": False,
                "reason": "Trace or packaged-app run result is missing.",
            },
        }

    exports: dict[str, str] = {}
    export_statuses: dict[str, bool] = {}
    export_requests = {
        "toc": (True, None),
        "hitches": (False, "hitches"),
        "potential-hangs": (False, "potential-hangs"),
        "swiftui-update-groups": (False, "swiftui-update-groups"),
        "time-profile": (False, "time-profile"),
        "os-signpost": (False, "os-signpost"),
    }
    for name, (is_toc, schema) in export_requests.items():
        output_path = trace_directory / f"{name}.xml"
        status, xml = export_trace(
            trace_path,
            output_path,
            toc=is_toc,
            schema=schema,
        )
        export_statuses[name] = status
        exports[name] = xml

    toc = exports["toc"]
    signposts = exports["os-signpost"]
    required_components_recorded = (
        all(export_statuses.values())
        and 'schema="hitches"' in toc
        and 'schema="potential-hangs"' in toc
        and 'schema="time-profile"' in toc
        and 'schema="swiftui-update-groups"' in toc
        and 'schema="os-signpost"' in toc
        and "PaneNavigation" in signposts
        and "FirstWindowOpening" in signposts
    )
    run_result = json.loads(trace_output.read_text())
    hitch_gate = evaluate_hitch_gate(
        run_result,
        toc,
        exports["hitches"],
    )
    causal_gate = evaluate_causal_gate(
        run_result,
        toc,
        exports["swiftui-update-groups"],
        exports["potential-hangs"],
        exports["time-profile"],
    )
    return {
        **specification,
        "tracePath": str(trace_path.resolve()),
        "runResultPath": str(trace_output.resolve()),
        "recorded": True,
        "xctraceExitStatus": result.returncode,
        "requiredComponentsRecorded": required_components_recorded,
        "hitchGate": hitch_gate,
        "causalGate": causal_gate,
        "exports": {
            name: str((trace_directory / f"{name}.xml").resolve())
            for name in export_requests
        },
    }


def record_trace_evidence(evidence: Path, timeout: int) -> dict[str, object]:
    traces = [
        record_trace(evidence, specification, timeout)
        for specification in trace_specifications()
    ]
    navigation_hitches = [
        hitch
        for trace in traces
        for hitch in trace["hitchGate"]["navigationHitches"]
    ]
    passed = all(
        trace["recorded"]
        and trace["requiredComponentsRecorded"]
        and trace["hitchGate"]["passed"]
        and trace["causalGate"]["passed"]
        for trace in traces
    )
    return {
        "passed": passed,
        "navigationHitchCount": len(navigation_hitches),
        "navigationHitches": navigation_hitches,
        "traces": traces,
        "causalReview": {
            "passed": all(trace["causalGate"]["passed"] for trace in traces),
            "instructions": "docs/pane-performance-harness.md#causal-trace-review",
        },
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
    parser.add_argument("--baselines", type=Path, default=DEFAULT_BASELINES)
    parser.add_argument("--no-build", action="store_true")
    parser.add_argument("--skip-trace", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_arguments()
    if args.samples <= 0:
        raise SystemExit("--samples must be greater than zero")
    output_directory = args.output_directory.resolve()
    output_directory.mkdir(parents=True, exist_ok=True)
    baselines = load_baselines(args.baselines)

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
        trace_evidence: dict[str, object] = {
            "passed": False,
            "reason": "Skipped explicitly with --skip-trace.",
            "navigationHitchCount": None,
            "traces": [],
        }
    else:
        trace_evidence = record_trace_evidence(output_directory, args.timeout)

    matrix_gate = evaluate_matrix_gate(raw_runs, args.samples)
    duration_gate = evaluate_duration_gate(raw_runs, baselines)
    authoritative = is_authoritative(
        args.samples,
        bool(matrix_gate["passed"]),
        bool(duration_gate["passed"]),
        bool(trace_evidence["passed"]),
    )
    report = {
        "schemaVersion": 2,
        "authoritative": authoritative,
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
        "acceptance": {
            "maximumNavigationMilliseconds": MAX_NAVIGATION_MILLISECONDS,
            "baselineSource": str(args.baselines.resolve()),
            "matrixGate": matrix_gate,
            "durationGate": duration_gate,
            "traceGate": trace_evidence,
        },
        "preSparkleComparison": baseline_comparison(raw_runs),
        "postSparkleComparison": post_sparkle_comparison(raw_runs, baselines),
    }
    report_path = output_directory / "pane-performance-report.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(report_path)
    if args.samples == 20 and not args.skip_trace and not authoritative:
        raise SystemExit(
            "Pane performance release gate failed; inspect acceptance in "
            f"{report_path}"
        )


if __name__ == "__main__":
    main()
