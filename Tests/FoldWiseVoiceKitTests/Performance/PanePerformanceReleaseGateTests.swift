import Foundation
import XCTest
@testable import FoldWiseVoiceKit

final class PanePerformanceReleaseGateTests: XCTestCase {
    func testRelativeBaselineRejectsMoreThanTwentyPercentDegradation() throws {
        let result = try PanePerformanceReleaseGate.evaluate(
            reportData: reportData(median: 48.001),
            baselineData: baselineData(median: 40)
        )

        XCTAssertEqual(result.relativeViolations, ["empty/Home/cold"])
    }

    func testRelativeBaselineNeverWaivesAbsoluteCap() throws {
        let result = try PanePerformanceReleaseGate.evaluate(
            reportData: reportData(median: 10, samples: [10, 100.001]),
            baselineData: baselineData(median: 200)
        )

        XCTAssertEqual(result.absoluteViolations, ["empty/Home/cold"])
    }

    func testRelativeBaselineRejectsMeasuredRouteWithoutBaseline() throws {
        let result = try PanePerformanceReleaseGate.evaluate(
            reportData: reportData(median: 10),
            baselineData: try JSONSerialization.data(withJSONObject: [
                "maximumRegressionPercent": 20,
                "routes": [:],
            ])
        )

        XCTAssertEqual(result.missingBaselines, ["empty/Home/cold"])
    }

    func testFixedMacReportMeetsRelativeAndAbsoluteBaselines() throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            let reportPath = environment["FOLDWISE_PANE_PERFORMANCE_REPORT"],
            let baselinePath = environment["FOLDWISE_PANE_PERFORMANCE_BASELINES"]
        else {
            throw XCTSkip(
                "The fixed-Mac Release lane supplies its retained report and baselines."
            )
        }

        let result = try PanePerformanceReleaseGate.evaluate(
            reportData: Data(contentsOf: URL(fileURLWithPath: reportPath)),
            baselineData: Data(contentsOf: URL(fileURLWithPath: baselinePath))
        )

        XCTAssertEqual(result, .passed)
    }

    private func reportData(
        median: Double,
        samples: [Double]? = nil
    ) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "runs": [
                [
                    "profile": "empty",
                    "routes": [
                        [
                            "destination": "Home",
                            "visit": "cold",
                            "samplesMilliseconds": samples ?? [median],
                            "statistics": ["medianMilliseconds": median],
                        ],
                    ],
                ],
            ],
        ])
    }

    private func baselineData(median: Double) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "maximumRegressionPercent": 20,
            "routes": [
                "empty/Home/cold": ["medianMilliseconds": median],
            ],
        ])
    }
}
