import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class SettingsViewPresentationTests: XCTestCase {
    func testConfigurationRecoveryPermissionMatrixKeepsOnlySafeDestinationsAvailable() {
        let model = SettingsModel()
        XCTAssertTrue(SettingsModel.Pane.allCases.allSatisfy(model.isPaneAvailable))

        model.configurationRecoveryMessage = "Configuration could not be loaded."
        XCTAssertEqual(
            SettingsModel.Pane.allCases.map(model.isPaneAvailable),
            [true, false, false, false, true, false]
        )
    }

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

    func testAppearanceLayoutChangesAtApprovedContentWidth() {
        XCTAssertEqual(
            [
                SettingsAppearanceLayout.forContentWidth(649.999),
                SettingsAppearanceLayout.forContentWidth(650),
            ],
            [.vertical, .horizontal]
        )
    }
}
