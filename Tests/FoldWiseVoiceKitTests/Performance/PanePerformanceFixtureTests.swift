import Foundation
import XCTest
@testable import FoldWiseVoiceKit

final class PanePerformanceFixtureTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("foldwise-pane-fixture-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testEmptyProfileContainsNoSessions() {
        XCTAssertTrue(PanePerformanceFixture(profile: .empty).entries.isEmpty)
    }

    func testTenThousandProfileContainsExactlyTenThousandSessions() {
        XCTAssertEqual(
            PanePerformanceFixture(profile: .tenThousand).entries.count,
            10000
        )
    }

    func testTenThousandProfileHasStableBoundarySessions() {
        let fixture = PanePerformanceFixture(profile: .tenThousand)

        XCTAssertEqual(
            [fixture.entries.first, fixture.entries.last].compactMap(\.self),
            [
                PanePerformanceFixture.expectedEntry(at: 0),
                PanePerformanceFixture.expectedEntry(at: 9999),
            ]
        )
    }

    func testFixtureRoundTripsThroughProductionHistoryStore() throws {
        let fixture = PanePerformanceFixture(profile: .tenThousand)
        let historyURL = directory.appendingPathComponent("history.jsonl")

        try fixture.write(to: historyURL)

        XCTAssertEqual(JSONLHistoryStore(url: historyURL).load(), fixture.entries)
    }

    func testProfilesHaveStableDistinctIdentities() {
        XCTAssertEqual(
            [
                PanePerformanceFixture(profile: .empty).identity,
                PanePerformanceFixture(profile: .tenThousand).identity,
            ],
            ["pane-empty-v1", "pane-10000-v1"]
        )
    }
}
