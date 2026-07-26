import unittest

from scripts.update_runtime_acceptance import (
    BundleIdentity,
    RuntimeEvidence,
)


class RuntimeEvidenceTests(unittest.TestCase):
    def test_complete_safe_relaunch_satisfies_runtime_contract(self) -> None:
        evidence = RuntimeEvidence(
            source=BundleIdentity(
                path="/tmp/Applications/FoldWise Voice.app",
                bundle_identifier="com.foldwise.voice.native",
                team_identifier="6849P798YW",
                version="9000",
            ),
            target=BundleIdentity(
                path="/tmp/target/FoldWise Voice.app",
                bundle_identifier="com.foldwise.voice.native",
                team_identifier="6849P798YW",
                version="9001",
            ),
            installed_path="/tmp/Applications/FoldWise Voice.app",
            deferred_process_alive=True,
            deferred_installed_version="9000",
            relaunched_installed_version="9001",
            events=[
                {"event": "source-ready", "version": "9000"},
                {"event": "dictation-started", "version": "9000"},
                {"event": "update-prepared", "version": "9000"},
                {"event": "termination-deferred", "version": "9000"},
                {
                    "event": "dictation-finished",
                    "version": "9000",
                    "installedVersionAtCompletion": "9000",
                },
                {
                    "event": "target-started",
                    "version": "9001",
                    "bundlePath": "/tmp/Applications/FoldWise Voice.app",
                },
                {
                    "event": "target-ready",
                    "version": "9001",
                    "bundlePath": "/tmp/Applications/FoldWise Voice.app",
                    "badgeVisible": True,
                    "hotkeyHealth": "global",
                },
            ],
        )

        self.assertEqual(evidence.violations(), [])

    def test_replacement_before_dictation_completion_is_reported(self) -> None:
        evidence = complete_evidence(
            deferred_process_alive=False,
            deferred_installed_version="9001",
        )

        self.assertEqual(
            evidence.violations(),
            [
                "source process terminated while Dictation was active",
                "installed version changed before Dictation finished: expected 9000, got 9001",
            ],
        )

    def test_identity_transition_requires_production_bundle_and_team(self) -> None:
        evidence = complete_evidence(
            target=BundleIdentity(
                path="/tmp/target/FoldWise Voice.app",
                bundle_identifier="com.example.changed",
                team_identifier="OTHERTEAM",
                version="9001",
            )
        )

        self.assertEqual(
            evidence.violations(),
            [
                "target bundle identifier changed: expected com.foldwise.voice.native, "
                "got com.example.changed",
                "target Team identifier changed: expected 6849P798YW, got OTHERTEAM",
            ],
        )

    def test_target_readiness_requires_badge_and_global_hotkey(self) -> None:
        events = complete_events()
        events[-1] = {
            "event": "target-ready",
            "version": "9001",
            "bundlePath": "/tmp/Applications/FoldWise Voice.app",
            "badgeVisible": False,
            "hotkeyHealth": "focusedAppOnly",
        }
        evidence = complete_evidence(events=events)

        self.assertEqual(
            evidence.violations(),
            [
                "relaunch readiness was emitted before the Badge was visible",
                "relaunch readiness was emitted before global hotkey registration",
            ],
        )

    def test_target_version_must_be_newer_than_source(self) -> None:
        events = complete_events()
        events[-1]["version"] = "9000"
        evidence = complete_evidence(
            target=BundleIdentity(
                path="/tmp/target/FoldWise Voice.app",
                bundle_identifier="com.foldwise.voice.native",
                team_identifier="6849P798YW",
                version="9000",
            ),
            relaunched_installed_version="9000",
            events=events,
        )

        self.assertEqual(
            evidence.violations(),
            ["target version is not newer than source: 9000 -> 9000"],
        )

    def test_completion_boundary_rejects_early_replacement(self) -> None:
        events = complete_events()
        events[4]["installedVersionAtCompletion"] = "9001"
        evidence = complete_evidence(events=events)

        self.assertEqual(
            evidence.violations(),
            [
                "installed version changed before Dictation finished: "
                "expected 9000, got 9001"
            ],
        )


def complete_events() -> list[dict[str, object]]:
    return [
        {"event": "source-ready", "version": "9000"},
        {"event": "dictation-started", "version": "9000"},
        {"event": "update-prepared", "version": "9000"},
        {"event": "termination-deferred", "version": "9000"},
        {
            "event": "dictation-finished",
            "version": "9000",
            "installedVersionAtCompletion": "9000",
        },
        {
            "event": "target-started",
            "version": "9001",
            "bundlePath": "/tmp/Applications/FoldWise Voice.app",
        },
        {
            "event": "target-ready",
            "version": "9001",
            "bundlePath": "/tmp/Applications/FoldWise Voice.app",
            "badgeVisible": True,
            "hotkeyHealth": "global",
        },
    ]


def complete_evidence(**changes: object) -> RuntimeEvidence:
    values: dict[str, object] = {
        "source": BundleIdentity(
            path="/tmp/Applications/FoldWise Voice.app",
            bundle_identifier="com.foldwise.voice.native",
            team_identifier="6849P798YW",
            version="9000",
        ),
        "target": BundleIdentity(
            path="/tmp/target/FoldWise Voice.app",
            bundle_identifier="com.foldwise.voice.native",
            team_identifier="6849P798YW",
            version="9001",
        ),
        "installed_path": "/tmp/Applications/FoldWise Voice.app",
        "deferred_process_alive": True,
        "deferred_installed_version": "9000",
        "relaunched_installed_version": "9001",
        "events": complete_events(),
    }
    values.update(changes)
    return RuntimeEvidence(**values)


if __name__ == "__main__":
    unittest.main()
