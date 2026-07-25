#!/usr/bin/env python3
"""Withdraw a bad FoldWise release from the Update origin."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Protocol

UPDATE_ORIGIN = "https://updates.guarcode.com"


class RecoveryError(RuntimeError):
    """Recovery cannot continue without violating the incident contract."""


class RecoveryOrigin(Protocol):
    def fetch_appcast(self) -> bytes | None:
        """Fetch the currently public appcast."""

    def fetch_archive(self, filename: str) -> bytes | None:
        """Fetch a public release archive."""

    def freeze_publication(self, request: WithdrawalRequest) -> None:
        """Block routine publication before changing public release state."""

    def remove_archive(self, filename: str) -> None:
        """Remove a bad archive without replacing its immutable URL."""

    def restore_appcast(self, appcast: Path) -> None:
        """Restore exact last-known-good signed feed bytes."""

    def purge(self, urls: list[str]) -> None:
        """Purge the named public URLs from the cache."""

    def verify_archive_absent(self, filename: str) -> None:
        """Fail unless the bad archive is unavailable publicly."""

    def verify_appcast(self, expected: bytes) -> None:
        """Fail unless the public feed equals the expected bytes."""


class InputCommandRunner(Protocol):
    def run_input(self, command: list[str], value: str | None) -> None:
        """Run a command while keeping optional sensitive input off argv."""


class PublicFetcher(Protocol):
    def fetch(self, url: str) -> bytes | None:
        """Fetch public bytes, or return None when the object is absent."""


class CachePurger(Protocol):
    def purge(self, urls: list[str]) -> None:
        """Purge the exact public URLs."""


@dataclass(frozen=True)
class WithdrawalRequest:
    bad_version: str
    bad_filename: str
    last_good_appcast: bytes
    evidence_directory: Path
    source_commit: str
    execute: bool
    credentials_present: bool = False
    confirmation: str = ""


@dataclass(frozen=True)
class IncidentRecord:
    schema_version: int
    bad_version: str
    bad_filename: str
    source_commit: str
    withdrawn_appcast_sha256: str
    withdrawn_archive_sha256: str
    restored_appcast_sha256: str
    recovery_paths: dict[str, str]


class BadReleaseWithdrawal:
    def __init__(self, origin: RecoveryOrigin) -> None:
        self.origin = origin

    def withdraw(self, request: WithdrawalRequest) -> list[str]:
        plan = [
            "validate the last-known-good signed appcast",
            "freeze routine publication",
            "preserve the bad feed and archive as private incident evidence",
            "remove the bad immutable archive and purge its public URL",
            "restore the last-known-good appcast byte-for-byte and purge it",
            "verify the bad archive is absent and the restored feed is exact",
        ]
        self._validate_request(request)
        if not request.execute:
            return plan
        if not request.credentials_present:
            raise RecoveryError(
                "Production withdrawal requires R2 and cache-purge credentials.",
            )
        expected_confirmation = f"WITHDRAW {request.bad_version}"
        if request.confirmation != expected_confirmation:
            raise RecoveryError(
                f"Production withdrawal requires confirmation: "
                f"{expected_confirmation}",
            )

        current_appcast = self.origin.fetch_appcast()
        archive = self.origin.fetch_archive(request.bad_filename)
        if current_appcast is None or archive is None:
            raise RecoveryError(
                "The live bad feed and archive must be captured before withdrawal.",
            )
        if not _feed_references_bad_release(
            current_appcast,
            request.bad_version,
            request.bad_filename,
        ):
            raise RecoveryError(
                "The live appcast does not advertise the named bad release.",
            )

        self.origin.freeze_publication(request)
        self._preserve_evidence(
            request=request,
            current_appcast=current_appcast,
            archive=archive,
        )
        archive_url = f"{UPDATE_ORIGIN}/releases/{request.bad_filename}"
        appcast_url = f"{UPDATE_ORIGIN}/appcast.xml"
        self.origin.remove_archive(request.bad_filename)
        self.origin.purge([archive_url])
        self.origin.verify_archive_absent(request.bad_filename)

        snapshot = request.evidence_directory / "last-known-good-appcast.xml"
        self.origin.restore_appcast(snapshot)
        self.origin.purge([appcast_url])
        self.origin.verify_appcast(request.last_good_appcast)
        return plan

    @staticmethod
    def _validate_request(request: WithdrawalRequest) -> None:
        if re.fullmatch(r"\d+\.\d+\.\d+", request.bad_version) is None:
            raise RecoveryError(
                f"Unsupported bad release version {request.bad_version}.",
            )
        expected_filename = f"FoldWise-Voice-{request.bad_version}.dmg"
        if request.bad_filename != expected_filename:
            raise RecoveryError(
                f"Expected bad archive {expected_filename}; "
                f"got {request.bad_filename}.",
            )
        decoded = request.last_good_appcast.decode("utf-8", errors="replace")
        if "sparkle-signatures:" not in decoded:
            raise RecoveryError(
                "The last-known-good appcast is not a signed feed snapshot.",
            )
        if _feed_references_bad_release(
            request.last_good_appcast,
            request.bad_version,
            request.bad_filename,
        ):
            raise RecoveryError(
                "The last-known-good appcast still advertises the bad release.",
            )

    @staticmethod
    def _preserve_evidence(
        *,
        request: WithdrawalRequest,
        current_appcast: bytes,
        archive: bytes,
    ) -> None:
        request.evidence_directory.mkdir(parents=True, exist_ok=False)
        withdrawn_appcast = request.evidence_directory / "withdrawn-appcast.xml"
        withdrawn_archive = request.evidence_directory / request.bad_filename
        last_good = request.evidence_directory / "last-known-good-appcast.xml"
        withdrawn_appcast.write_bytes(current_appcast)
        withdrawn_archive.write_bytes(archive)
        last_good.write_bytes(request.last_good_appcast)

        record = IncidentRecord(
            schema_version=1,
            bad_version=request.bad_version,
            bad_filename=request.bad_filename,
            source_commit=request.source_commit,
            withdrawn_appcast_sha256=hashlib.sha256(
                current_appcast,
            ).hexdigest(),
            withdrawn_archive_sha256=hashlib.sha256(archive).hexdigest(),
            restored_appcast_sha256=hashlib.sha256(
                request.last_good_appcast,
            ).hexdigest(),
            recovery_paths={
                "ed25519_private_key": (
                    "GitHub Actions secret SPARKLE_ED_PRIVATE_KEY plus the "
                    "offline recovery copy required by "
                    "docs/research/sparkle-bad-release-rollback-policy.md"
                ),
                "developer_id_identity": (
                    "GitHub Actions secrets MACOS_CERTIFICATE and "
                    "MACOS_CERTIFICATE_PASSWORD for Team 6849P798YW; see "
                    "docs/research/developer-id-certificate-rotation-policy.md"
                ),
            },
        )
        (request.evidence_directory / "incident.json").write_text(
            json.dumps(asdict(record), indent=2, sort_keys=True) + "\n",
        )


class R2RecoveryOrigin:
    def __init__(
        self,
        runner: InputCommandRunner,
        *,
        fetcher: PublicFetcher,
        purger: CachePurger,
        bucket: str,
        endpoint: str,
        public_base_url: str = UPDATE_ORIGIN,
    ) -> None:
        self.runner = runner
        self.fetcher = fetcher
        self.purger = purger
        self.bucket = bucket
        self.endpoint = endpoint
        self.public_base_url = public_base_url.rstrip("/")

    def fetch_appcast(self) -> bytes | None:
        return self.fetcher.fetch(f"{self.public_base_url}/appcast.xml")

    def fetch_archive(self, filename: str) -> bytes | None:
        return self.fetcher.fetch(
            f"{self.public_base_url}/releases/{filename}",
        )

    def freeze_publication(self, request: WithdrawalRequest) -> None:
        freeze_url = (
            f"{self.public_base_url}/controls/publication-frozen.json"
        )
        with tempfile.TemporaryDirectory(
            prefix="foldwise-recovery-",
        ) as directory:
            freeze = Path(directory) / "publication-frozen.json"
            freeze.write_text(
                json.dumps(
                    {
                        "frozen": True,
                        "bad_version": request.bad_version,
                        "bad_filename": request.bad_filename,
                        "source_commit": request.source_commit,
                    },
                    indent=2,
                    sort_keys=True,
                )
                + "\n",
            )
            self._put_object(
                key="controls/publication-frozen.json",
                body=freeze,
                content_type="application/json",
                cache_control="no-store",
            )
        self.purge([freeze_url])
        if self.fetcher.fetch(freeze_url) is None:
            raise RecoveryError(
                "The public publication freeze could not be verified.",
            )

    def remove_archive(self, filename: str) -> None:
        self.runner.run_input(
            [
                "aws",
                "--endpoint-url",
                self.endpoint,
                "s3api",
                "delete-object",
                "--bucket",
                self.bucket,
                "--key",
                f"releases/{filename}",
            ],
            None,
        )

    def restore_appcast(self, appcast: Path) -> None:
        self._put_object(
            key="appcast.xml",
            body=appcast,
            content_type="application/xml",
            cache_control="no-cache",
        )

    def purge(self, urls: list[str]) -> None:
        self.purger.purge(urls)

    def verify_archive_absent(self, filename: str) -> None:
        if self.fetch_archive(filename) is not None:
            raise RecoveryError(
                "The withdrawn archive still returns public bytes.",
            )

    def verify_appcast(self, expected: bytes) -> None:
        if self.fetch_appcast() != expected:
            raise RecoveryError(
                "The public appcast does not match the restored signed snapshot.",
            )

    def _put_object(
        self,
        *,
        key: str,
        body: Path,
        content_type: str,
        cache_control: str,
    ) -> None:
        self.runner.run_input(
            [
                "aws",
                "--endpoint-url",
                self.endpoint,
                "s3api",
                "put-object",
                "--bucket",
                self.bucket,
                "--key",
                key,
                "--body",
                str(body),
                "--content-type",
                content_type,
                "--cache-control",
                cache_control,
            ],
            None,
        )


def _feed_references_bad_release(
    appcast: bytes,
    bad_version: str,
    bad_filename: str,
) -> bool:
    try:
        root = ET.fromstring(appcast)
    except ET.ParseError as error:
        raise RecoveryError("The appcast snapshot is invalid XML.") from error
    namespace = (
        "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
    )
    for item in root.findall("./channel/item"):
        version = item.findtext(f"{namespace}version")
        enclosure = item.find("enclosure")
        if (
            version == bad_version
            and enclosure is not None
            and enclosure.get("url", "").endswith(f"/{bad_filename}")
        ):
            return True
    return False


class SystemInputRunner:
    def run_input(self, command: list[str], value: str | None) -> None:
        try:
            subprocess.run(
                command,
                check=True,
                text=True,
                input=value,
            )
        except subprocess.CalledProcessError as error:
            raise RecoveryError(
                f"{command[0]} exited with status {error.returncode}.",
            ) from error


class SystemPublicFetcher:
    def fetch(self, url: str) -> bytes | None:
        request = urllib.request.Request(
            url,
            headers={"Cache-Control": "no-cache"},
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return bytes(response.read())
        except urllib.error.HTTPError as error:
            if error.code == 404:
                return None
            raise RecoveryError(
                f"Public fetch failed for {url}: HTTP {error.code}.",
            ) from error
        except urllib.error.URLError as error:
            raise RecoveryError(
                f"Public fetch failed for {url}: {error.reason}.",
            ) from error


class CloudflareCachePurger:
    def __init__(self, *, zone_id: str, api_token: str) -> None:
        self.zone_id = zone_id
        self.api_token = api_token

    def purge(self, urls: list[str]) -> None:
        request = urllib.request.Request(
            (
                "https://api.cloudflare.com/client/v4/zones/"
                f"{self.zone_id}/purge_cache"
            ),
            data=json.dumps({"files": urls}).encode(),
            headers={
                "Authorization": f"Bearer {self.api_token}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                result = json.loads(response.read())
        except (
            urllib.error.HTTPError,
            urllib.error.URLError,
            json.JSONDecodeError,
        ) as error:
            raise RecoveryError(
                "Cloudflare cache purge failed.",
            ) from error
        if not isinstance(result, dict) or result.get("success") is not True:
            raise RecoveryError("Cloudflare rejected the cache purge.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    withdraw = subparsers.add_parser(
        "withdraw",
        help="plan or execute one bad-release withdrawal",
    )
    withdraw.add_argument("--bad-version", required=True)
    withdraw.add_argument("--last-good-appcast", type=Path, required=True)
    withdraw.add_argument("--last-good-record", type=Path)
    withdraw.add_argument("--evidence-directory", type=Path, required=True)
    withdraw.add_argument("--source-commit", required=True)
    withdraw.add_argument("--execute", action="store_true")
    withdraw.add_argument("--confirmation", default="")
    repair = subparsers.add_parser(
        "plan-forward-repair",
        help="validate and print a non-mutating Forward-repair plan",
    )
    repair.add_argument("--bad-version", required=True)
    repair.add_argument("--repair-version", required=True)
    repair.add_argument("--validation-reference", required=True)
    args = parser.parse_args()
    if args.command == "plan-forward-repair":
        from release_publication import PublicationError, PublicationPolicy

        expected_confirmation = (
            f"PUBLISH FORWARD REPAIR {args.repair_version}"
        )
        try:
            PublicationPolicy.forward_repair(
                bad_version=args.bad_version,
                repair_version=args.repair_version,
                validation_reference=args.validation_reference,
                confirmation=expected_confirmation,
            )
        except PublicationError as error:
            raise RecoveryError(str(error)) from error
        print("DRY RUN")
        print(
            "1. verify the repair version and build are strictly greater "
            "than the frozen bad version",
        )
        print("2. validate the installed bad build against the exact repair")
        print("3. publish an unphased critical update only after explicit action")
        print(f"Required confirmation: {expected_confirmation}")
        return

    last_good_appcast = args.last_good_appcast.read_bytes()
    if args.last_good_record is not None:
        record = json.loads(args.last_good_record.read_text())
        expected_digest = record.get("published_appcast_sha256")
        actual_digest = hashlib.sha256(last_good_appcast).hexdigest()
        if expected_digest != actual_digest:
            raise RecoveryError(
                "The last-known-good appcast does not match its release record.",
            )

    required_environment = {
        "AWS_ACCESS_KEY_ID": os.environ.get("AWS_ACCESS_KEY_ID"),
        "AWS_SECRET_ACCESS_KEY": os.environ.get("AWS_SECRET_ACCESS_KEY"),
        "UPDATE_R2_ACCOUNT_ID": os.environ.get("UPDATE_R2_ACCOUNT_ID"),
        "UPDATE_R2_BUCKET": os.environ.get("UPDATE_R2_BUCKET"),
        "UPDATE_CF_ZONE_ID": os.environ.get("UPDATE_CF_ZONE_ID"),
        "UPDATE_CF_API_TOKEN": os.environ.get("UPDATE_CF_API_TOKEN"),
    }
    credentials_present = all(required_environment.values())
    account_id = required_environment["UPDATE_R2_ACCOUNT_ID"] or "dry-run"
    origin = R2RecoveryOrigin(
        SystemInputRunner(),
        fetcher=SystemPublicFetcher(),
        purger=CloudflareCachePurger(
            zone_id=required_environment["UPDATE_CF_ZONE_ID"] or "dry-run",
            api_token=required_environment["UPDATE_CF_API_TOKEN"] or "dry-run",
        ),
        bucket=required_environment["UPDATE_R2_BUCKET"] or "dry-run",
        endpoint=f"https://{account_id}.r2.cloudflarestorage.com",
    )
    request = WithdrawalRequest(
        bad_version=args.bad_version,
        bad_filename=f"FoldWise-Voice-{args.bad_version}.dmg",
        last_good_appcast=last_good_appcast,
        evidence_directory=args.evidence_directory,
        source_commit=args.source_commit,
        execute=args.execute,
        credentials_present=credentials_present,
        confirmation=args.confirmation,
    )
    plan = BadReleaseWithdrawal(origin).withdraw(request)
    print("EXECUTE" if args.execute else "DRY RUN")
    for index, step in enumerate(plan, start=1):
        print(f"{index}. {step}")
    print(
        "Already prepared install-on-Quit updates cannot be recalled. "
        "For a non-critical prepared update, keep FoldWise open and choose "
        "Check for Updates… → Skip This Version before quitting. "
        "A prepared critical update has no supported standard-UI cancellation.",
    )


if __name__ == "__main__":
    try:
        main()
    except (OSError, RecoveryError, ValueError) as error:
        sys.exit(str(error))
