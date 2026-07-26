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

    func testTenThousandProfileHasStableBoundaryIdentifiers() {
        let fixture = PanePerformanceFixture(profile: .tenThousand)

        XCTAssertEqual(
            [fixture.entries.first?.id.uuidString, fixture.entries.last?.id.uuidString],
            [
                "00000000-0000-4000-8000-000000000000",
                "00000000-0000-4000-8000-00000000270F",
            ]
        )
    }

    func testTenThousandProfileHasStableBoundaryTimestamps() {
        let fixture = PanePerformanceFixture(profile: .tenThousand)

        XCTAssertEqual(
            [
                fixture.entries.first?.createdAt.timeIntervalSince1970,
                fixture.entries.last?.createdAt.timeIntervalSince1970,
            ],
            [1_783_075_200, 1_760_877_420]
        )
    }

    func testTenThousandProfileHasStableModeAttribution() {
        let fixture = PanePerformanceFixture(profile: .tenThousand)

        XCTAssertEqual(
            [fixture.entries.first?.modeName, fixture.entries.last?.modeName],
            ["Performance Mode", "Performance Mode"]
        )
    }

    func testTenThousandProfileHasStableText() {
        let fixture = PanePerformanceFixture(profile: .tenThousand)

        XCTAssertEqual(
            fixture.entries.first?.rawText,
            "meeting history release notes calendar review follow dictation customer up session research"
        )
    }

    func testTenThousandProfileHasStableFlags() {
        let fixture = PanePerformanceFixture(profile: .tenThousand)

        XCTAssertEqual(
            [fixture.entries.first?.flagged, fixture.entries.last?.flagged],
            [true, false]
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
