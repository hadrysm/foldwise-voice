#!/usr/bin/env python3
"""Publish one authenticated FoldWise update transaction."""

from __future__ import annotations

import hashlib
import html
import json
import re
import shutil
import tempfile
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Protocol

SPARKLE_VERSION = "2.9.4"
SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
UPDATE_ORIGIN = "https://updates.guarcode.com"
FULL_CHANGELOG_URL = "https://github.com/hadrysm/foldwise-voice/blob/main/CHANGELOG.md"


class PublicationError(RuntimeError):
    """The release cannot be published without violating its contract."""


class ArtifactMismatch(PublicationError):
    """Local, stored, or publicly served release bytes do not match."""


class InputCommandRunner(Protocol):
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
    ) -> Path:
        """Generate and validate a signed appcast for one exact archive."""


class UpdateOrigin(Protocol):
    def fetch_appcast(self) -> bytes | None:
        """Fetch the currently public signed appcast, when one exists."""

    def stage_archive(self, dmg: Path, sha256: str) -> None:
        """Publish immutable archive bytes and verify their public URL."""

    def publish_appcast(self, appcast: Path) -> None:
        """Publish and publicly verify the signed appcast."""


class GitHubRelease(Protocol):
    def stage_asset(self, tag: str, dmg: Path, sha256: str) -> None:
        """Attach and verify the exact DMG while the release stays draft."""

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
    ) -> Path:
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
            "--phased-rollout-interval",
            "86400",
            "-o",
            str(appcast),
            str(working_directory),
        ]
        self.runner.run_input(command, self.private_key)
        if not appcast.is_file():
            raise PublicationError("Sparkle did not generate appcast.xml.")
        if _sha256(archive) != digest_before or _sha256(dmg) != digest_before:
            raise ArtifactMismatch(
                "The release DMG changed during appcast generation.",
            )
        self._validate_appcast(appcast, version, dmg.name)
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
            "phasedRolloutInterval": "86400",
            "fullReleaseNotesLink": self.full_changelog_url,
        }
        for name, expected in expected_elements.items():
            value = item.findtext(f"{namespace}{name}")
            if value is None or value.strip() != expected:
                raise PublicationError(
                    f"The appcast has an unexpected sparkle:{name}.",
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
            headers={"Cache-Control": "no-cache"},
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return bytes(response.read())
        except urllib.error.HTTPError as error:
            if error.code == 404:
                return None
            raise PublicationError(
                f"Public fetch failed for {url}: HTTP {error.code}.",
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
    ) -> None:
        self.runner = runner
        self.fetcher = fetcher
        self.bucket = bucket
        self.endpoint = endpoint
        self.public_base_url = public_base_url.rstrip("/")

    def fetch_appcast(self) -> bytes | None:
        return self.fetcher.fetch(f"{self.public_base_url}/appcast.xml")

    def stage_archive(self, dmg: Path, sha256: str) -> None:
        if _sha256(dmg) != sha256:
            raise ArtifactMismatch(
                "The local DMG no longer matches its verified checksum.",
            )
        url = f"{self.public_base_url}/releases/{dmg.name}"
        current = self.fetcher.fetch(url)
        if current is not None:
            if hashlib.sha256(current).hexdigest() != sha256:
                raise ArtifactMismatch(
                    "The immutable archive URL already contains other bytes.",
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
                f"releases/{dmg.name}",
                "--body",
                str(dmg),
                "--content-type",
                "application/x-apple-diskimage",
                "--content-disposition",
                f'attachment; filename="{dmg.name}"',
                "--cache-control",
                "public, max-age=31536000, immutable",
                "--metadata",
                f"sha256={sha256}",
            ],
            None,
        )
        published = self.fetcher.fetch(url)
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
        published = self.fetcher.fetch(
            f"{self.public_base_url}/appcast.xml",
        )
        if published != expected:
            raise ArtifactMismatch(
                "The public appcast does not match the signed feed.",
            )


class AuthenticatedUpdatePublisher:
    def __init__(
        self,
        *,
        generator: AppcastGenerator,
        origin: UpdateOrigin,
        github: GitHubRelease,
        changelog: Path,
    ) -> None:
        self.generator = generator
        self.origin = origin
        self.github = github
        self.changelog = changelog

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
            )
            self.origin.stage_archive(dmg, sha256)
            self.github.stage_asset(tag, dmg, sha256)
            self.origin.publish_appcast(appcast)
            self.github.publish_draft(tag)
