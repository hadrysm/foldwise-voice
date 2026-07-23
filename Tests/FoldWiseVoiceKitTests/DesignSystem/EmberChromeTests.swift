import XCTest
@testable import FoldWiseVoiceKit

final class EmberChromeTests: XCTestCase {
    func testSemanticNoticesPairColorWithPermanentIconAndTextCues() {
        XCTAssertEqual(
            EmberStatusKind.allCases.map {
                [$0.accessibilityName, $0.symbolName, $0.colorRole.rawValue]
            },
            [
                ["Success", "checkmark.circle.fill", "success"],
                ["Warning", "exclamationmark.triangle.fill", "warning"],
                ["Error", "xmark.octagon.fill", "error"],
            ]
        )
    }
}
