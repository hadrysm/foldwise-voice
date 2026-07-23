import XCTest
@testable import FoldWiseVoiceKit

final class HomeOverviewLayoutTests: XCTestCase {
    func testWideCompositionStartsAtTheHomeBreakpoint() {
        XCTAssertEqual(HomeOverviewLayout.forWindowWidth(940), .wide)
    }

    func testCompactCompositionAppliesBelowTheHomeBreakpoint() {
        XCTAssertEqual(HomeOverviewLayout.forWindowWidth(939), .compact)
    }

    func testWideCompositionUsesFourMetricColumns() {
        XCTAssertEqual(HomeOverviewLayout.wide.metricColumnCount, 4)
    }

    func testCompactCompositionUsesTwoMetricColumns() {
        XCTAssertEqual(HomeOverviewLayout.compact.metricColumnCount, 2)
    }

    func testWideCompositionUsesCanonicalWidePadding() {
        XCTAssertEqual(
            HomeOverviewLayout.wide.contentPadding,
            Theme.contentPaddingWide
        )
    }

    func testCompactCompositionUsesCanonicalCompactPadding() {
        XCTAssertEqual(
            HomeOverviewLayout.compact.contentPadding,
            Theme.contentPaddingCompact
        )
    }
}
