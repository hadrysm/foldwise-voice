// Version comparison for the update checker. Component-wise numeric compare —
// "0.10.0" must beat "0.9.0", which naive string comparison gets wrong.
// Network paths (fetchLatestRelease/checkNow) are deliberately untested here.

import XCTest

@testable import FoldWiseVoiceKit

@MainActor
final class UpdateCheckerVersionTests: XCTestCase {
    func testNumericNotLexicographicComparison() {
        XCTAssertTrue(UpdateChecker.isNewer("0.10.0", than: "0.9.0"))
        XCTAssertFalse(UpdateChecker.isNewer("0.6.2", than: "0.10.0"))
    }

    func testEqualVersionsAreNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("1.2.3", than: "1.2.3"))
    }

    func testComponentCountMismatchPadsWithZeros() {
        XCTAssertFalse(UpdateChecker.isNewer("1.2", than: "1.2.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.2.0", than: "1.2"))
        XCTAssertTrue(UpdateChecker.isNewer("1.2.1", than: "1.2"))
        XCTAssertTrue(UpdateChecker.isNewer("1.3", than: "1.2.9"))
    }

    func testMajorAndMinorBumps() {
        XCTAssertTrue(UpdateChecker.isNewer("1.0.0", than: "0.99.99"))
        XCTAssertTrue(UpdateChecker.isNewer("0.7.0", than: "0.6.2"))
        XCTAssertFalse(UpdateChecker.isNewer("0.6.1", than: "0.6.2"))
    }

    func testNonNumericVersionsNeverCompareAsNewer() {
        // Pre-release tags are ignored rather than compared.
        XCTAssertFalse(UpdateChecker.isNewer("1.2.3-rc1", than: "1.2.2"))
        XCTAssertFalse(UpdateChecker.isNewer("1.2.3", than: "1.2.3-rc1"))
        XCTAssertFalse(UpdateChecker.isNewer("", than: "1.0.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0.0", than: ""))
        XCTAssertFalse(UpdateChecker.isNewer("abc", than: "1.0.0"))
    }
}
