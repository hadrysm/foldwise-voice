import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class SettingsModelTests: XCTestCase {
    func testPaneIDsMatchEachDestination() {
        XCTAssertEqual(
            SettingsModel.Pane.allCases.map(\.id),
            ["Home", "Modes", "Models", "History", "Stats", "Settings"]
        )
    }

    func testPaneIconsMatchEachDestination() {
        XCTAssertEqual(
            SettingsModel.Pane.allCases.map(\.icon),
            ["house", "sparkles", "shippingbox", "clock", "chart.bar", "slider.horizontal.3"]
        )
    }

    func testOllamaDownOnlyWhenTheAvailableListIsEmpty() {
        let model = SettingsModel()
        XCTAssertFalse(model.ollamaDown)

        model.installed = []
        XCTAssertTrue(model.ollamaDown)

        model.installed = [installed("qwen2.5:3b")]
        XCTAssertFalse(model.ollamaDown)
    }

    func testSelectedModelIsAllowedWhileAvailabilityIsUnknownOrOllamaIsDown() {
        let model = SettingsModel()
        model.selectedModel = "qwen2.5:3b"
        XCTAssertTrue(model.selectedModelInstalled)

        model.installed = []
        XCTAssertTrue(model.selectedModelInstalled)
    }

    func testSelectedModelInstalledReflectsTheAvailableModelList() {
        let model = SettingsModel()
        model.selectedModel = "qwen2.5:3b"
        model.installed = [installed("llama3.2:3b"), installed("qwen2.5:3b")]

        XCTAssertTrue(model.selectedModelInstalled)

        model.selectedModel = "missing:latest"
        XCTAssertFalse(model.selectedModelInstalled)
    }

    private func installed(_ name: String) -> OllamaClient.InstalledModel {
        OllamaClient.InstalledModel(name: name, sizeBytes: 1)
    }
}
