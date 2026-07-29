from __future__ import annotations

import importlib.util
import json
import sys
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).parents[1] / "run_streaming_latency.py"
SPEC = importlib.util.spec_from_file_location("run_streaming_latency", MODULE_PATH)
assert SPEC is not None
assert SPEC.loader is not None
run_streaming_latency = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = run_streaming_latency
SPEC.loader.exec_module(run_streaming_latency)


def model_run(
    *,
    asr_model: str = "parakeet-eou-320",
    short_sha: str = "short-hash",
) -> dict[str, object]:
    return {
        "asrModel": asr_model,
        "effectiveASRModel": asr_model,
        "polishModel": "qwen2.5:3b",
        "insertion": "stubbed plus the separately measured Accessibility constant",
        "insertConstantMilliseconds": 62.5,
        "residency": {
            "peakFootprintBytes": 900_000_000,
            "maximumResidentBytes": 1_100_000_000,
            "residentASREngineCount": 1,
        },
        "fixtures": [
            {
                "length": "short",
                "sha256": short_sha,
                "durationSeconds": 5.1,
                "speechOnsetSeconds": 0.2,
                "observedRawTranscripts": ["hello there"],
            },
            {
                "length": "long",
                "sha256": "long-hash",
                "durationSeconds": 17.2,
                "speechOnsetSeconds": 0.3,
                "observedRawTranscripts": ["hello there again"],
            },
        ],
        "classes": [],
    }


class StreamingLatencyPlanTests(unittest.TestCase):
    def test_planPinsOneStreamingModelItsFixturesAndTheInsertConstant(self) -> None:
        root = Path("/tmp/foldwise-streaming-latency-plan")

        plan = run_streaming_latency.make_plan(
            asr_model="nemotron-560",
            polish_model="qwen2.5:3b",
            samples=20,
            insert_constant_milliseconds=62.5,
            output=root / "result.json",
            short_audio=root / "short.wav",
            long_audio=root / "long.wav",
        )

        self.assertEqual(
            plan,
            {
                "schemaVersion": 1,
                "asrModel": "nemotron-560",
                "polishModel": "qwen2.5:3b",
                "sampleCount": 20,
                "insertConstantMilliseconds": 62.5,
                "outputURL": (root / "result.json").resolve().as_uri(),
                "fixtures": [
                    {
                        "length": "short",
                        "audioURL": (root / "short.wav").resolve().as_uri(),
                    },
                    {
                        "length": "long",
                        "audioURL": (root / "long.wav").resolve().as_uri(),
                    },
                ],
            },
        )


class StreamingLatencyAuthorityTests(unittest.TestCase):
    def test_twentySamplesOnBothModelsOnTheReferenceMacIsAuthoritative(self) -> None:
        violations = run_streaming_latency.authority_violations(
            samples=20,
            models=["parakeet-eou-320", "nemotron-560"],
            reference_mac="foldwise-streaming-reference",
            polish_model="qwen2.5:3b",
        )

        self.assertEqual(violations, [])

    def test_aSmokeSampleCountIsNotAuthoritative(self) -> None:
        violations = run_streaming_latency.authority_violations(
            samples=1,
            models=["parakeet-eou-320", "nemotron-560"],
            reference_mac="foldwise-streaming-reference",
            polish_model="qwen2.5:3b",
        )

        self.assertEqual(violations, ["recorded samples per class must equal 20"])

    def test_measuringOneModelIsNotAuthoritative(self) -> None:
        violations = run_streaming_latency.authority_violations(
            samples=20,
            models=["parakeet-eou-320"],
            reference_mac="foldwise-streaming-reference",
            polish_model="qwen2.5:3b",
        )

        self.assertEqual(
            violations,
            [
                "both shipped Streaming ASR models must be measured: "
                "parakeet-eou-320, nemotron-560"
            ],
        )

    def test_aNonReferenceMacIsNotAuthoritative(self) -> None:
        violations = run_streaming_latency.authority_violations(
            samples=20,
            models=["parakeet-eou-320", "nemotron-560"],
            reference_mac="my-laptop",
            polish_model="qwen2.5:3b",
        )

        self.assertEqual(
            violations, ["reference Mac must be foldwise-streaming-reference"]
        )


class StreamingLatencyMergeTests(unittest.TestCase):
    def test_mergeProducesOneGateReportPerRunModel(self) -> None:
        report = self.merge([model_run(), model_run(asr_model="nemotron-560")])

        self.assertEqual(
            [model["asrModel"] for model in report["models"]],
            ["parakeet-eou-320", "nemotron-560"],
        )

    def test_mergeKeepsTheSharedFixtureIdentityWithoutTranscripts(self) -> None:
        report = self.merge([model_run()])

        self.assertEqual(
            report["fixtures"],
            [
                {
                    "length": "short",
                    "sha256": "short-hash",
                    "durationSeconds": 5.1,
                    "speechOnsetSeconds": 0.2,
                },
                {
                    "length": "long",
                    "sha256": "long-hash",
                    "durationSeconds": 17.2,
                    "speechOnsetSeconds": 0.3,
                },
            ],
        )

    def test_modelsThatMeasuredDifferentFixturesAreNotOneMatrix(self) -> None:
        report = self.merge(
            [
                model_run(),
                model_run(asr_model="nemotron-560", short_sha="a-different-recording"),
            ]
        )

        self.assertEqual(
            (report["authoritative"], report["authorityViolations"]),
            (
                False,
                [
                    "nemotron-560 measured different fixtures from parakeet-eou-320"
                ],
            ),
        )

    def test_anUnreviewedMemoryCeilingIsRecordedAsUnreviewed(self) -> None:
        report = self.merge([model_run()], memory_ceiling_reviewed=False)

        self.assertFalse(report["memoryCeiling"]["humanReviewed"])

    def test_launcherViolationsMakeTheRunNonAuthoritative(self) -> None:
        report = self.merge([model_run()], violations=["reference Mac must be x"])

        self.assertFalse(report["authoritative"])

    def merge(
        self,
        runs: list[dict[str, object]],
        *,
        memory_ceiling_reviewed: bool = True,
        violations: list[str] | None = None,
    ) -> dict[str, object]:
        return run_streaming_latency.merge_reports(
            runs,
            samples=20,
            environment={"referenceMac": "foldwise-streaming-reference"},
            standalone_maximum_resident_bytes=1_227_000_000,
            memory_ceiling_reviewed=memory_ceiling_reviewed,
            authoritative=True,
            violations=list(violations or []),
        )


class StreamingLatencyBaselineTests(unittest.TestCase):
    def test_theShippedBaselineNamesTheReferenceMacAndTheDocumentedCeiling(self) -> None:
        baseline = json.loads(
            (run_streaming_latency.DEFAULT_BASELINES).read_text()
        )

        self.assertEqual(
            (
                baseline["schemaVersion"],
                baseline["referenceMac"],
                baseline["standaloneMaximumResidentBytes"],
            ),
            (1, "foldwise-streaming-reference", 1_227_000_000),
        )


if __name__ == "__main__":
    unittest.main()
