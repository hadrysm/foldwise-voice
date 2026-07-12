import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

final class HomeDictationFocusPolicyTests: XCTestCase {
    func testFocusInteractionsExcludePointerEditingFocus() {
        XCTAssertEqual(HomeDictationFocusPolicy.interactions, .activate)
    }
}
