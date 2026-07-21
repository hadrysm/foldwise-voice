#!/usr/bin/env python3
"""Evaluate FoldWiseVoiceKit coverage against the repository policy."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


CURRENT_POLICY_VERSION = 2
LEGACY_POLICY_VERSION = 1
MINIMUM_POLICY_FLOORS = {
    LEGACY_POLICY_VERSION: {
        "included_core_floor": 90.0,
        "changed_line_floor": 90.0,
        "minimum_file_coverage": 90.0,
    },
    CURRENT_POLICY_VERSION: {
        "included_core_floor": 90.0,
        "changed_line_floor": 85.0,
        "minimum_file_coverage": 80.0,
    },
}


@dataclass(frozen=True)
class FileCoverage:
    path: str
    covered: int
    count: int
    line_counts: dict[int, int]

    @property
    def percent(self) -> float:
        return percentage(self.covered, self.count)


@dataclass(frozen=True)
class ChangedLineCoverage:
    path: str
    line: int
    count: int

    @property
    def covered(self) -> bool:
        return self.count > 0


@dataclass(frozen=True)
class Exemption:
    reason: str
    allows_missing_coverage_data: bool


def percentage(covered: int, count: int) -> float:
    return 100.0 if count == 0 else covered / count * 100.0


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True, help="LLVM coverage JSON export")
    parser.add_argument("--policy", type=Path, required=True, help="Repository coverage policy JSON")
    parser.add_argument(
        "--baseline-policy",
        type=Path,
        help="Accepted policy from the target ref, when one already exists",
    )
    parser.add_argument("--diff", type=Path, required=True, help="Unified zero-context git diff")
    parser.add_argument("--root", type=Path, required=True, help="Repository root")
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return value


def relative_production_path(filename: str, root: Path, source_root: Path) -> str | None:
    path = Path(filename)
    if not path.is_absolute():
        path = root / path
    try:
        relative = path.resolve().relative_to(source_root.resolve())
    except ValueError:
        return None
    return (Path(source_root.name) / relative).as_posix()


def repository_path(production_path: str, policy_source_root: str) -> str:
    source_name = Path(policy_source_root).name
    relative = Path(production_path).relative_to(source_name)
    return (Path(policy_source_root) / relative).as_posix()


def line_counts(segments: list[list[Any]]) -> dict[int, int]:
    counts: dict[int, int] = {}
    for index, segment in enumerate(segments[:-1]):
        if len(segment) < 6:
            raise ValueError("coverage segment has fewer than six fields")
        line, _, count, has_count, is_region_entry, is_gap = segment[:6]
        if not has_count or is_gap:
            continue

        next_line, next_column = segments[index + 1][:2]
        last_line = next_line if next_column > 1 else next_line - 1
        first_line = line if is_region_entry else line + 1
        for covered_line in range(first_line, last_line + 1):
            counts[covered_line] = max(counts.get(covered_line, 0), int(count))
    return counts


def load_coverage(
    report: dict[str, Any], root: Path, policy_source_root: str
) -> dict[str, FileCoverage]:
    data = report.get("data")
    if not isinstance(data, list) or len(data) != 1 or not isinstance(data[0], dict):
        raise ValueError("coverage report must contain exactly one LLVM data object")
    files = data[0].get("files")
    if not isinstance(files, list):
        raise ValueError("coverage report is missing its files array")

    source_root = root / policy_source_root
    result: dict[str, FileCoverage] = {}
    for file_report in files:
        if not isinstance(file_report, dict) or not isinstance(file_report.get("filename"), str):
            raise ValueError("coverage report contains an invalid file entry")
        production_path = relative_production_path(file_report["filename"], root, source_root)
        if production_path is None:
            continue
        path = repository_path(production_path, policy_source_root)
        if path in result:
            raise ValueError(f"coverage report contains duplicate production file: {path}")

        try:
            lines = file_report["summary"]["lines"]
            segments = file_report["segments"]
            result[path] = FileCoverage(
                path=path,
                covered=int(lines["covered"]),
                count=int(lines["count"]),
                line_counts=line_counts(segments),
            )
        except (KeyError, TypeError, ValueError) as error:
            raise ValueError(f"invalid coverage data for {path}: {error}") from error
    return result


def load_exemptions(policy: dict[str, Any], production_files: set[str]) -> dict[str, Exemption]:
    entries = policy.get("exemptions")
    if not isinstance(entries, list):
        raise ValueError("policy exemptions must be an array")

    exemptions: dict[str, Exemption] = {}
    for entry in entries:
        if not isinstance(entry, dict):
            raise ValueError("each exemption must be an object")
        path = entry.get("path")
        reason = entry.get("reason")
        allows_missing_coverage_data = entry.get("allows_missing_coverage_data", False)
        if not isinstance(path, str) or not path.endswith(".swift"):
            raise ValueError("each exemption must name one Swift source file")
        if any(character in path for character in "*?["):
            raise ValueError(f"exemption must name an exact file, not a pattern: {path}")
        if not isinstance(reason, str) or not reason.strip():
            raise ValueError(f"exemption requires a reason: {path}")
        if not isinstance(allows_missing_coverage_data, bool):
            raise ValueError(f"exemption allows_missing_coverage_data must be a boolean: {path}")
        if path in exemptions:
            raise ValueError(f"duplicate exemption: {path}")
        if path not in production_files:
            raise ValueError(f"exemption does not name a production file: {path}")
        exemptions[path] = Exemption(
            reason=reason.strip(),
            allows_missing_coverage_data=allows_missing_coverage_data,
        )
    return exemptions


def changed_lines(diff: str) -> dict[str, set[int]]:
    changes: dict[str, set[int]] = {}
    path: str | None = None
    new_line: int | None = None
    hunk = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")

    for raw_line in diff.splitlines():
        if raw_line.startswith("+++ "):
            value = raw_line[4:]
            path = None if value == "/dev/null" else value.removeprefix("b/")
            new_line = None
            continue
        match = hunk.match(raw_line)
        if match:
            new_line = int(match.group(1))
            continue
        if path is None or new_line is None:
            continue
        if raw_line.startswith("+"):
            changes.setdefault(path, set()).add(new_line)
            new_line += 1
        elif raw_line.startswith("-"):
            continue
        elif raw_line.startswith("\\ No newline at end of file"):
            continue
        else:
            new_line += 1
    return changes


def policy_number(policy: dict[str, Any], name: str) -> float:
    value = policy.get(name)
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        raise ValueError(f"policy {name} must be a number")
    number = float(value)
    if number < 0 or number > 100:
        raise ValueError(f"policy {name} must be between 0 and 100")
    return number


def policy_version(policy: dict[str, Any]) -> int:
    value = policy.get("policy_version", LEGACY_POLICY_VERSION)
    if not isinstance(value, int) or isinstance(value, bool) or value < 1:
        raise ValueError("policy policy_version must be a positive integer")
    if value > CURRENT_POLICY_VERSION:
        raise ValueError(f"policy policy_version {value} is not supported")
    return value


def validate_policy_ratchet(policy: dict[str, Any], baseline_policy: dict[str, Any] | None) -> None:
    current_version = policy_version(policy)
    for name, minimum in MINIMUM_POLICY_FLOORS[current_version].items():
        if policy_number(policy, name) < minimum:
            raise ValueError(f"policy {name} must remain at least {minimum:.2f}%")

    if baseline_policy is None:
        return

    baseline_version = policy_version(baseline_policy)
    ratcheted_names = (
        "overall_floor",
        "included_core_floor",
        "changed_line_floor",
        "minimum_file_coverage",
    )
    if current_version == baseline_version:
        names_to_compare = ratcheted_names
    elif baseline_version == LEGACY_POLICY_VERSION and current_version == CURRENT_POLICY_VERSION:
        names_to_compare = ("overall_floor",)
    else:
        raise ValueError(
            "policy policy_version cannot change "
            f"from {baseline_version} to {current_version} without checker support"
        )

    for name in names_to_compare:
        accepted = policy_number(baseline_policy, name)
        current = policy_number(policy, name)
        if current + 1e-9 < accepted:
            raise ValueError(f"policy {name} cannot decrease from {accepted:.2f}% to {current:.2f}%")


def summarize(files: list[FileCoverage]) -> tuple[int, int, float]:
    covered = sum(file.covered for file in files)
    count = sum(file.count for file in files)
    return covered, count, percentage(covered, count)


def evaluate(args: argparse.Namespace) -> int:
    root = args.root.resolve()
    policy = load_json(args.policy)
    baseline_policy = load_json(args.baseline_policy) if args.baseline_policy else None
    validate_policy_ratchet(policy, baseline_policy)
    source_root_value = policy.get("production_source_root")
    if not isinstance(source_root_value, str) or not source_root_value:
        raise ValueError("policy production_source_root must be a path")
    source_root = root / source_root_value
    if not source_root.is_dir():
        raise ValueError(f"production source root does not exist: {source_root_value}")

    production_files = {
        path.relative_to(root).as_posix() for path in source_root.rglob("*.swift") if path.is_file()
    }
    exemptions = load_exemptions(policy, production_files)
    report = load_coverage(load_json(args.report), root, source_root_value)
    allowed_missing = {
        path for path, exemption in exemptions.items() if exemption.allows_missing_coverage_data
    }
    missing = sorted(production_files - report.keys() - allowed_missing)
    if missing:
        raise ValueError("coverage report is missing production files: " + ", ".join(missing))

    all_files = [report[path] for path in sorted(production_files & report.keys())]
    included_files = [report[path] for path in sorted(production_files - exemptions.keys())]
    overall_covered, overall_count, overall_percent = summarize(all_files)
    core_covered, core_count, core_percent = summarize(included_files)

    diff_changes = changed_lines(args.diff.read_text(encoding="utf-8"))
    changed_executable: list[ChangedLineCoverage] = []
    for path, lines in diff_changes.items():
        if path not in report or path in exemptions:
            continue
        for line in sorted(lines):
            if line in report[path].line_counts:
                changed_executable.append(
                    ChangedLineCoverage(path=path, line=line, count=report[path].line_counts[line])
                )
    changed_covered = sum(1 for changed_line in changed_executable if changed_line.covered)
    changed_count = len(changed_executable)
    changed_percent = percentage(changed_covered, changed_count)

    overall_floor = policy_number(policy, "overall_floor")
    core_floor = policy_number(policy, "included_core_floor")
    changed_floor = policy_number(policy, "changed_line_floor")
    file_floor = policy_number(policy, "minimum_file_coverage")

    print("Coverage policy")
    print(
        f"Overall production: {overall_percent:.2f}% "
        f"({overall_covered}/{overall_count}), required {overall_floor:.2f}%"
    )
    print(
        f"Included core: {core_percent:.2f}% "
        f"({core_covered}/{core_count}), required {core_floor:.2f}%"
    )
    changed_fraction = f"{changed_covered}/{changed_count}" if changed_count else "no executable changes"
    print(
        f"Changed included lines: {changed_percent:.2f}% "
        f"({changed_fraction}), required {changed_floor:.2f}%"
    )
    print(f"Included files: {len(included_files)}; explicit exemptions: {len(exemptions)}")
    print("Lowest-covered included files:")
    for file in sorted(included_files, key=lambda item: (item.percent, item.path))[:10]:
        print(f"  {file.percent:6.2f}%  {file.path} ({file.covered}/{file.count})")

    failures: list[str] = []
    if overall_percent + 1e-9 < overall_floor:
        failures.append(
            f"overall production coverage {overall_percent:.2f}% is below {overall_floor:.2f}%"
        )
    if core_percent + 1e-9 < core_floor:
        failures.append(f"included core coverage {core_percent:.2f}% is below {core_floor:.2f}%")

    low_files = [file for file in included_files if file.percent + 1e-9 < file_floor]
    for file in sorted(low_files, key=lambda item: (item.percent, item.path)):
        failures.append(f"{file.path} coverage {file.percent:.2f}% is below {file_floor:.2f}%")

    uncovered_changed = [changed_line for changed_line in changed_executable if not changed_line.covered]
    if changed_percent + 1e-9 < changed_floor:
        failures.append(
            f"changed included coverage {changed_percent:.2f}% is below {changed_floor:.2f}%"
        )
        failures.append(
            "uncovered changed lines: "
            + ", ".join(f"{changed_line.path}:{changed_line.line}" for changed_line in uncovered_changed)
        )

    if failures:
        print("Coverage policy FAILED")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print("Coverage policy PASSED")
    return 0


def main() -> int:
    try:
        return evaluate(parse_arguments())
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"Coverage policy error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
