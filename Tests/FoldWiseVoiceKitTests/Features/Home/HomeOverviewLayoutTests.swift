import XCTest
@testable import FoldWiseVoiceKit

final class HomeOverviewLayoutTests: XCTestCase {
    func testWideCompositionStartsAtTheHomeBreakpoint() {
        XCTAssertEqual(HomeOverviewLayout.forWindowWidth(940), .wide)
    }

    func testCompactCompositionAppliesBelowTheHomeBreakpoint() {
        XCTAssertEqual(HomeOverviewLayout.forWindowWidth(939), .compact)
    }
}
