from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).parents[1] / "run_dictation_baseline.py"
SPEC = importlib.util.spec_from_file_location("run_dictation_baseline", MODULE_PATH)
assert SPEC is not None
assert SPEC.loader is not None
run_dictation_baseline = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = run_dictation_baseline
SPEC.loader.exec_module(run_dictation_baseline)


class DictationBaselineRunnerTests(unittest.TestCase):
    def test_planPinsModelsFixturesAndSampleCount(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            short = root / "short.wav"
            long = root / "long.wav"
            output = root / "result.json"

            plan = run_dictation_baseline.make_plan(
                short_audio=short,
                short_transcript=(
                    "To jest krótka próbka mająca więcej niż czterdzieści znaków."
                ),
                long_audio=long,
                long_transcript=(
                    "To jest dłuższa próbka mająca zdecydowanie więcej niż "
                    "czterdzieści znaków."
                ),
                output=output,
                samples=20,
                asr_model="whisper-small",
                polish_model="qwen2.5:3b",
            )

        self.assertEqual(
            plan,
            {
                "schemaVersion": 1,
                "asrModel": "whisper-small",
                "polishModel": "qwen2.5:3b",
                "sampleCount": 20,
                "outputURL": output.resolve().as_uri(),
                "fixtures": [
                    {
                        "length": "short",
                        "audioURL": short.resolve().as_uri(),
                        "expectedTranscript": (
                            "To jest krótka próbka mająca więcej niż "
                            "czterdzieści znaków."
                        ),
                    },
                    {
                        "length": "long",
                        "audioURL": long.resolve().as_uri(),
                        "expectedTranscript": (
                            "To jest dłuższa próbka mająca zdecydowanie więcej niż "
                            "czterdzieści znaków."
                        ),
                    },
                ],
            },
        )

    def test_authoritativeContractRequiresExactTicketMatrix(self) -> None:
        fixtures = [
            {
                "durationSeconds": 5.2,
                "expectedTranscript": (
                    "Jutro o ósmej wyślę do Ani krótki opis naszej rozmowy."
                ),
            },
            {
                "durationSeconds": 16.8,
                "expectedTranscript": (
                    "Jutro o ósmej wyślę do Ani opis naszej rozmowy, a potem dam "
                    "listę ustaleń, ważne daty, role, plan na ten tydzień i trzy "
                    "cele dla nas na każdy dzień rano."
                ),
            },
        ]

        self.assertEqual(
            [
                run_dictation_baseline.authority_violations(
                    samples=20,
                    asr_model="whisper-small",
                    polish_model="qwen2.5:3b",
                    fixtures=fixtures,
                ),
                run_dictation_baseline.authority_violations(
                    samples=1,
                    asr_model="whisper-small",
                    polish_model="qwen2.5:3b",
                    fixtures=fixtures,
                ),
                run_dictation_baseline.authority_violations(
                    samples=20,
                    asr_model="parakeet-v3",
                    polish_model="llama3.2:1b",
                    fixtures=fixtures,
                ),
                run_dictation_baseline.authority_violations(
                    samples=20,
                    asr_model="whisper-small",
                    polish_model="qwen2.5:3b",
                    fixtures=[
                        {
                            "durationSeconds": 2.0,
                            "expectedTranscript": "Zbyt krótko.",
                        },
                        fixtures[1],
                    ],
                ),
            ],
            [
                [],
                ["recorded samples per class must equal 20"],
                [
                    "ASR model must equal whisper-small",
                    "Polish model must equal qwen2.5:3b",
                ],
                [
                    "Short duration must be 4–7 seconds",
                    "Short transcript must be 45–70 characters",
                    "Short transcript must be 8–12 words",
                ],
            ],
        )

    def testClearPreviousRunPreventsStaleReportReuse(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "dictation-baseline-report.json"
            failure = output.with_suffix(".failure.txt")
            output.write_text("stale report")
            failure.write_text("stale failure")

            run_dictation_baseline.clear_previous_run(output)

            self.assertEqual([output.exists(), failure.exists()], [False, False])


if __name__ == "__main__":
    unittest.main()
