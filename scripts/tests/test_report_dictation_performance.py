from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).parents[1] / "report_dictation_performance.py"
SPEC = importlib.util.spec_from_file_location(
    "report_dictation_performance",
    MODULE_PATH,
)
assert SPEC is not None
assert SPEC.loader is not None
report_dictation_performance = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = report_dictation_performance
SPEC.loader.exec_module(report_dictation_performance)


class DictationPerformanceReportTests(unittest.TestCase):
    def test_report_splits_voice_to_text_and_polish_percentiles(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            history = Path(temporary) / "history.jsonl"
            history.write_text(
                "\n".join(
                    [
                        json.dumps({"modeName": "legacy"}),
                        json.dumps(
                            self.entry(
                                total=100,
                                transcribe=40,
                                polish=None,
                            ),
                        ),
                        json.dumps(
                            self.entry(
                                total=300,
                                transcribe=80,
                                polish=180,
                            ),
                        ),
                    ],
                )
                + "\n",
                encoding="utf-8",
            )

            report = report_dictation_performance.build_report(history)

        self.assertEqual(report["measuredSessions"], 2)
        self.assertEqual(report["skippedSessions"], 1)
        self.assertEqual(
            report["groups"]["all"]["stages"]["total"]["statistics"],
            {
                "medianMilliseconds": 200.0,
                "p95Milliseconds": 300.0,
                "worstMilliseconds": 300.0,
            },
        )
        self.assertEqual(
            report["groups"]["voiceToText"]["stages"]["transcribe"][
                "samplesMilliseconds"
            ],
            [40.0],
        )
        self.assertEqual(
            report["groups"]["polish"]["stages"]["polish"][
                "samplesMilliseconds"
            ],
            [180.0],
        )

    @staticmethod
    def entry(
        *,
        total: float,
        transcribe: float,
        polish: float | None,
    ) -> dict[str, object]:
        timing = {
            "totalMilliseconds": total,
            "queuedMilliseconds": 2,
            "transcribeMilliseconds": transcribe,
            "polishMilliseconds": polish,
            "polishServerMilliseconds": 160 if polish is not None else None,
            "polishModelLoadMilliseconds": 80 if polish is not None else None,
            "polishPromptEvalMilliseconds": 20 if polish is not None else None,
            "polishGenerationMilliseconds": 100 if polish is not None else None,
            "insertMilliseconds": 52,
            "serialTailMilliseconds": 60,
        }
        return {
            # A custom mode may reuse the built-in display name; modeID is the
            # authoritative discriminator.
            "modeName": "Voice to Text",
            "modeID": "email-mode" if polish is not None else None,
            "timing": timing,
        }


if __name__ == "__main__":
    unittest.main()
