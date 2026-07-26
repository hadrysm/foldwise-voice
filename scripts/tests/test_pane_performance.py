from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).parents[1] / "run_pane_performance.py"
SPEC = importlib.util.spec_from_file_location("run_pane_performance", MODULE_PATH)
assert SPEC is not None
assert SPEC.loader is not None
run_pane_performance = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = run_pane_performance
SPEC.loader.exec_module(run_pane_performance)


class PanePerformanceHarnessTests(unittest.TestCase):
    def test_plan_uses_isolated_file_urls_and_full_route_list(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)

            plan = run_pane_performance.make_plan(
                profile="10000",
                output=root / "raw.json",
                data_directory=root / "profile",
                sample_count=20,
            )

        self.assertEqual(
            plan,
            {
                "profile": "10000",
                "outputURL": (root / "raw.json").resolve().as_uri(),
                "dataDirectory": (root / "profile").resolve().as_uri(),
                "sampleCount": 20,
                "destinations": [
                    "Home",
                    "Modes",
                    "Models",
                    "History",
                    "Stats",
                    "Settings",
                ],
            },
        )

    def test_measurementConfigurationDisablesDiagnosticSourcesOfOverhead(self) -> None:
        self.assertEqual(
            run_pane_performance.measurement_configuration(),
            {
                "buildConfiguration": "Release",
                "debugger": False,
                "codeCoverage": False,
                "screenshots": False,
                "sanitizers": False,
                "runtimeDiagnostics": False,
                "appNap": False,
                "windowVisibility": "foreground",
                "windowSizePoints": {"width": 980, "height": 720},
            },
        )

    def test_authority_requires_twenty_samples_and_hitch_evidence(self) -> None:
        self.assertEqual(
            [
                run_pane_performance.is_authoritative(20, True),
                run_pane_performance.is_authoritative(1, True),
                run_pane_performance.is_authoritative(20, False),
            ],
            [True, False, False],
        )

    def test_comparison_calculates_post_sparkle_deltas(self) -> None:
        runs = [
            self.run_result("empty", {"Stats": 160.0}),
            self.run_result(
                "10000",
                {"Home": 260.0, "History": 340.0, "Stats": 360.0},
            ),
        ]

        comparison = run_pane_performance.baseline_comparison(runs)

        self.assertEqual(
            comparison["profile10000"]["Home"],
            {
                "preSparkleMedianMilliseconds": 257.702,
                "postSparkleMedianMilliseconds": 260.0,
                "deltaMilliseconds": 2.298,
                "ratio": 1.008917,
            },
        )

    @staticmethod
    def run_result(
        profile: str,
        medians: dict[str, float],
    ) -> dict[str, object]:
        return {
            "profile": profile,
            "routes": [
                {
                    "destination": destination,
                    "visit": "cold",
                    "statistics": {"medianMilliseconds": median},
                }
                for destination, median in medians.items()
            ],
        }


if __name__ == "__main__":
    unittest.main()
