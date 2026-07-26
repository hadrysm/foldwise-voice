from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).parents[1] / "release_notarization.py"
SPEC = importlib.util.spec_from_file_location("release_notarization", MODULE_PATH)
assert SPEC is not None
assert SPEC.loader is not None
release_notarization = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = release_notarization
SPEC.loader.exec_module(release_notarization)


class FakeRunner:
    def __init__(
        self,
        responses: list[dict[str, object] | Exception],
    ) -> None:
        self.responses = responses
        self.commands: list[list[str]] = []
        self.events: list[str] = []

    def run_json(self, command: list[str]) -> dict[str, object]:
        self.commands.append(command)
        self.events.append(" ".join(command))
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response

    def run(self, command: list[str]) -> None:
        self.commands.append(command)
        self.events.append(" ".join(command))


class FakePublisher:
    def __init__(self, events: list[str]) -> None:
        self.events = events
        self.publications: list[tuple[str, Path, str]] = []

    def publish(self, tag: str, dmg: Path, sha256: str) -> None:
        self.events.append("publish")
        self.publications.append((tag, dmg, sha256))


class ReleaseNotarizationTests(unittest.TestCase):
    def write_record(self, root: Path) -> tuple[Path, Path]:
        dmg = root / "FoldWise-Voice-0.18.0.dmg"
        dmg.write_bytes(b"signed disk image")
        record = release_notarization.SubmissionRecord(
            tag="v0.18.0",
            filename=dmg.name,
            sha256=hashlib.sha256(dmg.read_bytes()).hexdigest(),
            source_run_id="123456",
            commit="a" * 40,
            submission_filename=("FoldWise-Voice-0.18.0-v0.18.0-run-123456.dmg"),
            submission_id="72b8fb3f-09c2-4d2e-aee3-7733498340a7",
        )
        record_path = root / "submission.json"
        record_path.write_text(json.dumps(record.to_json()))
        return dmg, record_path

    def testSubmitOnceRecordsArtifactAndSubmissionIdentity(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            dmg = root / "FoldWise-Voice-0.18.0.dmg"
            dmg.write_bytes(b"signed disk image")
            record_path = root / "submission.json"
            runner = FakeRunner(
                [
                    {
                        "id": "72b8fb3f-09c2-4d2e-aee3-7733498340a7",
                        "status": "Uploaded",
                    },
                ]
            )
            transaction = release_notarization.ReleaseNotarization(runner)

            record = transaction.submit_once(
                dmg=dmg,
                record_path=record_path,
                tag="v0.18.0",
                source_run_id="123456",
                commit="a" * 40,
            )

            self.assertEqual(
                record,
                release_notarization.SubmissionRecord(
                    tag="v0.18.0",
                    filename="FoldWise-Voice-0.18.0.dmg",
                    sha256=hashlib.sha256(b"signed disk image").hexdigest(),
                    source_run_id="123456",
                    commit="a" * 40,
                    submission_filename=(
                        "FoldWise-Voice-0.18.0-v0.18.0-run-123456.dmg"
                    ),
                    submission_id="72b8fb3f-09c2-4d2e-aee3-7733498340a7",
                ),
            )
            self.assertEqual(
                json.loads(record_path.read_text()),
                record.to_json(),
            )
            self.assertIn("submit", runner.commands[0])
            self.assertNotIn("--wait", runner.commands[0])

    def testSubmitOnceReusesRecordedSubmissionWithoutSubmittingAgain(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            dmg = root / "FoldWise-Voice-0.18.0.dmg"
            dmg.write_bytes(b"signed disk image")
            record_path = root / "submission.json"
            runner = FakeRunner(
                [
                    {
                        "id": "72b8fb3f-09c2-4d2e-aee3-7733498340a7",
                        "status": "Uploaded",
                    },
                ]
            )
            transaction = release_notarization.ReleaseNotarization(runner)
            expected = transaction.submit_once(
                dmg=dmg,
                record_path=record_path,
                tag="v0.18.0",
                source_run_id="123456",
                commit="a" * 40,
            )
            command_count = len(runner.commands)

            reused = transaction.submit_once(
                dmg=dmg,
                record_path=record_path,
                tag="v0.18.0",
                source_run_id="123456",
                commit="a" * 40,
            )

            self.assertEqual(reused, expected)
            self.assertEqual(len(runner.commands), command_count)

    def testAmbiguousSubmitReconcilesOneHistoryMatch(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            dmg = root / "FoldWise-Voice-0.18.0.dmg"
            dmg.write_bytes(b"signed disk image")
            runner = FakeRunner(
                [
                    release_notarization.CommandFailed("connection dropped"),
                    {
                        "history": [
                            {
                                "id": "72b8fb3f-09c2-4d2e-aee3-7733498340a7",
                                "name": (
                                    "FoldWise-Voice-0.18.0-v0.18.0-run-123456.dmg"
                                ),
                                "status": "In Progress",
                            },
                        ],
                    },
                ]
            )

            record = release_notarization.ReleaseNotarization(
                runner,
            ).submit_once(
                dmg=dmg,
                record_path=root / "submission.json",
                tag="v0.18.0",
                source_run_id="123456",
                commit="a" * 40,
            )

            self.assertEqual(
                record.submission_id,
                "72b8fb3f-09c2-4d2e-aee3-7733498340a7",
            )
            self.assertIn("history", runner.commands[1])
            self.assertEqual(
                sum("submit" in command for command in runner.commands),
                1,
            )

    def testAmbiguousSubmitRequiresReviewWhenHistoryHasNoMatch(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            dmg = root / "FoldWise-Voice-0.18.0.dmg"
            dmg.write_bytes(b"signed disk image")
            runner = FakeRunner(
                [
                    release_notarization.CommandFailed("connection dropped"),
                    {"history": []},
                ]
            )

            with self.assertRaises(
                release_notarization.OperatorReviewRequired,
            ):
                release_notarization.ReleaseNotarization(
                    runner,
                ).submit_once(
                    dmg=dmg,
                    record_path=root / "submission.json",
                    tag="v0.18.0",
                    source_run_id="123456",
                    commit="a" * 40,
                )

            self.assertEqual(
                sum("submit" in command for command in runner.commands),
                1,
            )

    def testAmbiguousSubmitRetriesReadOnlyHistoryCall(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            dmg = root / "FoldWise-Voice-0.18.0.dmg"
            dmg.write_bytes(b"signed disk image")
            submission_name = "FoldWise-Voice-0.18.0-v0.18.0-run-123456.dmg"
            runner = FakeRunner(
                [
                    release_notarization.CommandFailed("connection dropped"),
                    release_notarization.CommandFailed("history unavailable"),
                    {
                        "history": [
                            {
                                "id": "72b8fb3f-09c2-4d2e-aee3-7733498340a7",
                                "name": submission_name,
                            },
                        ],
                    },
                ]
            )

            release_notarization.ReleaseNotarization(
                runner,
                sleeper=lambda _: None,
            ).submit_once(
                dmg=dmg,
                record_path=root / "submission.json",
                tag="v0.18.0",
                source_run_id="123456",
                commit="a" * 40,
            )

            self.assertEqual(
                sum("history" in command for command in runner.commands),
                2,
            )

    def testPendingRecordNeverResubmitsWhenHistoryHasMultipleMatches(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            dmg = root / "FoldWise-Voice-0.18.0.dmg"
            dmg.write_bytes(b"signed disk image")
            record_path = root / "submission.json"
            digest = hashlib.sha256(b"signed disk image").hexdigest()
            pending = release_notarization.SubmissionRecord(
                tag="v0.18.0",
                filename=dmg.name,
                sha256=digest,
                source_run_id="123456",
                commit="a" * 40,
                submission_filename=("FoldWise-Voice-0.18.0-v0.18.0-run-123456.dmg"),
                submission_id=None,
            )
            record_path.write_text(json.dumps(pending.to_json()))
            runner = FakeRunner(
                [
                    {
                        "history": [
                            {"id": "first", "name": pending.submission_filename},
                            {"id": "second", "name": pending.submission_filename},
                        ],
                    },
                ]
            )

            with self.assertRaises(
                release_notarization.OperatorReviewRequired,
            ):
                release_notarization.ReleaseNotarization(
                    runner,
                ).submit_once(
                    dmg=dmg,
                    record_path=record_path,
                    tag="v0.18.0",
                    source_run_id="123456",
                    commit="a" * 40,
                )

            self.assertNotIn("submit", runner.commands[0])

    def testFinalizePublishesOnlyAfterAcceptedStapledAndVerified(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            dmg, record_path = self.write_record(root)
            runner = FakeRunner([{"status": "Accepted"}])
            publisher = FakePublisher(runner.events)

            release_notarization.ReleaseNotarization(
                runner,
            ).finalize(
                dmg=dmg,
                record_path=record_path,
                log_path=root / "notarization-log.json",
                publisher=publisher,
            )

            self.assertEqual(len(publisher.publications), 1)
            self.assertEqual(publisher.publications[0][0], "v0.18.0")
            self.assertEqual(
                publisher.publications[0][2],
                hashlib.sha256(dmg.read_bytes()).hexdigest(),
            )
            self.assertEqual(runner.events[-1], "publish")
            self.assertTrue(
                any("notarytool wait" in event for event in runner.events),
            )
            self.assertTrue(
                any("stapler staple" in event for event in runner.events),
            )
            self.assertTrue(
                any("stapler validate" in event for event in runner.events),
            )
            self.assertTrue(
                any("codesign --verify" in event for event in runner.events),
            )
            self.assertTrue(
                any("spctl -a" in event for event in runner.events),
            )

    def testFinalizeTreatsInProgressAsRecoverableWithoutPublishing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            dmg, record_path = self.write_record(root)
            runner = FakeRunner(
                [
                    release_notarization.CommandFailed("timeout"),
                    release_notarization.CommandFailed("timeout"),
                    release_notarization.CommandFailed("timeout"),
                    {"status": "In Progress"},
                ]
            )
            publisher = FakePublisher(runner.events)

            with self.assertRaises(release_notarization.RecoverableTimeout):
                release_notarization.ReleaseNotarization(
                    runner,
                    sleeper=lambda _: None,
                ).finalize(
                    dmg=dmg,
                    record_path=record_path,
                    log_path=root / "notarization-log.json",
                    publisher=publisher,
                )

            self.assertEqual(len(publisher.publications), 0)
            self.assertEqual(
                sum("notarytool wait" in event for event in runner.events),
                3,
            )
            self.assertEqual(
                sum("notarytool submit" in event for event in runner.events),
                0,
            )

    def testFinalizeRetainsRejectedSubmissionLogWithoutPublishing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            dmg, record_path = self.write_record(root)
            log_path = root / "notarization-log.json"
            runner = FakeRunner([{"status": "Rejected"}])
            publisher = FakePublisher(runner.events)

            with self.assertRaises(
                release_notarization.TerminalSubmissionFailure,
            ):
                release_notarization.ReleaseNotarization(
                    runner,
                ).finalize(
                    dmg=dmg,
                    record_path=record_path,
                    log_path=log_path,
                    publisher=publisher,
                )

            self.assertEqual(len(publisher.publications), 0)
            self.assertTrue(
                any("notarytool log" in event for event in runner.events),
            )
            self.assertFalse(
                any("stapler staple" in event for event in runner.events),
            )

    def testFinalizeRejectsChangedPreservedBytesBeforeWaiting(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            dmg, record_path = self.write_record(root)
            dmg.write_bytes(b"different disk image")
            runner = FakeRunner([])

            with self.assertRaises(release_notarization.ArtifactMismatch):
                release_notarization.ReleaseNotarization(
                    runner,
                ).finalize(
                    dmg=dmg,
                    record_path=record_path,
                    log_path=root / "notarization-log.json",
                    publisher=FakePublisher(runner.events),
                )

            self.assertEqual(runner.commands, [])

    def testPublisherReusesMatchingServerAssetThenPublishesDraft(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            dmg = Path(directory) / "FoldWise-Voice-0.18.0.dmg"
            dmg.write_bytes(b"stapled disk image")
            digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
            runner = FakeRunner(
                [
                    {
                        "isDraft": True,
                        "assets": [
                            {
                                "name": dmg.name,
                                "digest": f"sha256:{digest}",
                            },
                        ],
                    },
                    {
                        "isDraft": True,
                        "assets": [
                            {
                                "name": dmg.name,
                                "digest": f"sha256:{digest}",
                            },
                        ],
                    },
                ]
            )

            release_notarization.GitHubReleasePublisher(
                runner,
                repository="hadrysm/foldwise-voice",
            ).publish("v0.18.0", dmg, digest)

            self.assertFalse(
                any("release upload" in event for event in runner.events),
            )
            self.assertTrue(
                any("release edit" in event for event in runner.events),
            )
            self.assertNotIn("--clobber", " ".join(runner.events))

    def testPublisherFindsDraftReleaseThroughReleaseView(self) -> None:
        runner = FakeRunner([{"isDraft": True, "assets": []}])

        release_notarization.GitHubReleasePublisher(
            runner,
            repository="hadrysm/foldwise-voice",
        ).publish_draft("v0.18.0")

        self.assertEqual(
            runner.commands,
            [
                [
                    "gh",
                    "release",
                    "view",
                    "v0.18.0",
                    "--repo",
                    "hadrysm/foldwise-voice",
                    "--json",
                    "isDraft,assets",
                ],
                [
                    "gh",
                    "release",
                    "edit",
                    "v0.18.0",
                    "--repo",
                    "hadrysm/foldwise-voice",
                    "--draft=false",
                ],
            ],
        )

    def testPublisherRejectsReleaseResponseWithoutDraftState(self) -> None:
        runner = FakeRunner([{"assets": []}])

        with self.assertRaises(release_notarization.CommandFailed):
            release_notarization.GitHubReleasePublisher(
                runner,
                repository="hadrysm/foldwise-voice",
            ).publish_draft("v0.18.0")

        self.assertEqual(len(runner.commands), 1)

    def testPublisherStopsWhenExistingServerAssetDigestDiffers(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            dmg = Path(directory) / "FoldWise-Voice-0.18.0.dmg"
            dmg.write_bytes(b"stapled disk image")
            digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
            runner = FakeRunner(
                [
                    {
                        "isDraft": True,
                        "assets": [
                            {
                                "name": dmg.name,
                                "digest": f"sha256:{'b' * 64}",
                            },
                        ],
                    },
                ]
            )

            with self.assertRaises(release_notarization.ArtifactMismatch):
                release_notarization.GitHubReleasePublisher(
                    runner,
                    repository="hadrysm/foldwise-voice",
                ).publish("v0.18.0", dmg, digest)

            self.assertEqual(len(runner.commands), 1)

    def testPublisherVerifiesNewAssetServerDigestBeforePublishing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            dmg = Path(directory) / "FoldWise-Voice-0.18.0.dmg"
            dmg.write_bytes(b"stapled disk image")
            digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
            runner = FakeRunner(
                [
                    {"isDraft": True, "assets": []},
                    {
                        "isDraft": True,
                        "assets": [
                            {
                                "name": dmg.name,
                                "digest": f"sha256:{digest}",
                            },
                        ],
                    },
                    {
                        "isDraft": True,
                        "assets": [
                            {
                                "name": dmg.name,
                                "digest": f"sha256:{digest}",
                            },
                        ],
                    },
                ]
            )

            release_notarization.GitHubReleasePublisher(
                runner,
                repository="hadrysm/foldwise-voice",
            ).publish("v0.18.0", dmg, digest)

            upload_index = next(
                index
                for index, event in enumerate(runner.events)
                if "release upload" in event
            )
            publish_index = next(
                index
                for index, event in enumerate(runner.events)
                if "release edit" in event
            )
            self.assertLess(upload_index, publish_index)
            self.assertNotIn("--clobber", runner.events[upload_index])

    def testPublisherLeavesDraftWhenUploadedServerDigestDiffers(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            dmg = Path(directory) / "FoldWise-Voice-0.18.0.dmg"
            dmg.write_bytes(b"stapled disk image")
            digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
            runner = FakeRunner(
                [
                    {"isDraft": True, "assets": []},
                    {
                        "isDraft": True,
                        "assets": [
                            {
                                "name": dmg.name,
                                "digest": f"sha256:{'b' * 64}",
                            },
                        ],
                    },
                ]
            )

            with self.assertRaises(release_notarization.ArtifactMismatch):
                release_notarization.GitHubReleasePublisher(
                    runner,
                    repository="hadrysm/foldwise-voice",
                ).publish("v0.18.0", dmg, digest)

            self.assertFalse(
                any("release edit" in event for event in runner.events),
            )


if __name__ == "__main__":
    unittest.main()
