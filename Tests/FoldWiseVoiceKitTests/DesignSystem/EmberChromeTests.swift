import XCTest
@testable import FoldWiseVoiceKit

final class EmberChromeTests: XCTestCase {
    func testGlobalToastMotionRisesFromBelowAndExitsTowardTheBottom() {
        XCTAssertEqual(GlobalStatusToastMotion.insertionOffset, 20)
        XCTAssertEqual(GlobalStatusToastMotion.removalOffset, 12)
        XCTAssertLessThan(GlobalStatusToastMotion.insertionScale, 1)
        XCTAssertLessThan(GlobalStatusToastMotion.removalScale, 1)
    }

    func testPlainButtonStyleDoesNotStoreInheritedFocusState() {
        let storedState = Mirror(reflecting: EmberPlainButtonStyle()).children

        XCTAssertFalse(
            storedState.contains { $0.label == "_isFocused" },
            "plain buttons must leave keyboard-focus ownership to their call site"
        )
    }

    func testSemanticNoticeUsesCanonicalIngressByDefault() {
        let notice = EmberStatusNotice(kind: .success, title: "Saved")

        XCTAssertEqual(notice.ingressWidth, Theme.noticeIngressWidth)
    }

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
