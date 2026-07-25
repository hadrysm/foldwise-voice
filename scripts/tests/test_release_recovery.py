from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).parents[1] / "release_recovery.py"
SPEC = importlib.util.spec_from_file_location("release_recovery", MODULE_PATH)
assert SPEC is not None
assert SPEC.loader is not None
release_recovery = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = release_recovery
SPEC.loader.exec_module(release_recovery)


class FakeRecoveryOrigin:
    def __init__(
        self,
        *,
        current_appcast: bytes,
        archive: bytes,
        last_good_appcast: bytes,
    ) -> None:
        self.current_appcast = current_appcast
        self.archive = archive
        self.last_good_appcast = last_good_appcast
        self.events: list[str] = []

    def fetch_appcast(self) -> bytes | None:
        self.events.append("fetch current appcast")
        return self.current_appcast

    def fetch_archive(self, filename: str) -> bytes | None:
        self.events.append(f"fetch archive {filename}")
        return self.archive

    def freeze_publication(
        self,
        request: release_recovery.WithdrawalRequest,
    ) -> None:
        self.events.append("freeze publication")

    def remove_archive(self, filename: str) -> None:
        self.events.append(f"remove archive {filename}")
        self.archive = b""

    def restore_appcast(self, appcast: Path) -> None:
        self.events.append("restore appcast")
        self.current_appcast = appcast.read_bytes()

    def purge_archive(self, filename: str) -> None:
        self.events.append(f"purge archive {filename}")

    def purge_appcast(self) -> None:
        self.events.append("purge appcast")

    def verify_archive_absent(self, filename: str) -> None:
        self.events.append(f"verify archive absent {filename}")
        if self.archive:
            raise release_recovery.RecoveryError("archive remains public")

    def verify_appcast(self, expected: bytes) -> None:
        self.events.append("verify restored appcast")
        if self.current_appcast != expected:
            raise release_recovery.RecoveryError("appcast mismatch")


class FakeInputRunner:
    def __init__(self) -> None:
        self.commands: list[list[str]] = []
        self.bodies: list[bytes] = []

    def run_input(self, command: list[str], value: str | None) -> None:
        self.commands.append(command)
        if "--body" in command:
            body = Path(command[command.index("--body") + 1])
            self.bodies.append(body.read_bytes())


class FakeFetcher:
    def __init__(self, responses: dict[str, list[bytes | None]]) -> None:
        self.responses = responses
        self.requests: list[str] = []

    def fetch(self, url: str) -> bytes | None:
        self.requests.append(url)
        return self.responses[url].pop(0)


class FakePurger:
    def __init__(self) -> None:
        self.requests: list[list[str]] = []

    def purge(self, urls: list[str]) -> None:
        self.requests.append(urls)


def feed(version: str, filename: str) -> bytes:
    return f"""<?xml version="1.0"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <sparkle:version>{version}</sparkle:version>
      <enclosure url="https://updates.guarcode.com/releases/{filename}" />
    </item>
  </channel>
</rss>
<!-- sparkle-signatures:
edSignature: signed-feed
length: 123
-->
""".encode()


class BadReleaseWithdrawalTests(unittest.TestCase):
    def testForwardRepairPlanNeedsNoCredentialsOrConfirmation(self) -> None:
        result = subprocess.run(
            [
                sys.executable,
                str(MODULE_PATH),
                "plan-forward-repair",
                "--bad-version",
                "0.18.0",
                "--repair-version",
                "0.18.1",
                "--validation-reference",
                "acceptance-run-123",
            ],
            check=True,
            text=True,
            capture_output=True,
            env={},
        )

        self.assertIn("DRY RUN", result.stdout)
        self.assertIn("PUBLISH FORWARD REPAIR 0.18.1", result.stdout)

    def testDryRunCliNeedsNoCredentialsAndPrintsPreparedUpdateWarning(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            snapshot = root / "appcast.xml"
            snapshot.write_bytes(
                feed("0.17.0", "FoldWise-Voice-0.17.0.dmg"),
            )

            result = subprocess.run(
                [
                    sys.executable,
                    str(MODULE_PATH),
                    "withdraw",
                    "--bad-version",
                    "0.18.0",
                    "--last-good-appcast",
                    str(snapshot),
                    "--evidence-directory",
                    str(root / "incident"),
                    "--source-commit",
                    "bad-commit",
                ],
                check=True,
                text=True,
                capture_output=True,
                env={},
            )

            self.assertIn("DRY RUN", result.stdout)
            self.assertIn("cannot be recalled", result.stdout)
            self.assertIn("Skip This Version", result.stdout)

    def testDryRunMakesNoProductionMutationsWithoutAuthorization(self) -> None:
        filename = "FoldWise-Voice-0.18.0.dmg"
        origin = FakeRecoveryOrigin(
            current_appcast=feed("0.18.0", filename),
            archive=b"bad release bytes",
            last_good_appcast=feed(
                "0.17.0",
                "FoldWise-Voice-0.17.0.dmg",
            ),
        )

        plan = release_recovery.BadReleaseWithdrawal(origin).withdraw(
            release_recovery.WithdrawalRequest(
                bad_version="0.18.0",
                bad_filename=filename,
                last_good_appcast=origin.last_good_appcast,
                evidence_directory=Path("unused"),
                source_commit="bad-commit",
                execute=False,
            )
        )

        self.assertEqual(origin.events, [])
        self.assertIn("freeze routine publication", "\n".join(plan))

    def testExecutePreservesEvidenceBeforeRemovingBadRelease(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            filename = "FoldWise-Voice-0.18.0.dmg"
            current = feed("0.18.0", filename)
            last_good = feed(
                "0.17.0",
                "FoldWise-Voice-0.17.0.dmg",
            )
            origin = FakeRecoveryOrigin(
                current_appcast=current,
                archive=b"bad release bytes",
                last_good_appcast=last_good,
            )
            evidence = Path(directory) / "incident"

            release_recovery.BadReleaseWithdrawal(origin).withdraw(
                release_recovery.WithdrawalRequest(
                    bad_version="0.18.0",
                    bad_filename=filename,
                    last_good_appcast=last_good,
                    evidence_directory=evidence,
                    source_commit="bad-commit",
                    execute=True,
                    credentials_present=True,
                    confirmation="WITHDRAW 0.18.0",
                )
            )

            self.assertLess(
                origin.events.index("freeze publication"),
                origin.events.index(f"remove archive {filename}"),
            )
            self.assertEqual((evidence / "withdrawn-appcast.xml").read_bytes(), current)
            self.assertEqual(
                (evidence / filename).read_bytes(),
                b"bad release bytes",
            )
            self.assertEqual(
                (evidence / "last-known-good-appcast.xml").read_bytes(),
                last_good,
            )
            manifest = json.loads((evidence / "incident.json").read_text())
            self.assertEqual(manifest["bad_version"], "0.18.0")
            self.assertEqual(manifest["source_commit"], "bad-commit")
            self.assertIn("ed25519_private_key", manifest["recovery_paths"])
            self.assertIn("developer_id_identity", manifest["recovery_paths"])
            self.assertEqual(origin.current_appcast, last_good)
            self.assertIn("verify restored appcast", origin.events)

    def testExecuteRequiresCredentialsAndExactConfirmation(self) -> None:
        filename = "FoldWise-Voice-0.18.0.dmg"
        origin = FakeRecoveryOrigin(
            current_appcast=feed("0.18.0", filename),
            archive=b"bad release bytes",
            last_good_appcast=feed(
                "0.17.0",
                "FoldWise-Voice-0.17.0.dmg",
            ),
        )
        requests = [
            release_recovery.WithdrawalRequest(
                bad_version="0.18.0",
                bad_filename=filename,
                last_good_appcast=origin.last_good_appcast,
                evidence_directory=Path("unused"),
                source_commit="bad-commit",
                execute=True,
                credentials_present=False,
                confirmation="WITHDRAW 0.18.0",
            ),
            release_recovery.WithdrawalRequest(
                bad_version="0.18.0",
                bad_filename=filename,
                last_good_appcast=origin.last_good_appcast,
                evidence_directory=Path("unused"),
                source_commit="bad-commit",
                execute=True,
                credentials_present=True,
                confirmation="yes",
            ),
        ]

        for request in requests:
            with self.subTest(request=request):
                with self.assertRaises(release_recovery.RecoveryError):
                    release_recovery.BadReleaseWithdrawal(origin).withdraw(request)

        self.assertEqual(origin.events, [])


class R2RecoveryOriginTests(unittest.TestCase):
    def testPurgeTargetsUseTheConfiguredPublicOrigin(self) -> None:
        purger = FakePurger()
        origin = release_recovery.R2RecoveryOrigin(
            FakeInputRunner(),
            fetcher=FakeFetcher({}),
            purger=purger,
            bucket="foldwise-updates",
            endpoint="https://account.r2.cloudflarestorage.com",
            public_base_url="https://staging-updates.example",
        )

        origin.purge_archive("FoldWise-Voice-0.18.0.dmg")
        origin.purge_appcast()

        self.assertEqual(
            purger.requests,
            [
                [
                    "https://staging-updates.example/"
                    "releases/FoldWise-Voice-0.18.0.dmg"
                ],
                ["https://staging-updates.example/appcast.xml"],
            ],
        )

    def testWithdrawalMutatesR2OnlyAfterEvidenceInputsAreReadable(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            filename = "FoldWise-Voice-0.18.0.dmg"
            appcast_url = "https://updates.guarcode.com/appcast.xml"
            archive_url = f"https://updates.guarcode.com/releases/{filename}"
            freeze_url = (
                "https://updates.guarcode.com/"
                "controls/publication-frozen.json"
            )
            current = feed("0.18.0", filename)
            last_good = feed(
                "0.17.0",
                "FoldWise-Voice-0.17.0.dmg",
            )
            runner = FakeInputRunner()
            purger = FakePurger()
            origin = release_recovery.R2RecoveryOrigin(
                runner,
                fetcher=FakeFetcher(
                    {
                        appcast_url: [current, last_good],
                        archive_url: [b"bad release bytes", None],
                        freeze_url: [b'{"frozen": true}\n'],
                    }
                ),
                purger=purger,
                bucket="foldwise-updates",
                endpoint="https://account.r2.cloudflarestorage.com",
            )

            release_recovery.BadReleaseWithdrawal(origin).withdraw(
                release_recovery.WithdrawalRequest(
                    bad_version="0.18.0",
                    bad_filename=filename,
                    last_good_appcast=last_good,
                    evidence_directory=Path(directory) / "incident",
                    source_commit="bad-commit",
                    execute=True,
                    credentials_present=True,
                    confirmation="WITHDRAW 0.18.0",
                )
            )

            operations = [
                command[command.index("s3api") + 1]
                for command in runner.commands
            ]
            self.assertEqual(
                operations,
                ["put-object", "delete-object", "put-object"],
            )
            freeze = json.loads(runner.bodies[0])
            self.assertEqual(freeze["bad_version"], "0.18.0")
            self.assertEqual(freeze["bad_filename"], filename)
            self.assertEqual(freeze["source_commit"], "bad-commit")
            self.assertEqual(
                purger.requests,
                [[freeze_url], [archive_url], [appcast_url]],
            )


if __name__ == "__main__":
    unittest.main()
