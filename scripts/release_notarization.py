#!/usr/bin/env python3
"""Submit and finalize one resumable FoldWise notarization transaction."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from collections.abc import Callable
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Protocol


class JSONCommandRunner(Protocol):
    def run_json(self, command: list[str]) -> dict[str, object]:
        """Run a command and return its JSON object output."""

    def run(self, command: list[str]) -> None:
        """Run a command that does not return structured output."""


class ReleasePublisher(Protocol):
    def publish(self, tag: str, dmg: Path, sha256: str) -> None:
        """Attach an exact asset and publish its draft release."""


class CommandFailed(RuntimeError):
    """An external command failed without a usable result."""


class OperatorReviewRequired(RuntimeError):
    """Automation cannot identify one safe transaction to resume."""


class ArtifactMismatch(RuntimeError):
    """Preserved bytes do not match the submit-once record."""


class RecoverableTimeout(RuntimeError):
    """Apple is still processing the recorded submission."""


class TerminalSubmissionFailure(RuntimeError):
    """Apple rejected or invalidated the submitted bytes."""


@dataclass(frozen=True)
class SubmissionRecord:
    tag: str
    filename: str
    sha256: str
    source_run_id: str
    commit: str
    submission_filename: str
    submission_id: str | None

    def to_json(self) -> dict[str, object]:
        return {"schema_version": 1, **asdict(self)}

    @classmethod
    def from_json(cls, value: object) -> SubmissionRecord:
        if not isinstance(value, dict) or value.get("schema_version") != 1:
            raise ValueError("Unsupported notarization record.")
        fields = {key: item for key, item in value.items() if key != "schema_version"}
        return cls(**fields)


class GitHubReleasePublisher:
    def __init__(
        self,
        runner: JSONCommandRunner,
        *,
        repository: str,
    ) -> None:
        self.runner = runner
        self.repository = repository

    def publish(self, tag: str, dmg: Path, sha256: str) -> None:
        self.stage_asset(tag, dmg, sha256)
        self.publish_draft(tag)

    def stage_asset(self, tag: str, asset_path: Path, sha256: str) -> None:
        release = self._release(tag)
        asset = self._asset(release, asset_path.name)
        if asset is not None:
            self._verify_asset_digest(asset, sha256)
        else:
            if release.get("draft") is not True:
                raise OperatorReviewRequired(
                    "Cannot add a missing asset to an already-published release.",
                )
            self.runner.run(
                [
                    "gh",
                    "release",
                    "upload",
                    tag,
                    str(asset_path),
                    "--repo",
                    self.repository,
                ]
            )
            uploaded = self._asset(self._release(tag), asset_path.name)
            if uploaded is None:
                raise ArtifactMismatch(
                    "GitHub did not report the uploaded release asset.",
                )
            self._verify_asset_digest(uploaded, sha256)

    def publish_draft(self, tag: str) -> None:
        release = self._release(tag)
        if release.get("draft") is True:
            self.runner.run(
                [
                    "gh",
                    "release",
                    "edit",
                    tag,
                    "--repo",
                    self.repository,
                    "--draft=false",
                ]
            )

    def _release(self, tag: str) -> dict[str, object]:
        return self.runner.run_json(
            [
                "gh",
                "api",
                f"repos/{self.repository}/releases/tags/{tag}",
            ]
        )

    @staticmethod
    def _asset(
        release: dict[str, object],
        filename: str,
    ) -> dict[str, object] | None:
        assets = release.get("assets")
        if not isinstance(assets, list):
            raise CommandFailed("GitHub release response has no asset list.")
        matches = [
            asset
            for asset in assets
            if isinstance(asset, dict) and asset.get("name") == filename
        ]
        if len(matches) > 1:
            raise OperatorReviewRequired(
                f"GitHub reported multiple release assets named {filename}.",
            )
        return matches[0] if matches else None

    @staticmethod
    def _verify_asset_digest(
        asset: dict[str, object],
        sha256: str,
    ) -> None:
        expected = f"sha256:{sha256}"
        if asset.get("digest") != expected:
            raise ArtifactMismatch(
                "GitHub release asset digest does not match the local asset.",
            )


class SystemCommandRunner:
    def run_json(self, command: list[str]) -> dict[str, object]:
        result = self._run(command, capture_output=True)
        try:
            value = json.loads(result.stdout)
        except json.JSONDecodeError as error:
            raise CommandFailed(
                f"{command[0]} returned invalid JSON: {error}",
            ) from error
        if not isinstance(value, dict):
            raise CommandFailed(
                f"{command[0]} returned a non-object JSON response.",
            )
        return value

    def run(self, command: list[str]) -> None:
        self._run(command, capture_output=False)

    def run_input(self, command: list[str], value: str | None) -> None:
        self._run(
            command,
            capture_output=False,
            input_value=value,
        )

    @staticmethod
    def _run(
        command: list[str],
        *,
        capture_output: bool,
        input_value: str | None = None,
    ) -> subprocess.CompletedProcess[str]:
        try:
            return subprocess.run(
                command,
                check=True,
                text=True,
                capture_output=capture_output,
                input=input_value,
            )
        except subprocess.CalledProcessError as error:
            detail = (error.stderr or error.stdout or "").strip()
            message = f"{command[0]} exited with status {error.returncode}"
            if detail:
                message = f"{message}: {detail}"
            raise CommandFailed(message) from error


class ReleaseNotarization:
    def __init__(
        self,
        runner: JSONCommandRunner,
        *,
        sleeper: Callable[[float], None] = time.sleep,
        notary_arguments: list[str] | None = None,
    ) -> None:
        self.runner = runner
        self.sleeper = sleeper
        self.notary_arguments = notary_arguments or []

    def submit_once(
        self,
        *,
        dmg: Path,
        record_path: Path,
        tag: str,
        source_run_id: str,
        commit: str,
    ) -> SubmissionRecord:
        digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
        submission_filename = f"{dmg.stem}-{tag}-run-{source_run_id}{dmg.suffix}"
        expected = SubmissionRecord(
            tag=tag,
            filename=dmg.name,
            sha256=digest,
            source_run_id=source_run_id,
            commit=commit,
            submission_filename=submission_filename,
            submission_id=None,
        )
        if record_path.exists():
            existing = SubmissionRecord.from_json(
                json.loads(record_path.read_text()),
            )
            self._validate_record(existing, expected)
            if existing.submission_id is not None:
                return existing
            return self._reconcile(existing, record_path)

        self._write_record(record_path, expected)

        submission_path = record_path.parent / submission_filename
        shutil.copy2(dmg, submission_path)
        try:
            try:
                response = self.runner.run_json(
                    [
                        "xcrun",
                        "notarytool",
                        "submit",
                        str(submission_path),
                        "--output-format",
                        "json",
                        *self.notary_arguments,
                    ]
                )
            except CommandFailed:
                return self._reconcile(expected, record_path)
        finally:
            submission_path.unlink(missing_ok=True)

        submission_id = response.get("id")
        if not isinstance(submission_id, str) or not submission_id:
            return self._reconcile(expected, record_path)

        completed = SubmissionRecord(
            **{
                **asdict(expected),
                "submission_id": submission_id,
            },
        )
        self._write_record(record_path, completed)
        return completed

    def _reconcile(
        self,
        record: SubmissionRecord,
        record_path: Path,
    ) -> SubmissionRecord:
        response = self._retry_json(
            [
                "xcrun",
                "notarytool",
                "history",
                "--output-format",
                "json",
                *self.notary_arguments,
            ]
        )
        history = response.get("history")
        if not isinstance(history, list):
            raise OperatorReviewRequired(
                "Apple history returned an unexpected response.",
            )
        matches = [
            entry
            for entry in history
            if isinstance(entry, dict)
            and entry.get("name") == record.submission_filename
            and isinstance(entry.get("id"), str)
        ]
        if len(matches) != 1:
            raise OperatorReviewRequired(
                "Expected exactly one Apple history match for "
                f"{record.submission_filename}; found {len(matches)}.",
            )
        reconciled = SubmissionRecord(
            **{
                **asdict(record),
                "submission_id": matches[0]["id"],
            },
        )
        self._write_record(record_path, reconciled)
        return reconciled

    def finalize(
        self,
        *,
        dmg: Path,
        record_path: Path,
        log_path: Path,
        publisher: ReleasePublisher,
    ) -> None:
        record = SubmissionRecord.from_json(
            json.loads(record_path.read_text()),
        )
        if record.submission_id is None:
            raise OperatorReviewRequired(
                "The notarization record has no submission UUID.",
            )
        if dmg.name != record.filename or self._sha256(dmg) != record.sha256:
            raise ArtifactMismatch(
                "The preserved DMG does not match its submission record.",
            )

        status = self._wait_for_terminal_status(record.submission_id)
        if status in {"Invalid", "Rejected"}:
            self._retry_command(
                [
                    "xcrun",
                    "notarytool",
                    "log",
                    record.submission_id,
                    *self.notary_arguments,
                    str(log_path),
                ]
            )
            raise TerminalSubmissionFailure(
                f"Apple notarization ended with status {status}.",
            )
        if status != "Accepted":
            raise RecoverableTimeout(
                f"Apple notarization remains {status}.",
            )

        self._retry_command(
            [
                "xcrun",
                "stapler",
                "staple",
                str(dmg),
            ]
        )
        self._verify_release_artifact(dmg)
        publisher.publish(record.tag, dmg, self._sha256(dmg))

    def _wait_for_terminal_status(self, submission_id: str) -> str:
        status: str | None = None
        for attempt in range(3):
            try:
                response = self.runner.run_json(
                    [
                        "xcrun",
                        "notarytool",
                        "wait",
                        submission_id,
                        "--timeout",
                        "1h",
                        "--output-format",
                        "json",
                        *self.notary_arguments,
                    ]
                )
                status = self._status(response)
                if status in {"Accepted", "Invalid", "Rejected"}:
                    return status
            except CommandFailed:
                pass
            if attempt < 2:
                self.sleeper(5 * (attempt + 1))

        response = self._retry_json(
            [
                "xcrun",
                "notarytool",
                "info",
                submission_id,
                "--output-format",
                "json",
                *self.notary_arguments,
            ]
        )
        return self._status(response)

    @staticmethod
    def _status(response: dict[str, object]) -> str:
        status = response.get("status")
        if not isinstance(status, str) or not status:
            raise CommandFailed("Notary response did not contain a status.")
        return status

    def _retry_json(self, command: list[str]) -> dict[str, object]:
        for attempt in range(3):
            try:
                return self.runner.run_json(command)
            except CommandFailed:
                if attempt == 2:
                    raise
                self.sleeper(5 * (attempt + 1))
        raise AssertionError("unreachable")

    def _retry_command(self, command: list[str]) -> None:
        for attempt in range(3):
            try:
                self.runner.run(command)
                return
            except CommandFailed:
                if attempt == 2:
                    raise
                self.sleeper(5 * (attempt + 1))

    def _verify_release_artifact(self, dmg: Path) -> None:
        self.runner.run(
            [
                "xcrun",
                "stapler",
                "validate",
                str(dmg),
            ]
        )
        self.runner.run(
            [
                "codesign",
                "--verify",
                "--strict",
                "--verbose=2",
                str(dmg),
            ]
        )
        self.runner.run(
            [
                "spctl",
                "-a",
                "-vvv",
                "-t",
                "open",
                "--context",
                "context:primary-signature",
                str(dmg),
            ]
        )
        with tempfile.TemporaryDirectory() as directory:
            mount_point = Path(directory) / "volume"
            mount_point.mkdir()
            self.runner.run(
                [
                    "hdiutil",
                    "attach",
                    "-readonly",
                    "-nobrowse",
                    "-mountpoint",
                    str(mount_point),
                    str(dmg),
                ]
            )
            try:
                app = mount_point / "FoldWise Voice.app"
                self.runner.run(
                    [
                        "codesign",
                        "--verify",
                        "--deep",
                        "--strict",
                        "--verbose=2",
                        str(app),
                    ]
                )
                self.runner.run(
                    [
                        "spctl",
                        "-a",
                        "-vvv",
                        "-t",
                        "exec",
                        str(app),
                    ]
                )
            finally:
                self.runner.run(
                    [
                        "hdiutil",
                        "detach",
                        str(mount_point),
                    ]
                )

    @staticmethod
    def _sha256(path: Path) -> str:
        digest = hashlib.sha256()
        with path.open("rb") as file:
            for chunk in iter(lambda: file.read(1024 * 1024), b""):
                digest.update(chunk)
        return digest.hexdigest()

    @staticmethod
    def _validate_record(
        actual: SubmissionRecord,
        expected: SubmissionRecord,
    ) -> None:
        comparable = SubmissionRecord(
            **{
                **asdict(actual),
                "submission_id": None,
            },
        )
        if comparable != expected:
            raise OperatorReviewRequired(
                "The preserved notarization record does not match this "
                "artifact or source run.",
            )

    @staticmethod
    def _write_record(path: Path, record: SubmissionRecord) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(f"{path.suffix}.tmp")
        temporary.write_text(
            json.dumps(record.to_json(), indent=2, sort_keys=True) + "\n",
        )
        temporary.replace(path)


def notary_arguments_from_environment() -> list[str]:
    required = {
        "NOTARY_KEY_PATH": os.environ.get("NOTARY_KEY_PATH"),
        "NOTARY_API_KEY_ID": os.environ.get("NOTARY_API_KEY_ID"),
        "NOTARY_API_ISSUER_ID": os.environ.get("NOTARY_API_ISSUER_ID"),
    }
    missing = [name for name, value in required.items() if not value]
    if missing:
        raise RuntimeError(
            "Missing required notarization environment: " + ", ".join(missing),
        )
    return [
        "--key",
        required["NOTARY_KEY_PATH"] or "",
        "--key-id",
        required["NOTARY_API_KEY_ID"] or "",
        "--issuer",
        required["NOTARY_API_ISSUER_ID"] or "",
    ]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    submit = subparsers.add_parser(
        "submit",
        help="submit exact DMG bytes once and record their Apple UUID",
    )
    submit.add_argument("--dmg", type=Path, required=True)
    submit.add_argument("--record", type=Path, required=True)
    submit.add_argument("--tag", required=True)
    submit.add_argument("--source-run-id", required=True)
    submit.add_argument("--commit", required=True)

    finalize = subparsers.add_parser(
        "finalize",
        help="resume, verify, and publish one recorded submission",
    )
    finalize.add_argument("--artifact-directory", type=Path, required=True)
    finalize.add_argument("--record", type=Path, required=True)
    finalize.add_argument("--log", type=Path, required=True)
    finalize.add_argument("--repository", required=True)
    finalize.add_argument("--forward-repair-bad-version")
    finalize.add_argument("--forward-repair-validation-reference")
    finalize.add_argument("--confirm-forward-repair")

    args = parser.parse_args()
    runner = SystemCommandRunner()
    transaction = ReleaseNotarization(
        runner,
        notary_arguments=notary_arguments_from_environment(),
    )

    if args.command == "submit":
        record = transaction.submit_once(
            dmg=args.dmg,
            record_path=args.record,
            tag=args.tag,
            source_run_id=args.source_run_id,
            commit=args.commit,
        )
        print(json.dumps(record.to_json(), sort_keys=True))
        return

    record = SubmissionRecord.from_json(
        json.loads(args.record.read_text()),
    )
    dmg = args.artifact_directory / record.filename
    from release_publication import (
        AuthenticatedUpdatePublisher,
        PublicationPolicy,
        R2UpdateOrigin,
        SparkleAppcastGenerator,
        SystemPublicFetcher,
    )

    required_publication_environment = {
        "AWS_ACCESS_KEY_ID": os.environ.get("AWS_ACCESS_KEY_ID"),
        "AWS_SECRET_ACCESS_KEY": os.environ.get("AWS_SECRET_ACCESS_KEY"),
        "SPARKLE_ED_PRIVATE_KEY": os.environ.get("SPARKLE_ED_PRIVATE_KEY"),
        "UPDATE_R2_ACCOUNT_ID": os.environ.get("UPDATE_R2_ACCOUNT_ID"),
        "UPDATE_R2_BUCKET": os.environ.get("UPDATE_R2_BUCKET"),
    }
    missing = [
        name for name, value in required_publication_environment.items() if not value
    ]
    if missing:
        raise RuntimeError(
            "Missing required publication environment: " + ", ".join(missing),
        )
    repository_root = Path(__file__).resolve().parents[1]
    github = GitHubReleasePublisher(
        runner,
        repository=args.repository,
    )
    generator = SparkleAppcastGenerator(
        runner,
        tool=(
            repository_root
            / ".build"
            / "artifacts"
            / "sparkle"
            / "Sparkle"
            / "bin"
            / "generate_appcast"
        ),
        package_resolved=repository_root / "Package.resolved",
        private_key=required_publication_environment["SPARKLE_ED_PRIVATE_KEY"] or "",
    )
    origin = R2UpdateOrigin(
        runner,
        fetcher=SystemPublicFetcher(),
        bucket=required_publication_environment["UPDATE_R2_BUCKET"] or "",
        endpoint=(
            "https://"
            f"{required_publication_environment['UPDATE_R2_ACCOUNT_ID']}"
            ".r2.cloudflarestorage.com"
        ),
    )
    release_version = record.tag.removeprefix("v")
    forward_repair_arguments = [
        args.forward_repair_bad_version,
        args.forward_repair_validation_reference,
        args.confirm_forward_repair,
    ]
    if any(forward_repair_arguments):
        if not all(forward_repair_arguments):
            raise RuntimeError(
                "Forward repair publication requires the bad version, "
                "validation reference, and exact confirmation.",
            )
        policy = PublicationPolicy.forward_repair(
            bad_version=args.forward_repair_bad_version,
            repair_version=release_version,
            validation_reference=args.forward_repair_validation_reference,
            confirmation=args.confirm_forward_repair,
        )
    else:
        policy = PublicationPolicy.routine(release_version)
    publisher = AuthenticatedUpdatePublisher(
        generator=generator,
        origin=origin,
        github=github,
        changelog=repository_root / "CHANGELOG.md",
        policy=policy,
        record_directory=args.artifact_directory,
        source_commit=record.commit,
        source_run_id=record.source_run_id,
    )
    transaction.finalize(
        dmg=dmg,
        record_path=args.record,
        log_path=args.log,
        publisher=publisher,
    )


if __name__ == "__main__":
    try:
        main()
    except (
        ArtifactMismatch,
        CommandFailed,
        OperatorReviewRequired,
        RecoverableTimeout,
        TerminalSubmissionFailure,
        ValueError,
        RuntimeError,
    ) as error:
        sys.exit(str(error))
