from __future__ import annotations

import hashlib
import http.server
import importlib.util
import json
import sys
import tempfile
import threading
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).parents[1] / "release_publication.py"
SPEC = importlib.util.spec_from_file_location("release_publication", MODULE_PATH)
assert SPEC is not None
assert SPEC.loader is not None
release_publication = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = release_publication
SPEC.loader.exec_module(release_publication)


class FakeInputRunner:
    def __init__(
        self,
        generated_appcast: str | None = None,
        *,
        object_list: dict[str, object] | None = None,
        head_object: dict[str, object] | None = None,
    ) -> None:
        self.generated_appcast = generated_appcast
        self.object_list = object_list or {}
        self.head_object = head_object or {}
        self.commands: list[list[str]] = []
        self.json_commands: list[list[str]] = []
        self.standard_inputs: list[str | None] = []

    def run_json(self, command: list[str]) -> dict[str, object]:
        self.json_commands.append(command)
        if "head-object" in command:
            return self.head_object
        return self.object_list

    def run_input(self, command: list[str], value: str | None) -> None:
        self.commands.append(command)
        self.standard_inputs.append(value)
        if self.generated_appcast is not None and "-o" in command:
            output = Path(command[command.index("-o") + 1])
            output.write_text(self.generated_appcast)


class FakeFetcher:
    def __init__(
        self,
        responses: dict[str, bytes | None | list[bytes | None]],
    ) -> None:
        self.responses = responses
        self.requests: list[str] = []

    def fetch(self, url: str) -> bytes | None:
        self.requests.append(url)
        response = self.responses.get(url)
        if isinstance(response, list):
            return response.pop(0)
        return response


class FakeGenerator:
    def __init__(self, events: list[str], appcast: bytes) -> None:
        self.events = events
        self.appcast = appcast
        self.previous_appcasts: list[bytes | None] = []

    def generate(
        self,
        *,
        dmg: Path,
        version: str,
        changelog: Path,
        previous_appcast: bytes | None,
        working_directory: Path,
        policy: release_publication.PublicationPolicy | None = None,
    ) -> Path:
        self.events.append("generate appcast")
        self.previous_appcasts.append(previous_appcast)
        output = working_directory / "appcast.xml"
        output.write_bytes(self.appcast)
        return output


class FailingGenerator:
    def __init__(self, events: list[str]) -> None:
        self.events = events

    def generate(
        self,
        *,
        dmg: Path,
        version: str,
        changelog: Path,
        previous_appcast: bytes | None,
        working_directory: Path,
        policy: release_publication.PublicationPolicy | None = None,
    ) -> Path:
        self.events.append("generate appcast")
        raise release_publication.PublicationError("generation failed")


class FakeOrigin:
    def __init__(
        self,
        events: list[str],
        previous_appcast: bytes | None = None,
        frozen: bool = False,
        frozen_bad_version: str | None = None,
    ) -> None:
        self.events = events
        self.previous_appcast = previous_appcast
        self.frozen = frozen
        self.frozen_bad_version = frozen_bad_version
        self.archives: list[tuple[Path, str]] = []
        self.appcasts: list[Path] = []

    def assert_publication_allowed(
        self,
        policy: release_publication.PublicationPolicy,
    ) -> None:
        self.events.append("check publication freeze")
        if not self.frozen:
            return
        if (
            not policy.is_forward_repair
            or policy.bad_version != self.frozen_bad_version
        ):
            raise release_publication.PublicationError("publication frozen")

    def fetch_appcast(self) -> bytes | None:
        self.events.append("fetch appcast")
        return self.previous_appcast

    def stage_archive(self, dmg: Path, sha256: str) -> None:
        self.events.append("stage archive")
        self.archives.append((dmg, sha256))

    def publish_appcast(self, appcast: Path) -> None:
        self.events.append("publish appcast")
        self.appcasts.append(appcast)


class FakeGitHubRelease:
    def __init__(self, events: list[str]) -> None:
        self.events = events
        self.staged: list[tuple[str, Path, str]] = []
        self.published: list[str] = []

    def stage_asset(self, tag: str, dmg: Path, sha256: str) -> None:
        self.events.append("stage GitHub asset")
        self.staged.append((tag, dmg, sha256))

    def publish_draft(self, tag: str) -> None:
        self.events.append("publish GitHub release")
        self.published.append(tag)


def appcast_xml(
    version: str,
    filename: str,
    *,
    critical: bool = False,
    phased: bool = True,
) -> str:
    rollout = (
        "      <sparkle:phasedRolloutInterval>86400"
        "</sparkle:phasedRolloutInterval>\n"
        if phased
        else ""
    )
    critical_update = "      <sparkle:criticalUpdate />\n" if critical else ""
    content = f"""<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     version="2.0">
  <channel>
    <item>
      <sparkle:version>{version}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0.0</sparkle:minimumSystemVersion>
{rollout}{critical_update}\
      <sparkle:fullReleaseNotesLink>
        https://github.com/hadrysm/foldwise-voice/blob/main/CHANGELOG.md
      </sparkle:fullReleaseNotesLink>
      <description><![CDATA[<h3>Features</h3>]]></description>
      <enclosure
        url="https://updates.guarcode.com/releases/{filename}"
        sparkle:edSignature="archive-signature"
        length="17"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
"""
    return (
        content
        + "<!-- sparkle-signatures:\n"
        + "edSignature: c2lnbmVkLWZlZWQ=\n"
        + f"length: {len(content.encode())}\n"
        + "-->\n"
    )


class ReleaseNotesTests(unittest.TestCase):
    def testExtractReleaseNotesUsesOnlyMatchingChangelogSection(self) -> None:
        changelog = """# Changelog

## [0.18.0](compare-link) (2026-07-26)

### Features

* ship authenticated updates ([abc123](commit-link))

## [0.17.0](compare-link) (2026-07-25)

Older release.
"""

        notes = release_publication.release_notes_html(changelog, "0.18.0")

        self.assertIn("<h3>Features</h3>", notes)
        self.assertIn("ship authenticated updates", notes)
        self.assertNotIn("Older release", notes)


class SparkleAppcastGeneratorTests(unittest.TestCase):
    def testGeneratePinsSparkleAndConfiguresCompletePhasedHistory(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            dmg = root / "FoldWise-Voice-0.18.0.dmg"
            dmg.write_bytes(b"stapled DMG bytes")
            changelog = root / "CHANGELOG.md"
            changelog.write_text(
                "# Changelog\n\n## [0.18.0](link)\n\n### Features\n\n* Updates\n"
            )
            resolved = root / "Package.resolved"
            resolved.write_text(
                json.dumps(
                    {
                        "pins": [
                            {
                                "identity": "sparkle",
                                "state": {"version": "2.9.4"},
                            }
                        ]
                    }
                )
            )
            tool = root / "generate_appcast"
            tool.touch()
            runner = FakeInputRunner(
                appcast_xml("0.18.0", dmg.name),
            )
            previous = b"<rss>previous signed history</rss>"

            output = release_publication.SparkleAppcastGenerator(
                runner,
                tool=tool,
                package_resolved=resolved,
                private_key="private signing material",
            ).generate(
                dmg=dmg,
                version="0.18.0",
                changelog=changelog,
                previous_appcast=previous,
                working_directory=root / "publication",
            )

            command = runner.commands[0]
            self.assertEqual(output.read_text(), appcast_xml("0.18.0", dmg.name))
            self.assertIn("--maximum-versions", command)
            self.assertEqual(command[command.index("--maximum-versions") + 1], "0")
            self.assertIn("--maximum-deltas", command)
            self.assertEqual(command[command.index("--maximum-deltas") + 1], "0")
            self.assertEqual(
                command[command.index("--phased-rollout-interval") + 1],
                "86400",
            )
            self.assertNotIn("--auto-prune-update-files", command)
            self.assertNotIn("private signing material", command)
            self.assertEqual(runner.standard_inputs, ["private signing material"])
            self.assertEqual(
                (root / "publication" / "appcast.xml").read_bytes(),
                output.read_bytes(),
            )

    def testGenerateForwardRepairIsUnphasedAndCritical(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            dmg = root / "FoldWise-Voice-0.18.1.dmg"
            dmg.write_bytes(b"stapled repair DMG bytes")
            changelog = root / "CHANGELOG.md"
            changelog.write_text(
                "# Changelog\n\n## [0.18.1](link)\n\n### Fixes\n\n* Repair\n"
            )
            resolved = root / "Package.resolved"
            resolved.write_text(
                json.dumps(
                    {
                        "pins": [
                            {
                                "identity": "sparkle",
                                "state": {"version": "2.9.4"},
                            }
                        ]
                    }
                )
            )
            tool = root / "generate_appcast"
            tool.touch()
            runner = FakeInputRunner(
                appcast_xml(
                    "0.18.1",
                    dmg.name,
                    critical=True,
                    phased=False,
                ),
            )
            policy = release_publication.PublicationPolicy.forward_repair(
                bad_version="0.18.0",
                repair_version="0.18.1",
                validation_reference="acceptance-run-123",
                confirmation="PUBLISH FORWARD REPAIR 0.18.1",
            )

            release_publication.SparkleAppcastGenerator(
                runner,
                tool=tool,
                package_resolved=resolved,
                private_key="private signing material",
            ).generate(
                dmg=dmg,
                version="0.18.1",
                changelog=changelog,
                previous_appcast=b"<rss>known-good history</rss>",
                working_directory=root / "publication",
                policy=policy,
            )

            command = runner.commands[0]
            self.assertNotIn("--phased-rollout-interval", command)
            self.assertEqual(
                command[command.index("--critical-update-version") + 1],
                "",
            )

    def testGenerateRoutineRejectsCriticalItem(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            dmg = root / "FoldWise-Voice-0.18.0.dmg"
            dmg.write_bytes(b"stapled DMG bytes")
            changelog = root / "CHANGELOG.md"
            changelog.write_text(
                "# Changelog\n\n## [0.18.0](link)\n\n### Features\n\n* Update\n"
            )
            resolved = root / "Package.resolved"
            resolved.write_text(
                json.dumps(
                    {
                        "pins": [
                            {
                                "identity": "sparkle",
                                "state": {"version": "2.9.4"},
                            }
                        ]
                    }
                )
            )
            tool = root / "generate_appcast"
            tool.touch()
            runner = FakeInputRunner(
                appcast_xml(
                    "0.18.0",
                    dmg.name,
                    critical=True,
                    phased=False,
                ),
            )

            with self.assertRaises(release_publication.PublicationError):
                release_publication.SparkleAppcastGenerator(
                    runner,
                    tool=tool,
                    package_resolved=resolved,
                    private_key="private signing material",
                ).generate(
                    dmg=dmg,
                    version="0.18.0",
                    changelog=changelog,
                    previous_appcast=None,
                    working_directory=root / "publication",
                )

    def testGenerateRejectsUnexpectedSparkleVersion(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            resolved = root / "Package.resolved"
            resolved.write_text(
                json.dumps(
                    {
                        "pins": [
                            {
                                "identity": "sparkle",
                                "state": {"version": "2.10.0"},
                            }
                        ]
                    }
                )
            )
            runner = FakeInputRunner()

            with self.assertRaises(release_publication.PublicationError):
                release_publication.SparkleAppcastGenerator(
                    runner,
                    tool=root / "generate_appcast",
                    package_resolved=resolved,
                    private_key="private signing material",
                ).generate(
                    dmg=root / "FoldWise-Voice-0.18.0.dmg",
                    version="0.18.0",
                    changelog=root / "CHANGELOG.md",
                    previous_appcast=None,
                    working_directory=root / "publication",
                )

            self.assertEqual(runner.commands, [])


class SystemPublicFetcherTests(unittest.TestCase):
    def testFetchUsesApplicationUserAgentAcceptedByCloudflare(self) -> None:
        class CloudflareLikeHandler(http.server.BaseHTTPRequestHandler):
            def do_GET(self) -> None:
                user_agent = self.headers.get("User-Agent", "")
                status = (
                    404
                    if user_agent == "FoldWise-Release-Publisher/1.0"
                    else 403
                )
                self.send_response(status)
                self.end_headers()

            def log_message(self, format: str, *args: object) -> None:
                pass

        server = http.server.ThreadingHTTPServer(
            ("127.0.0.1", 0),
            CloudflareLikeHandler,
        )
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            result = release_publication.SystemPublicFetcher().fetch(
                "http://127.0.0.1:"
                f"{server.server_port}/controls/publication-frozen.json",
            )
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

        self.assertIsNone(result)


class R2UpdateOriginTests(unittest.TestCase):
    def testRoutinePublicationStopsWhenIncidentFreezeIsPublic(self) -> None:
        freeze_url = (
            "https://updates.guarcode.com/"
            "controls/publication-frozen.json"
        )
        origin = release_publication.R2UpdateOrigin(
            FakeInputRunner(),
            fetcher=FakeFetcher({freeze_url: b'{"frozen": true}\n'}),
            bucket="foldwise-updates",
            endpoint="https://account.r2.cloudflarestorage.com",
        )

        with self.assertRaises(release_publication.PublicationError):
            origin.assert_publication_allowed(
                release_publication.PublicationPolicy.routine("0.18.0"),
            )

    def testForwardRepairMustMatchTheFrozenIncidentVersion(self) -> None:
        freeze_url = (
            "https://updates.guarcode.com/"
            "controls/publication-frozen.json"
        )
        policy = release_publication.PublicationPolicy.forward_repair(
            bad_version="0.18.0",
            repair_version="0.18.1",
            validation_reference="acceptance-run-123",
            confirmation="PUBLISH FORWARD REPAIR 0.18.1",
        )
        origin = release_publication.R2UpdateOrigin(
            FakeInputRunner(),
            fetcher=FakeFetcher(
                {
                    freeze_url: json.dumps(
                        {
                            "frozen": True,
                            "bad_version": "0.19.0",
                        }
                    ).encode()
                }
            ),
            bucket="foldwise-updates",
            endpoint="https://account.r2.cloudflarestorage.com",
        )

        with self.assertRaises(release_publication.PublicationError):
            origin.assert_publication_allowed(policy)

    def testForwardRepairRequiresAnActiveFrozenIncident(self) -> None:
        freeze_url = (
            "https://updates.guarcode.com/"
            "controls/publication-frozen.json"
        )
        policy = release_publication.PublicationPolicy.forward_repair(
            bad_version="0.18.0",
            repair_version="0.18.1",
            validation_reference="acceptance-run-123",
            confirmation="PUBLISH FORWARD REPAIR 0.18.1",
        )
        origin = release_publication.R2UpdateOrigin(
            FakeInputRunner(),
            fetcher=FakeFetcher({freeze_url: None}),
            bucket="foldwise-updates",
            endpoint="https://account.r2.cloudflarestorage.com",
        )

        with self.assertRaises(release_publication.PublicationError):
            origin.assert_publication_allowed(policy)

    def testForwardRepairMayPublishOnlyForTheFrozenIncidentVersion(self) -> None:
        freeze_url = (
            "https://updates.guarcode.com/"
            "controls/publication-frozen.json"
        )
        policy = release_publication.PublicationPolicy.forward_repair(
            bad_version="0.18.0",
            repair_version="0.18.1",
            validation_reference="acceptance-run-123",
            confirmation="PUBLISH FORWARD REPAIR 0.18.1",
        )
        origin = release_publication.R2UpdateOrigin(
            FakeInputRunner(),
            fetcher=FakeFetcher(
                {
                    freeze_url: json.dumps(
                        {
                            "frozen": True,
                            "bad_version": "0.18.0",
                        }
                    ).encode()
                }
            ),
            bucket="foldwise-updates",
            endpoint="https://account.r2.cloudflarestorage.com",
        )

        origin.assert_publication_allowed(policy)

    def testStageArchiveUploadsImmutableMetadataThenVerifiesPublicBytes(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            dmg = Path(directory) / "FoldWise-Voice-0.18.0.dmg"
            dmg.write_bytes(b"stapled DMG bytes")
            digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
            url = f"https://updates.guarcode.com/releases/{dmg.name}"
            fetcher = FakeFetcher({url: [None, dmg.read_bytes()]})
            runner = FakeInputRunner()
            origin = release_publication.R2UpdateOrigin(
                runner,
                fetcher=fetcher,
                bucket="foldwise-updates",
                endpoint="https://account.r2.cloudflarestorage.com",
                public_base_url="https://updates.guarcode.com",
            )

            origin.stage_archive(dmg, digest)

            command = runner.commands[0]
            self.assertIn("put-object", command)
            self.assertEqual(
                command[command.index("--cache-control") + 1],
                "public, max-age=31536000, immutable",
            )
            self.assertEqual(
                command[command.index("--content-type") + 1],
                "application/x-apple-diskimage",
            )
            self.assertEqual(
                command[command.index("--if-none-match") + 1],
                "*",
            )
            self.assertEqual(fetcher.requests, [url, url])

    def testStageArchiveRefusesToOverwriteDifferentPublicBytes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            dmg = Path(directory) / "FoldWise-Voice-0.18.0.dmg"
            dmg.write_bytes(b"stapled DMG bytes")
            digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
            url = f"https://updates.guarcode.com/releases/{dmg.name}"
            runner = FakeInputRunner()
            origin = release_publication.R2UpdateOrigin(
                runner,
                fetcher=FakeFetcher({url: b"different published bytes"}),
                bucket="foldwise-updates",
                endpoint="https://account.r2.cloudflarestorage.com",
                public_base_url="https://updates.guarcode.com",
            )

            with self.assertRaises(release_publication.ArtifactMismatch):
                origin.stage_archive(dmg, digest)

            self.assertEqual(runner.commands, [])

    def testStageArchiveRetriesPublicVerificationAfterUpload(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            dmg = Path(directory) / "FoldWise-Voice-0.18.0.dmg"
            dmg.write_bytes(b"stapled DMG bytes")
            digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
            url = f"https://updates.guarcode.com/releases/{dmg.name}"
            fetcher = FakeFetcher(
                {
                    url: [
                        None,
                        b"temporarily stale public bytes",
                        dmg.read_bytes(),
                    ]
                }
            )
            delays: list[float] = []
            origin = release_publication.R2UpdateOrigin(
                FakeInputRunner(),
                fetcher=fetcher,
                bucket="foldwise-updates",
                endpoint="https://account.r2.cloudflarestorage.com",
                public_base_url="https://updates.guarcode.com",
                verification_delays=(1.0,),
                sleeper=delays.append,
            )

            origin.stage_archive(dmg, digest)

            self.assertEqual(fetcher.requests, [url, url, url])
            self.assertEqual(delays, [1.0])

    def testStageArchiveWaitsWhenR2AlreadyHasHiddenObject(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            dmg = Path(directory) / "FoldWise-Voice-0.18.0.dmg"
            dmg.write_bytes(b"stapled DMG bytes")
            digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
            key = f"releases/{dmg.name}"
            url = f"https://updates.guarcode.com/{key}"
            fetcher = FakeFetcher({url: [None, None, dmg.read_bytes()]})
            runner = FakeInputRunner(
                object_list={"Contents": [{"Key": key}]},
                head_object={
                    "Metadata": {"sha256": digest},
                    "ContentLength": dmg.stat().st_size,
                },
            )
            delays: list[float] = []
            origin = release_publication.R2UpdateOrigin(
                runner,
                fetcher=fetcher,
                bucket="foldwise-updates",
                endpoint="https://account.r2.cloudflarestorage.com",
                public_base_url="https://updates.guarcode.com",
                verification_delays=(1.0,),
                sleeper=delays.append,
            )

            origin.stage_archive(dmg, digest)

            self.assertEqual(runner.commands, [])
            self.assertEqual(len(runner.json_commands), 2)
            self.assertEqual(fetcher.requests, [url, url, url])
            self.assertEqual(delays, [1.0])

    def testStageArchiveRejectsDifferentAuthoritativeR2Object(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            dmg = Path(directory) / "FoldWise-Voice-0.18.0.dmg"
            dmg.write_bytes(b"stapled DMG bytes")
            digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
            key = f"releases/{dmg.name}"
            url = f"https://updates.guarcode.com/{key}"
            runner = FakeInputRunner(
                object_list={"Contents": [{"Key": key}]},
                head_object={
                    "Metadata": {"sha256": "b" * 64},
                    "ContentLength": dmg.stat().st_size,
                },
            )
            origin = release_publication.R2UpdateOrigin(
                runner,
                fetcher=FakeFetcher({url: None}),
                bucket="foldwise-updates",
                endpoint="https://account.r2.cloudflarestorage.com",
                public_base_url="https://updates.guarcode.com",
                verification_delays=(),
            )

            with self.assertRaises(release_publication.ArtifactMismatch):
                origin.stage_archive(dmg, digest)

            self.assertEqual(runner.commands, [])
            self.assertEqual(len(runner.json_commands), 2)

    def testStageArchiveChecksR2WhenCachedPublicBytesMatch(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            dmg = Path(directory) / "FoldWise-Voice-0.18.0.dmg"
            dmg.write_bytes(b"stapled DMG bytes")
            digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
            key = f"releases/{dmg.name}"
            url = f"https://updates.guarcode.com/{key}"
            runner = FakeInputRunner(
                object_list={"Contents": [{"Key": key}]},
                head_object={
                    "Metadata": {"sha256": "b" * 64},
                    "ContentLength": dmg.stat().st_size,
                },
            )
            origin = release_publication.R2UpdateOrigin(
                runner,
                fetcher=FakeFetcher({url: dmg.read_bytes()}),
                bucket="foldwise-updates",
                endpoint="https://account.r2.cloudflarestorage.com",
                public_base_url="https://updates.guarcode.com",
            )

            with self.assertRaises(release_publication.ArtifactMismatch):
                origin.stage_archive(dmg, digest)

            self.assertEqual(runner.commands, [])
            self.assertEqual(len(runner.json_commands), 2)

    def testPublishAppcastUsesCacheBypassMetadata(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            appcast = Path(directory) / "appcast.xml"
            appcast.write_bytes(b"<rss>signed appcast</rss>")
            url = "https://updates.guarcode.com/appcast.xml"
            fetcher = FakeFetcher({url: b"<rss>signed appcast</rss>"})
            runner = FakeInputRunner()
            origin = release_publication.R2UpdateOrigin(
                runner,
                fetcher=fetcher,
                bucket="foldwise-updates",
                endpoint="https://account.r2.cloudflarestorage.com",
                public_base_url="https://updates.guarcode.com",
            )

            origin.publish_appcast(appcast)

            command = runner.commands[0]
            self.assertEqual(
                command[command.index("--cache-control") + 1],
                "no-cache",
            )
            self.assertEqual(
                command[command.index("--content-type") + 1],
                "application/xml",
            )
            self.assertEqual(fetcher.requests, [url])

    def testPublishAppcastRetriesPublicVerificationAfterUpload(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            appcast = Path(directory) / "appcast.xml"
            appcast.write_bytes(b"<rss>new signed appcast</rss>")
            url = "https://updates.guarcode.com/appcast.xml"
            fetcher = FakeFetcher(
                {
                    url: [
                        b"<rss>previous appcast</rss>",
                        appcast.read_bytes(),
                    ]
                }
            )
            delays: list[float] = []
            origin = release_publication.R2UpdateOrigin(
                FakeInputRunner(),
                fetcher=fetcher,
                bucket="foldwise-updates",
                endpoint="https://account.r2.cloudflarestorage.com",
                public_base_url="https://updates.guarcode.com",
                verification_delays=(1.0,),
                sleeper=delays.append,
            )

            origin.publish_appcast(appcast)

            self.assertEqual(fetcher.requests, [url, url])
            self.assertEqual(delays, [1.0])


class AuthenticatedUpdatePublisherTests(unittest.TestCase):
    def testForwardRepairRequiresNewerVersionValidationAndConfirmation(
        self,
    ) -> None:
        invalid_requests = [
            {
                "bad_version": "0.18.0",
                "repair_version": "0.18.0",
                "validation_reference": "acceptance-run-123",
                "confirmation": "PUBLISH FORWARD REPAIR 0.18.0",
            },
            {
                "bad_version": "0.18.0",
                "repair_version": "0.18.1",
                "validation_reference": "",
                "confirmation": "PUBLISH FORWARD REPAIR 0.18.1",
            },
            {
                "bad_version": "0.18.0",
                "repair_version": "0.18.1",
                "validation_reference": "acceptance-run-123",
                "confirmation": "yes",
            },
        ]

        for request in invalid_requests:
            with self.subTest(request=request):
                with self.assertRaises(release_publication.PublicationError):
                    release_publication.PublicationPolicy.forward_repair(**request)

    def testPublicationPolicyRejectsInvalidDirectState(self) -> None:
        with self.assertRaises(release_publication.PublicationError):
            release_publication.PublicationPolicy(
                release_version="0.18.1",
                bad_version=None,
                validation_reference="acceptance-run-123",
            )

    def testPublishOrdersArchiveVerificationBeforeSignedAppcastAndRelease(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            dmg = root / "FoldWise-Voice-0.18.0.dmg"
            dmg.write_bytes(b"stapled DMG bytes")
            digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
            changelog = root / "CHANGELOG.md"
            changelog.write_text("# Changelog")
            events: list[str] = []
            origin = FakeOrigin(events, b"<rss>previous appcast</rss>")
            github = FakeGitHubRelease(events)

            release_publication.AuthenticatedUpdatePublisher(
                generator=FakeGenerator(events, b"<rss>new signed appcast</rss>"),
                origin=origin,
                github=github,
                changelog=changelog,
            ).publish("v0.18.0", dmg, digest)

            self.assertEqual(
                events,
                [
                    "check publication freeze",
                    "fetch appcast",
                    "generate appcast",
                    "stage archive",
                    "stage GitHub asset",
                    "publish appcast",
                    "publish GitHub release",
                ],
            )
            self.assertEqual(origin.archives, [(dmg, digest)])
            self.assertEqual(github.staged, [("v0.18.0", dmg, digest)])
            self.assertEqual(github.published, ["v0.18.0"])

    def testPublishRejectsArtifactChangedAfterVerification(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            dmg = root / "FoldWise-Voice-0.18.0.dmg"
            dmg.write_bytes(b"changed DMG bytes")
            events: list[str] = []

            with self.assertRaises(release_publication.ArtifactMismatch):
                release_publication.AuthenticatedUpdatePublisher(
                    generator=FakeGenerator(events, b"<rss />"),
                    origin=FakeOrigin(events),
                    github=FakeGitHubRelease(events),
                    changelog=root / "CHANGELOG.md",
                ).publish("v0.18.0", dmg, "0" * 64)

            self.assertEqual(events, [])

    def testPublishLeavesPreviousAppcastLiveWhenGenerationFails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            dmg = root / "FoldWise-Voice-0.18.0.dmg"
            dmg.write_bytes(b"stapled DMG bytes")
            digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
            events: list[str] = []

            with self.assertRaises(release_publication.PublicationError):
                release_publication.AuthenticatedUpdatePublisher(
                    generator=FailingGenerator(events),
                    origin=FakeOrigin(events, b"<rss>previous appcast</rss>"),
                    github=FakeGitHubRelease(events),
                    changelog=root / "CHANGELOG.md",
                ).publish("v0.18.0", dmg, digest)

            self.assertEqual(
                events,
                [
                    "check publication freeze",
                    "fetch appcast",
                    "generate appcast",
                ],
            )

    def testPublishRoutineStopsWhenIncidentFreezeIsLive(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            dmg = root / "FoldWise-Voice-0.18.0.dmg"
            dmg.write_bytes(b"stapled DMG bytes")
            digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
            events: list[str] = []

            with self.assertRaises(release_publication.PublicationError):
                release_publication.AuthenticatedUpdatePublisher(
                    generator=FakeGenerator(events, b"<rss />"),
                    origin=FakeOrigin(events, frozen=True),
                    github=FakeGitHubRelease(events),
                    changelog=root / "CHANGELOG.md",
                ).publish("v0.18.0", dmg, digest)

            self.assertEqual(events, ["check publication freeze"])

    def testPublishPreservesReleaseRecordBeforePublicMutation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact = root / "source" / "FoldWise-Voice-0.18.0.dmg"
            artifact.parent.mkdir()
            artifact.write_bytes(b"stapled DMG bytes")
            digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
            record_directory = root / "record"
            events: list[str] = []
            previous = b"<rss>last-known-good signed feed</rss>"
            published = b"<rss>new signed feed</rss>"
            github = FakeGitHubRelease(events)

            release_publication.AuthenticatedUpdatePublisher(
                generator=FakeGenerator(events, published),
                origin=FakeOrigin(events, previous),
                github=github,
                changelog=root / "CHANGELOG.md",
                record_directory=record_directory,
                source_commit="release-commit",
                source_run_id="12345",
            ).publish("v0.18.0", artifact, digest)

            self.assertEqual(
                (record_directory / artifact.name).read_bytes(),
                artifact.read_bytes(),
            )
            self.assertEqual(
                (record_directory / "appcast-before.xml").read_bytes(),
                previous,
            )
            self.assertEqual(
                (record_directory / "appcast-published.xml").read_bytes(),
                published,
            )
            record = json.loads(
                (record_directory / "publication.json").read_text(),
            )
            self.assertEqual(record["sha256"], digest)
            self.assertEqual(record["source_commit"], "release-commit")
            self.assertEqual(record["source_run_id"], "12345")
            self.assertIn("ed25519_private_key", record["recovery_paths"])
            staged_names = [asset.name for _, asset, _ in github.staged]
            self.assertEqual(
                staged_names,
                [
                    artifact.name,
                    "appcast-before.xml",
                    "appcast-published.xml",
                    "publication.json",
                ],
            )
            self.assertLess(
                events.index("generate appcast"),
                events.index("stage archive"),
            )


if __name__ == "__main__":
    unittest.main()
