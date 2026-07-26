#!/usr/bin/env python3
"""Publish one authenticated FoldWise update transaction."""

from __future__ import annotations

import hashlib
import html
import json
import re
import shutil
import tempfile
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

SPARKLE_VERSION = "2.9.4"
SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
UPDATE_ORIGIN = "https://updates.guarcode.com"
FULL_CHANGELOG_URL = "https://github.com/hadrysm/foldwise-voice/blob/main/CHANGELOG.md"
PUBLIC_FETCH_USER_AGENT = "FoldWise-Release-Publisher/1.0"


class PublicationError(RuntimeError):
    """The release cannot be published without violating its contract."""


class ArtifactMismatch(PublicationError):
    """Local, stored, or publicly served release bytes do not match."""


@dataclass(frozen=True)
class PublicationPolicy:
    release_version: str
    bad_version: str | None
    validation_reference: str | None

    def __post_init__(self) -> None:
        release_components = _version_components(self.release_version)
        repair_fields = (
            self.bad_version is not None,
            self.validation_reference is not None,
        )
        if any(repair_fields) and not all(repair_fields):
            raise PublicationError(
                "A publication policy must be entirely routine or Forward repair.",
            )
        if self.bad_version is None:
            return
        bad_components = _version_components(self.bad_version)
        if release_components <= bad_components:
            raise PublicationError(
                "A Forward repair must have a version greater than the bad release.",
            )
        if not self.validation_reference or not self.validation_reference.strip():
            raise PublicationError(
                "A Forward repair requires bad-to-repair validation evidence.",
            )

    @property
    def is_forward_repair(self) -> bool:
        return self.bad_version is not None

    @classmethod
    def routine(cls, release_version: str) -> PublicationPolicy:
        _version_components(release_version)
        return cls(
            release_version=release_version,
            bad_version=None,
            validation_reference=None,
        )

    @classmethod
    def forward_repair(
        cls,
        *,
        bad_version: str,
        repair_version: str,
        validation_reference: str,
        confirmation: str,
    ) -> PublicationPolicy:
        expected = f"PUBLISH FORWARD REPAIR {repair_version}"
        if confirmation != expected:
            raise PublicationError(
                f"Forward repair publication requires confirmation: {expected}",
            )
        return cls(
            release_version=repair_version,
            bad_version=bad_version,
            validation_reference=validation_reference,
        )


def _version_components(version: str) -> tuple[int, int, int]:
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)", version)
    if match is None:
        raise PublicationError(f"Unsupported release version {version}.")
    return tuple(int(component) for component in match.groups())


class InputCommandRunner(Protocol):
    def run_json(self, command: list[str]) -> dict[str, object]:
        """Run a command and return its JSON object output."""

    def run_input(self, command: list[str], value: str | None) -> None:
        """Run a command while keeping optional sensitive input off argv."""


class PublicFetcher(Protocol):
    def fetch(self, url: str) -> bytes | None:
        """Fetch public bytes, or return None when the object is absent."""


class AppcastGenerator(Protocol):
    def generate(
        self,
        *,
        dmg: Path,
        version: str,
        changelog: Path,
        previous_appcast: bytes | None,
        working_directory: Path,
        policy: PublicationPolicy | None = None,
    ) -> Path:
        """Generate and validate a signed appcast for one exact archive."""


class UpdateOrigin(Protocol):
    def assert_publication_allowed(self, policy: PublicationPolicy) -> None:
        """Fail when an incident freeze blocks this publication mode."""

    def fetch_appcast(self) -> bytes | None:
        """Fetch the currently public signed appcast, when one exists."""

    def stage_archive(self, dmg: Path, sha256: str) -> None:
        """Publish immutable archive bytes and verify their public URL."""

    def publish_appcast(self, appcast: Path) -> None:
        """Publish and publicly verify the signed appcast."""


class GitHubRelease(Protocol):
    def stage_asset(self, tag: str, asset: Path, sha256: str) -> None:
        """Attach and verify exact asset bytes while the release stays draft."""

    def publish_draft(self, tag: str) -> None:
        """Publish the fully staged draft release."""


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _render_inline_markdown(value: str) -> str:
    escaped = html.escape(value, quote=True)
    return re.sub(
        r"\[([^\]]+)\]\(([^)]+)\)",
        r'<a href="\2">\1</a>',
        escaped,
    )


def release_notes_html(changelog: str, version: str) -> str:
    """Render the matching release-please section as an HTML fragment."""
    heading = re.compile(
        rf"^## \[{re.escape(version)}\](?:\([^)]*\))?.*$",
        re.MULTILINE,
    )
    match = heading.search(changelog)
    if match is None:
        raise PublicationError(
            f"CHANGELOG.md has no section for version {version}.",
        )
    next_heading = re.search(
        r"^## \[",
        changelog[match.end() :],
        re.MULTILINE,
    )
    end = (
        match.end() + next_heading.start()
        if next_heading is not None
        else len(changelog)
    )
    lines = changelog[match.end() : end].strip().splitlines()
    output: list[str] = []
    paragraph: list[str] = []
    in_list = False

    def flush_paragraph() -> None:
        if paragraph:
            output.append(
                f"<p>{_render_inline_markdown(' '.join(paragraph))}</p>",
            )
            paragraph.clear()

    def close_list() -> None:
        nonlocal in_list
        if in_list:
            output.append("</ul>")
            in_list = False

    for line in lines:
        stripped = line.strip()
        subheading = re.match(r"^(#{3,6})\s+(.+)$", stripped)
        bullet = re.match(r"^[*-]\s+(.+)$", stripped)
        if not stripped:
            flush_paragraph()
            close_list()
        elif subheading is not None:
            flush_paragraph()
            close_list()
            level = len(subheading.group(1))
            output.append(
                f"<h{level}>{_render_inline_markdown(subheading.group(2))}</h{level}>",
            )
        elif bullet is not None:
            flush_paragraph()
            if not in_list:
                output.append("<ul>")
                in_list = True
            output.append(
                f"<li>{_render_inline_markdown(bullet.group(1))}</li>",
            )
        else:
            close_list()
            paragraph.append(stripped)

    flush_paragraph()
    close_list()
    if not output:
        raise PublicationError(
            f"CHANGELOG.md section for {version} has no release notes.",
        )
    return "\n".join(output) + "\n"


class SparkleAppcastGenerator:
    def __init__(
        self,
        runner: InputCommandRunner,
        *,
        tool: Path,
        package_resolved: Path,
        private_key: str,
        public_base_url: str = UPDATE_ORIGIN,
        full_changelog_url: str = FULL_CHANGELOG_URL,
    ) -> None:
        self.runner = runner
        self.tool = tool
        self.package_resolved = package_resolved
        self.private_key = private_key
        self.public_base_url = public_base_url.rstrip("/")
        self.full_changelog_url = full_changelog_url

    def generate(
        self,
        *,
        dmg: Path,
        version: str,
        changelog: Path,
        previous_appcast: bytes | None,
        working_directory: Path,
        policy: PublicationPolicy | None = None,
    ) -> Path:
        policy = policy or PublicationPolicy.routine(version)
        if policy.release_version != version:
            raise PublicationError(
                "The publication policy version does not match the release archive.",
            )
        self._validate_sparkle_pin()
        if not self.tool.is_file():
            raise PublicationError(
                f"Sparkle generate_appcast is missing at {self.tool}.",
            )
        if not dmg.is_file():
            raise PublicationError(f"Release archive is missing at {dmg}.")

        working_directory.mkdir(parents=True, exist_ok=True)
        archive = working_directory / dmg.name
        notes = working_directory / f"{dmg.stem}.html"
        appcast = working_directory / "appcast.xml"
        shutil.copy2(dmg, archive)
        notes.write_text(
            release_notes_html(changelog.read_text(), version),
        )
        if previous_appcast is not None:
            appcast.write_bytes(previous_appcast)
        else:
            appcast.unlink(missing_ok=True)

        digest_before = _sha256(archive)
        command = [
            str(self.tool),
            "--ed-key-file",
            "-",
            "--download-url-prefix",
            f"{self.public_base_url}/releases/",
            "--embed-release-notes",
            "--full-release-notes-url",
            self.full_changelog_url,
            "--versions",
            version,
            "--maximum-versions",
            "0",
            "--maximum-deltas",
            "0",
        ]
        if policy.is_forward_repair:
            command.extend(["--critical-update-version", ""])
        else:
            command.extend(["--phased-rollout-interval", "86400"])
        command.extend(["-o", str(appcast), str(working_directory)])
        self.runner.run_input(command, self.private_key)
        if not appcast.is_file():
            raise PublicationError("Sparkle did not generate appcast.xml.")
        if _sha256(archive) != digest_before or _sha256(dmg) != digest_before:
            raise ArtifactMismatch(
                "The release DMG changed during appcast generation.",
            )
        self._validate_appcast(appcast, version, dmg.name, policy)
        return appcast

    def _validate_sparkle_pin(self) -> None:
        try:
            resolved = json.loads(self.package_resolved.read_text())
            pins = resolved["pins"]
            versions = [
                pin["state"].get("version")
                for pin in pins
                if pin.get("identity") == "sparkle"
            ]
        except (
            FileNotFoundError,
            json.JSONDecodeError,
            KeyError,
            TypeError,
        ) as error:
            raise PublicationError(
                "Could not verify the resolved Sparkle version.",
            ) from error
        if versions != [SPARKLE_VERSION]:
            raise PublicationError(
                f"Expected Sparkle {SPARKLE_VERSION}; resolved {versions}.",
            )

    def _validate_appcast(
        self,
        appcast: Path,
        version: str,
        filename: str,
        policy: PublicationPolicy,
    ) -> None:
        appcast_bytes = appcast.read_bytes()
        try:
            root = ET.fromstring(appcast_bytes)
        except ET.ParseError as error:
            raise PublicationError(
                "Sparkle generated an invalid XML appcast.",
            ) from error
        namespace = f"{{{SPARKLE_NAMESPACE}}}"
        items = [
            candidate
            for candidate in root.findall("./channel/item")
            if candidate.findtext(f"{namespace}version") == version
        ]
        if len(items) != 1:
            raise PublicationError(
                "The appcast does not contain exactly one matching release item.",
            )
        item = items[0]
        expected_elements = {
            "version": version,
            "shortVersionString": version,
            "minimumSystemVersion": "14.0.0",
            "fullReleaseNotesLink": self.full_changelog_url,
        }
        for name, expected in expected_elements.items():
            value = item.findtext(f"{namespace}{name}")
            if value is None or value.strip() != expected:
                raise PublicationError(
                    f"The appcast has an unexpected sparkle:{name}.",
                )
        phased_interval = item.findtext(
            f"{namespace}phasedRolloutInterval",
        )
        critical_update = item.find(f"{namespace}criticalUpdate")
        if policy.is_forward_repair:
            if phased_interval is not None or critical_update is None:
                raise PublicationError(
                    "A Forward repair must be unphased and critical.",
                )
        elif phased_interval != "86400" or critical_update is not None:
            raise PublicationError(
                "A routine update must be phased and non-critical.",
            )
        enclosure = item.find("enclosure")
        if enclosure is None:
            raise PublicationError("The appcast item has no enclosure.")
        expected_url = f"{self.public_base_url}/releases/{filename}"
        if enclosure.get("url") != expected_url:
            raise PublicationError(
                "The appcast enclosure does not use the immutable archive URL.",
            )
        if not enclosure.get(f"{namespace}edSignature"):
            raise PublicationError(
                "The appcast enclosure has no Ed25519 signature.",
            )
        signature = re.search(
            rb"<!-- sparkle-signatures:\n"
            rb"edSignature: [A-Za-z0-9+/=]+\n"
            rb"length: ([0-9]+)\n"
            rb"-->\s*$",
            appcast_bytes,
        )
        if signature is None or int(signature.group(1)) != signature.start():
            raise PublicationError("The appcast feed is not signed.")
        if item.find("description") is None:
            raise PublicationError(
                "The appcast item has no version-scoped release notes.",
            )


class SystemPublicFetcher:
    def fetch(self, url: str) -> bytes | None:
        request = urllib.request.Request(
            url,
            headers={
                "Cache-Control": "no-cache",
                "User-Agent": PUBLIC_FETCH_USER_AGENT,
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return bytes(response.read())
        except urllib.error.HTTPError as error:
            status_code = error.code
            error.close()
            if status_code == 404:
                return None
            raise PublicationError(
                f"Public fetch failed for {url}: HTTP {status_code}.",
            ) from error
        except urllib.error.URLError as error:
            raise PublicationError(
                f"Public fetch failed for {url}: {error.reason}.",
            ) from error


class R2UpdateOrigin:
    def __init__(
        self,
        runner: InputCommandRunner,
        *,
        fetcher: PublicFetcher,
        bucket: str,
        endpoint: str,
        public_base_url: str = UPDATE_ORIGIN,
        verification_delays: tuple[float, ...] = (
            2.0,
            4.0,
            8.0,
            16.0,
            30.0,
        ),
        sleeper: Callable[[float], None] = time.sleep,
    ) -> None:
        self.runner = runner
        self.fetcher = fetcher
        self.bucket = bucket
        self.endpoint = endpoint
        self.public_base_url = public_base_url.rstrip("/")
        self.verification_delays = verification_delays
        self.sleeper = sleeper

    def assert_publication_allowed(self, policy: PublicationPolicy) -> None:
        freeze = self.fetcher.fetch(
            f"{self.public_base_url}/controls/publication-frozen.json",
        )
        if freeze is None:
            if policy.is_forward_repair:
                raise PublicationError(
                    "A Forward repair requires an active frozen incident.",
                )
            return
        if not policy.is_forward_repair:
            raise PublicationError(
                "Routine publication is frozen by an active release incident.",
            )
        try:
            incident = json.loads(freeze)
        except (json.JSONDecodeError, UnicodeDecodeError) as error:
            raise PublicationError(
                "The publication freeze is malformed; fail closed.",
            ) from error
        if (
            not isinstance(incident, dict)
            or incident.get("frozen") is not True
            or incident.get("bad_version") != policy.bad_version
        ):
            raise PublicationError(
                "The Forward repair does not match the active frozen incident.",
            )

    def fetch_appcast(self) -> bytes | None:
        return self.fetcher.fetch(f"{self.public_base_url}/appcast.xml")

    def stage_archive(self, dmg: Path, sha256: str) -> None:
        if _sha256(dmg) != sha256:
            raise ArtifactMismatch(
                "The local DMG no longer matches its verified checksum.",
            )
        url = f"{self.public_base_url}/releases/{dmg.name}"
        key = f"releases/{dmg.name}"
        if self._object_exists(key):
            self._verify_object(
                key,
                sha256=sha256,
                content_length=dmg.stat().st_size,
            )
            current = self.fetcher.fetch(url)
            if current is not None:
                if hashlib.sha256(current).hexdigest() != sha256:
                    raise ArtifactMismatch(
                        "The immutable archive URL already contains "
                        "other bytes.",
                    )
                return
            published = self._fetch_until(
                url,
                lambda value: (
                    value is not None
                    and hashlib.sha256(value).hexdigest() == sha256
                ),
            )
            if (
                published is None
                or hashlib.sha256(published).hexdigest() != sha256
            ):
                raise ArtifactMismatch(
                    "The existing R2 archive is not publicly serving "
                    "the verified DMG.",
                )
            return

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
                str(dmg),
                "--content-type",
                "application/x-apple-diskimage",
                "--content-disposition",
                f'attachment; filename="{dmg.name}"',
                "--cache-control",
                "public, max-age=31536000, immutable",
                "--if-none-match",
                "*",
                "--metadata",
                f"sha256={sha256}",
            ],
            None,
        )
        published = self._fetch_until(
            url,
            lambda value: (
                value is not None
                and hashlib.sha256(value).hexdigest() == sha256
            ),
        )
        if published is None or hashlib.sha256(published).hexdigest() != sha256:
            raise ArtifactMismatch(
                "The public archive bytes do not match the verified DMG.",
            )

    def publish_appcast(self, appcast: Path) -> None:
        expected = appcast.read_bytes()
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
                "appcast.xml",
                "--body",
                str(appcast),
                "--content-type",
                "application/xml",
                "--cache-control",
                "no-cache",
            ],
            None,
        )
        published = self._fetch_until(
            f"{self.public_base_url}/appcast.xml",
            lambda value: value == expected,
        )
        if published != expected:
            raise ArtifactMismatch(
                "The public appcast does not match the signed feed.",
            )

    def _object_exists(self, key: str) -> bool:
        response = self.runner.run_json(
            [
                "aws",
                "--endpoint-url",
                self.endpoint,
                "s3api",
                "list-objects-v2",
                "--bucket",
                self.bucket,
                "--prefix",
                key,
                "--max-keys",
                "2",
                "--output",
                "json",
            ]
        )
        contents = response.get("Contents", [])
        if not isinstance(contents, list):
            raise PublicationError("R2 returned an invalid object listing.")
        keys: list[str] = []
        for item in contents:
            listed_key = item.get("Key") if isinstance(item, dict) else None
            if not isinstance(listed_key, str):
                raise PublicationError("R2 returned an invalid object listing.")
            keys.append(listed_key)
        return key in keys

    def _verify_object(
        self,
        key: str,
        *,
        sha256: str,
        content_length: int,
    ) -> None:
        response = self.runner.run_json(
            [
                "aws",
                "--endpoint-url",
                self.endpoint,
                "s3api",
                "head-object",
                "--bucket",
                self.bucket,
                "--key",
                key,
                "--output",
                "json",
            ]
        )
        metadata = response.get("Metadata")
        stored_length = response.get("ContentLength")
        if (
            not isinstance(metadata, dict)
            or metadata.get("sha256") != sha256
            or stored_length != content_length
        ):
            raise ArtifactMismatch(
                "The existing R2 archive metadata does not match "
                "the verified DMG.",
            )

    def _fetch_until(
        self,
        url: str,
        matches: Callable[[bytes | None], bool],
    ) -> bytes | None:
        published = self.fetcher.fetch(url)
        for delay in self.verification_delays:
            if matches(published):
                return published
            self.sleeper(delay)
            published = self.fetcher.fetch(url)
        return published


class AuthenticatedUpdatePublisher:
    def __init__(
        self,
        *,
        generator: AppcastGenerator,
        origin: UpdateOrigin,
        github: GitHubRelease,
        changelog: Path,
        policy: PublicationPolicy | None = None,
        record_directory: Path | None = None,
        source_commit: str | None = None,
        source_run_id: str | None = None,
    ) -> None:
        self.generator = generator
        self.origin = origin
        self.github = github
        self.changelog = changelog
        self.policy = policy
        self.record_directory = record_directory
        self.source_commit = source_commit
        self.source_run_id = source_run_id

    def publish(self, tag: str, dmg: Path, sha256: str) -> None:
        if _sha256(dmg) != sha256:
            raise ArtifactMismatch(
                "The DMG changed after release artifact verification.",
            )
        version_match = re.fullmatch(r"v?(\d+\.\d+\.\d+)", tag)
        if version_match is None:
            raise PublicationError(f"Unsupported release tag {tag}.")
        version = version_match.group(1)
        expected_filename = f"FoldWise-Voice-{version}.dmg"
        if dmg.name != expected_filename:
            raise PublicationError(
                f"Expected release archive {expected_filename}; got {dmg.name}.",
            )

        policy = self.policy or PublicationPolicy.routine(version)
        if policy.release_version != version:
            raise PublicationError(
                "The publication policy does not match the release tag.",
            )
        self.origin.assert_publication_allowed(policy)
        previous_appcast = self.origin.fetch_appcast()
        with tempfile.TemporaryDirectory(
            prefix="foldwise-publication-",
        ) as directory:
            appcast = self.generator.generate(
                dmg=dmg,
                version=version,
                changelog=self.changelog,
                previous_appcast=previous_appcast,
                working_directory=Path(directory),
                policy=policy,
            )
            record_files = self._preserve_record(
                tag=tag,
                dmg=dmg,
                sha256=sha256,
                previous_appcast=previous_appcast,
                appcast=appcast,
                policy=policy,
            )
            self.origin.stage_archive(dmg, sha256)
            self.github.stage_asset(tag, dmg, sha256)
            for record_file in record_files:
                self.github.stage_asset(
                    tag,
                    record_file,
                    _sha256(record_file),
                )
            self.origin.publish_appcast(appcast)
            self.github.publish_draft(tag)

    def _preserve_record(
        self,
        *,
        tag: str,
        dmg: Path,
        sha256: str,
        previous_appcast: bytes | None,
        appcast: Path,
        policy: PublicationPolicy,
    ) -> list[Path]:
        if self.record_directory is None:
            return []
        self.record_directory.mkdir(parents=True, exist_ok=True)
        retained_dmg = self.record_directory / dmg.name
        if retained_dmg.resolve() != dmg.resolve():
            shutil.copy2(dmg, retained_dmg)
        record_files: list[Path] = []
        if previous_appcast is not None:
            previous = self.record_directory / "appcast-before.xml"
            previous.write_bytes(previous_appcast)
            record_files.append(previous)
        published = appcast.read_bytes()
        published_snapshot = self.record_directory / "appcast-published.xml"
        published_snapshot.write_bytes(published)
        record_files.append(published_snapshot)
        record = {
            "schema_version": 1,
            "tag": tag,
            "version": policy.release_version,
            "bad_version": policy.bad_version,
            "validation_reference": policy.validation_reference,
            "filename": dmg.name,
            "sha256": sha256,
            "source_commit": self.source_commit,
            "source_run_id": self.source_run_id,
            "previous_appcast_sha256": (
                hashlib.sha256(previous_appcast).hexdigest()
                if previous_appcast is not None
                else None
            ),
            "published_appcast_sha256": hashlib.sha256(published).hexdigest(),
            "recovery_paths": {
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
        }
        publication_record = self.record_directory / "publication.json"
        publication_record.write_text(
            json.dumps(record, indent=2, sort_keys=True) + "\n",
        )
        record_files.append(publication_record)
        return record_files
