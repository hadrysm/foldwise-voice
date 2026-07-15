import XCTest
@testable import FoldWiseVoiceKit

final class SettingsViewPresentationTests: XCTestCase {
    func testAppearancePresentationMatchesApprovedTiles() {
        XCTAssertEqual(
            AppearanceTilePresentation.all,
            [
                AppearanceTilePresentation(
                    preference: .system,
                    title: "System",
                    symbolName: "circle.lefthalf.filled",
                    detail: "Follows macOS as it changes"
                ),
                AppearanceTilePresentation(
                    preference: .light,
                    title: "Light",
                    symbolName: "sun.max",
                    detail: "Always uses the light appearance"
                ),
                AppearanceTilePresentation(
                    preference: .dark,
                    title: "Dark",
                    symbolName: "moon",
                    detail: "Always uses the dark appearance"
                ),
            ]
        )
    }
}
