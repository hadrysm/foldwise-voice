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
                "windowActivation": "nonactivating",
                "windowSizePoints": {"width": 980, "height": 720},
            },
        )

    def test_authority_requires_every_gate_to_pass(self) -> None:
        self.assertEqual(
            [
                run_pane_performance.is_authoritative(20, True, True, True),
                run_pane_performance.is_authoritative(1, True, True, True),
                run_pane_performance.is_authoritative(20, False, True, True),
                run_pane_performance.is_authoritative(20, True, False, True),
                run_pane_performance.is_authoritative(20, True, True, False),
            ],
            [True, False, False, False, False],
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

    def test_duration_gate_rejects_any_sample_over_absolute_cap(self) -> None:
        runs = [
            {
                "profile": "empty",
                "routes": [
                    {
                        "destination": "Home",
                        "visit": "cold",
                        "samplesMilliseconds": [35.0, 100.001, 42.0],
                        "statistics": {"medianMilliseconds": 42.0},
                    },
                ],
            },
        ]

        result = run_pane_performance.evaluate_duration_gate(
            runs,
            baselines={},
        )

        self.assertEqual(result["passed"], False)
        self.assertEqual(
            result["absoluteViolations"],
            [
                {
                    "profile": "empty",
                    "destination": "Home",
                    "visit": "cold",
                    "sampleIndex": 2,
                    "milliseconds": 100.001,
                    "limitMilliseconds": 100.0,
                },
            ],
        )

    def test_duration_gate_rejects_more_than_twenty_percent_regression(self) -> None:
        runs = [
            {
                "profile": "10000",
                "routes": [
                    {
                        "destination": "History",
                        "visit": "warm",
                        "samplesMilliseconds": [47.0, 48.001, 49.0],
                        "statistics": {"medianMilliseconds": 48.001},
                    },
                ],
            },
        ]
        baselines = {
            "maximumRegressionPercent": 20.0,
            "routes": {
                "10000/History/warm": {"medianMilliseconds": 40.0},
            },
        }

        result = run_pane_performance.evaluate_duration_gate(runs, baselines)

        self.assertEqual(result["passed"], False)
        self.assertEqual(
            result["baselineViolations"],
            [
                {
                    "profile": "10000",
                    "destination": "History",
                    "visit": "warm",
                    "medianMilliseconds": 48.001,
                    "baselineMedianMilliseconds": 40.0,
                    "limitMilliseconds": 48.0,
                    "maximumRegressionPercent": 20.0,
                },
            ],
        )

    def test_duration_gate_rejects_route_without_an_accepted_baseline(self) -> None:
        runs = [
            {
                "profile": "empty",
                "routes": [
                    {
                        "destination": "Models",
                        "visit": "cold",
                        "samplesMilliseconds": [40.0],
                        "statistics": {"medianMilliseconds": 40.0},
                    },
                ],
            },
        ]

        result = run_pane_performance.evaluate_duration_gate(
            runs,
            baselines={"maximumRegressionPercent": 20.0, "routes": {}},
        )

        self.assertEqual(
            result["missingBaselines"],
            ["empty/Models/cold"],
        )

    def test_matrix_gate_requires_every_profile_pane_visit_class(self) -> None:
        result = run_pane_performance.evaluate_matrix_gate(
            runs=[],
            expected_sample_count=20,
        )

        self.assertEqual(
            result["missingRoutes"],
            [
                "empty/Home/cold",
                "empty/Home/warm",
                "empty/Modes/cold",
                "empty/Modes/warm",
                "empty/Models/cold",
                "empty/Models/warm",
                "empty/History/cold",
                "empty/History/warm",
                "empty/Stats/cold",
                "empty/Stats/warm",
                "empty/Settings/cold",
                "empty/Settings/warm",
                "10000/Home/cold",
                "10000/Home/warm",
                "10000/Modes/cold",
                "10000/Modes/warm",
                "10000/Models/cold",
                "10000/Models/warm",
                "10000/History/cold",
                "10000/History/warm",
                "10000/Stats/cold",
                "10000/Stats/warm",
                "10000/Settings/cold",
                "10000/Settings/warm",
            ],
        )

    def test_matrix_gate_rejects_duplicate_and_unexpected_routes(self) -> None:
        run = self.run_result("empty", {"Home": 20.0})
        run["routes"].append(dict(run["routes"][0]))
        run["routes"].append(
            {
                "destination": "Unknown",
                "visit": "cold",
                "samplesMilliseconds": [20.0],
                "statistics": {"medianMilliseconds": 20.0},
            }
        )

        result = run_pane_performance.evaluate_matrix_gate(
            runs=[run],
            expected_sample_count=1,
        )

        self.assertEqual(result["duplicateRoutes"], ["empty/Home/cold"])
        self.assertEqual(result["unexpectedRoutes"], ["empty/Unknown/cold"])

    def test_post_sparkle_comparison_includes_every_route(self) -> None:
        baselines = {
            "postSparkleRoutes": {
                "empty/Home/cold": {"medianMilliseconds": 34.0},
                "empty/Home/warm": {"medianMilliseconds": 32.0},
            },
        }
        runs = [
            {
                "profile": "empty",
                "routes": [
                    {
                        "destination": "Home",
                        "visit": "cold",
                        "samplesMilliseconds": [17.0],
                        "statistics": {"medianMilliseconds": 17.0},
                    },
                    {
                        "destination": "Home",
                        "visit": "warm",
                        "samplesMilliseconds": [16.0],
                        "statistics": {"medianMilliseconds": 16.0},
                    },
                ],
            },
        ]

        result = run_pane_performance.post_sparkle_comparison(runs, baselines)

        self.assertEqual(
            result["empty/Home/cold"],
            {
                "postSparkleMedianMilliseconds": 34.0,
                "currentMedianMilliseconds": 17.0,
                "deltaMilliseconds": -17.0,
                "ratio": 0.5,
            },
        )
        self.assertEqual(set(result), set(baselines["postSparkleRoutes"]))

    def test_matrix_gate_checks_raw_sample_count(self) -> None:
        runs = [
            {
                "profile": "empty",
                "routes": [
                    {
                        "destination": "Home",
                        "visit": "cold",
                        "samplesMilliseconds": [42.0] * 19,
                    },
                ],
            },
        ]

        result = run_pane_performance.evaluate_matrix_gate(
            runs,
            expected_sample_count=20,
        )

        self.assertEqual(
            result["sampleCountViolations"],
            [
                {
                    "route": "empty/Home/cold",
                    "expected": 20,
                    "actual": 19,
                },
            ],
        )

    def test_matrix_gate_rejectsNonDeterministicFixtureOrWarmUpContract(self) -> None:
        run = self.run_result("empty", {"Home": 20.0})
        run.update(
            {
                "fixtureIdentity": "live-data",
                "warmUpSamplesDiscarded": 0,
                "recordedSamplesPerClass": 1,
            }
        )

        result = run_pane_performance.evaluate_matrix_gate(
            runs=[run],
            expected_sample_count=1,
        )

        self.assertEqual(
            result["runMetadataViolations"],
            [
                {
                    "profile": "empty",
                    "field": "fixtureIdentity",
                    "expected": "pane-empty-v1",
                    "actual": "live-data",
                },
                {
                    "profile": "empty",
                    "field": "warmUpSamplesDiscarded",
                    "expected": 1,
                    "actual": 0,
                },
            ],
        )

    def test_trace_matrix_covers_high_risk_routes_in_both_profiles(self) -> None:
        self.assertEqual(
            run_pane_performance.trace_specifications(),
            [
                {
                    "profile": "empty",
                    "template": "SwiftUI",
                    "instruments": ["os_signpost"],
                    "destinations": ["Modes", "Stats"],
                    "visitClasses": ["cold", "warm"],
                    "components": [
                        "SwiftUI",
                        "Time Profiler",
                        "Hitches",
                        "PaneNavigation signposts",
                        "FirstWindowOpening signpost",
                    ],
                },
                {
                    "profile": "10000",
                    "template": "SwiftUI",
                    "instruments": ["os_signpost"],
                    "destinations": [
                        "Home",
                        "Modes",
                        "History",
                        "Stats",
                    ],
                    "visitClasses": ["cold", "warm"],
                    "components": [
                        "SwiftUI",
                        "Time Profiler",
                        "Hitches",
                        "PaneNavigation signposts",
                        "FirstWindowOpening signpost",
                    ],
                },
            ],
        )

    def test_trace_command_records_signposts_in_the_swiftUI_execution(self) -> None:
        command = run_pane_performance.trace_record_command(
            {
                "template": "SwiftUI",
                "instruments": ["os_signpost"],
            },
            trace_path=Path("/tmp/result.trace"),
            plan_path=Path("/tmp/plan.json"),
            executable=Path("/tmp/FoldWiseVoice"),
        )

        self.assertEqual(
            command,
            [
                "xcrun",
                "xctrace",
                "record",
                "--template",
                "SwiftUI",
                "--instrument",
                "os_signpost",
                "--output",
                "/tmp/result.trace",
                "--no-prompt",
                "--env",
                (
                    "FOLDWISE_PANE_PERFORMANCE_PLAN="
                    f"{Path('/tmp/plan.json').resolve()}"
                ),
                "--launch",
                "--",
                "/tmp/FoldWiseVoice",
            ],
        )

    def test_hitch_gate_counts_only_navigation_interval_overlaps(self) -> None:
        toc_xml = """
        <trace-toc>
          <run>
            <info>
              <summary>
                <start-date>1970-01-01T00:16:40.000+00:00</start-date>
              </summary>
            </info>
          </run>
        </trace-toc>
        """
        hitches_xml = """
        <trace-query-result>
          <row>
            <start-time>500000000</start-time>
            <duration>100000000</duration>
          </row>
          <row>
            <start-time>1050000000</start-time>
            <duration>10000000</duration>
          </row>
        </trace-query-result>
        """
        run = {
            "profile": "empty",
            "navigationIntervals": [
                {
                    "destination": "Stats",
                    "visit": "cold",
                    "sample": "warmUp",
                    "startedAtSystemUptime": 120.5,
                    "endedAtSystemUptime": 120.6,
                    "startedAtEpoch": 1000.5,
                    "endedAtEpoch": 1000.6,
                },
                {
                    "destination": "Stats",
                    "visit": "cold",
                    "sample": "recorded",
                    "startedAtSystemUptime": 121.0,
                    "endedAtSystemUptime": 121.1,
                    "startedAtEpoch": 1001.0,
                    "endedAtEpoch": 1001.1,
                },
            ],
        }

        result = run_pane_performance.evaluate_hitch_gate(
            run,
            toc_xml,
            hitches_xml,
        )

        self.assertEqual(
            result["navigationHitches"],
            [
                {
                    "profile": "empty",
                    "destination": "Stats",
                    "visit": "cold",
                    "sample": "recorded",
                    "hitchStartMilliseconds": 1050.0,
                    "hitchDurationMilliseconds": 10.0,
                },
            ],
        )

    def test_causal_gate_rejects_navigation_updateFanoutAndStalls(self) -> None:
        toc_xml = """
        <trace-toc><run><info><summary>
          <start-date>1970-01-01T00:16:40.000+00:00</start-date>
        </summary></info></run></trace-toc>
        """
        run = {
            "profile": "empty",
            "navigationIntervals": [
                {
                    "destination": "Stats",
                    "visit": "cold",
                    "sample": "recorded",
                    "startedAtEpoch": 1001.0,
                    "endedAtEpoch": 1001.1,
                },
            ],
        }
        update_groups = """
        <trace-query-result><row>
          <start-time>1050000000</start-time><duration>10000000</duration>
        </row></trace-query-result>
        """
        potential_hangs = """
        <trace-query-result><row>
          <start-time>1070000000</start-time><duration>10000000</duration>
        </row></trace-query-result>
        """
        time_profile = """
        <trace-query-result>
          <row>
            <sample-time>1050000000</sample-time>
            <thread id="main" fmt="Main Thread 0x1 (FoldWiseVoice, pid: 1)" />
            <thread-state id="running" fmt="Running">Running</thread-state>
            <weight id="weight">5000000</weight>
            <backtrace><frame name="LayoutEngineBox.sizeThatFits(_:)" /></backtrace>
          </row>
          <row>
            <sample-time>1055000000</sample-time>
            <thread ref="main" />
            <thread-state ref="running" />
            <weight ref="weight" />
            <backtrace><frame name="LayoutEngineBox.sizeThatFits(_:)" /></backtrace>
          </row>
          <row>
            <sample-time>1060000000</sample-time>
            <thread ref="main" />
            <thread-state ref="running" />
            <weight ref="weight" />
            <backtrace><frame name="LayoutEngineBox.sizeThatFits(_:)" /></backtrace>
          </row>
          <row>
            <sample-time>1065000000</sample-time>
            <thread ref="main" />
            <thread-state ref="running" />
            <weight ref="weight" />
            <backtrace><frame name="LayoutEngineBox.sizeThatFits(_:)" /></backtrace>
          </row>
          <row>
            <sample-time>1070000000</sample-time>
            <thread ref="main" />
            <thread-state ref="running" />
            <weight ref="weight" />
            <backtrace><frame name="LayoutEngineBox.sizeThatFits(_:)" /></backtrace>
          </row>
        </trace-query-result>
        """

        result = run_pane_performance.evaluate_causal_gate(
            run,
            toc_xml,
            update_groups,
            potential_hangs,
            time_profile,
        )

        self.assertEqual(result["navigationUpdateGroupCount"], 1)
        self.assertEqual(result["navigationPotentialHangCount"], 1)
        self.assertEqual(
            result["navigationMainThreadStalls"],
            [
                {
                    "profile": "empty",
                    "destination": "Stats",
                    "visit": "cold",
                    "sample": "recorded",
                    "startMilliseconds": 1050.0,
                    "durationMilliseconds": 25.0,
                    "dominantLeafFrame": "LayoutEngineBox.sizeThatFits(_:)",
                    "classification": "explainedFrameRendering",
                    "renderingSamplePercent": 100.0,
                },
            ],
        )
        self.assertEqual(result["navigationUnexplainedMainThreadStallCount"], 0)
        self.assertEqual(result["passed"], False)

    def test_causal_gate_rejects_unexplained_main_thread_stall(self) -> None:
        toc_xml = """
        <trace-toc><run><info><summary>
          <start-date>1970-01-01T00:16:40.000+00:00</start-date>
        </summary></info></run></trace-toc>
        """
        run = {
            "profile": "10000",
            "navigationIntervals": [
                {
                    "destination": "History",
                    "visit": "cold",
                    "sample": "recorded",
                    "startedAtEpoch": 1001.0,
                    "endedAtEpoch": 1001.1,
                },
            ],
        }
        samples = "\n".join(
            f"""
            <row>
              <sample-time>{1_050_000_000 + offset * 5_000_000}</sample-time>
              <thread id="main-{offset}" fmt="Main Thread 0x1 (FoldWiseVoice, pid: 1)" />
              <thread-state id="running-{offset}" fmt="Running">Running</thread-state>
              <weight>5000000</weight>
              <backtrace><frame name="JSONLHistoryStore.load()" /></backtrace>
            </row>
            """
            for offset in range(5)
        )

        result = run_pane_performance.evaluate_causal_gate(
            run,
            toc_xml,
            "<trace-query-result />",
            "<trace-query-result />",
            f"<trace-query-result>{samples}</trace-query-result>",
        )

        self.assertEqual(result["navigationUnexplainedMainThreadStallCount"], 1)
        self.assertEqual(
            result["navigationMainThreadStalls"][0]["classification"],
            "unexplained",
        )
        self.assertEqual(result["passed"], False)

    def test_causal_gate_accepts_explained_hitch_free_frame_rendering(self) -> None:
        toc_xml = """
        <trace-toc><run><info><summary>
          <start-date>1970-01-01T00:16:40.000+00:00</start-date>
        </summary></info></run></trace-toc>
        """
        run = {
            "profile": "empty",
            "navigationIntervals": [
                {
                    "destination": "Modes",
                    "visit": "warm",
                    "sample": "recorded",
                    "startedAtEpoch": 1001.0,
                    "endedAtEpoch": 1001.1,
                },
            ],
        }
        samples = "\n".join(
            f"""
            <row>
              <sample-time>{1_050_000_000 + offset * 5_000_000}</sample-time>
              <thread id="main-{offset}" fmt="Main Thread 0x1 (FoldWiseVoice, pid: 1)" />
              <thread-state id="running-{offset}" fmt="Running">Running</thread-state>
              <weight>5000000</weight>
              <backtrace>
                <frame name="&lt;deduplicated_symbol&gt;" />
                <frame name="GraphHost.flushTransactions()" />
              </backtrace>
            </row>
            """
            for offset in range(5)
        )

        result = run_pane_performance.evaluate_causal_gate(
            run,
            toc_xml,
            "<trace-query-result />",
            "<trace-query-result />",
            f"<trace-query-result>{samples}</trace-query-result>",
        )

        self.assertEqual(result["navigationMainThreadStallCount"], 1)
        self.assertEqual(result["navigationExplainedMainThreadStallCount"], 1)
        self.assertEqual(result["navigationUnexplainedMainThreadStallCount"], 0)
        self.assertEqual(result["passed"], True)

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
                    "samplesMilliseconds": [median],
                    "statistics": {"medianMilliseconds": median},
                }
                for destination, median in medians.items()
            ],
        }


if __name__ == "__main__":
    unittest.main()
