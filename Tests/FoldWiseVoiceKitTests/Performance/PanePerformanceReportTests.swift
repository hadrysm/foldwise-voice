import Foundation
import XCTest
@testable import FoldWiseVoiceKit

final class PanePerformanceReportTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("foldwise-pane-report-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testStatisticsUseObservedP95AndRetainWorstSample() throws {
        let statistics = try PanePerformanceStatistics(
            samplesMilliseconds: Array((1 ... 20).reversed()).map(Double.init)
        )

        XCTAssertEqual(
            statistics,
            PanePerformanceStatistics(
                medianMilliseconds: 10.5,
                p95Milliseconds: 19,
                worstMilliseconds: 20
            )
        )
    }

    func testReportRetainsEveryRawSample() throws {
        let route = try PanePerformanceRouteResult(
            source: .home,
            destination: .stats,
            visit: .warm,
            samplesMilliseconds: [80, 90, 100]
        )

        XCTAssertEqual(route.samplesMilliseconds, [80, 90, 100])
    }

    func testStatisticsRejectAnEmptySampleSet() {
        XCTAssertThrowsError(
            try PanePerformanceStatistics(samplesMilliseconds: [])
        )
    }

    func testPlanLoadsAnExplicitComparableRunMatrix() throws {
        let url = directory.appendingPathComponent("plan.json")
        let plan = PanePerformancePlan(
            profile: .empty,
            outputURL: directory.appendingPathComponent("result.json"),
            dataDirectory: directory.appendingPathComponent("profile"),
            sampleCount: 20,
            destinations: SettingsModel.Pane.allCases
        )
        try JSONEncoder().encode(plan).write(to: url)

        XCTAssertEqual(try PanePerformancePlan.load(from: url), plan)
    }

    func testPlanRejectsAnEmptySampleSet() throws {
        let url = directory.appendingPathComponent("plan.json")
        let plan = PanePerformancePlan(
            profile: .empty,
            outputURL: directory.appendingPathComponent("result.json"),
            dataDirectory: directory.appendingPathComponent("profile"),
            sampleCount: 0,
            destinations: [.home]
        )
        try JSONEncoder().encode(plan).write(to: url)

        XCTAssertThrowsError(try PanePerformancePlan.load(from: url))
    }

    func testPlanRejectsTheLiveApplicationSupportProfile() throws {
        let url = directory.appendingPathComponent("plan.json")
        let plan = PanePerformancePlan(
            profile: .empty,
            outputURL: directory.appendingPathComponent("result.json"),
            dataDirectory: JSONLHistoryStore.defaultURL.deletingLastPathComponent(),
            sampleCount: 20,
            destinations: [.home]
        )
        try JSONEncoder().encode(plan).write(to: url)

        XCTAssertThrowsError(try PanePerformancePlan.load(from: url))
    }

    func testPlanRejectsAnOutputInLiveApplicationSupport() throws {
        let url = directory.appendingPathComponent("plan.json")
        let plan = PanePerformancePlan(
            profile: .empty,
            outputURL: JSONLHistoryStore.defaultURL,
            dataDirectory: directory.appendingPathComponent("profile"),
            sampleCount: 20,
            destinations: [.home]
        )
        try JSONEncoder().encode(plan).write(to: url)

        XCTAssertThrowsError(try PanePerformancePlan.load(from: url))
    }

    func testRunReportWritesMachineReadableRawResults() throws {
        let outputURL = directory.appendingPathComponent("result.json")
        let route = try PanePerformanceRouteResult(
            source: .settings,
            destination: .home,
            visit: .cold,
            samplesMilliseconds: [25, 30]
        )
        let report = PanePerformanceRunReport(
            fixtureIdentity: "pane-empty-v1",
            profile: .empty,
            recordedSamplesPerClass: 2,
            firstWindowMilliseconds: 80,
            routes: [route]
        )

        try report.write(to: outputURL)

        XCTAssertEqual(
            try JSONDecoder().decode(
                PanePerformanceRunReport.self,
                from: Data(contentsOf: outputURL)
            ),
            report
        )
    }
}
