import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class ModeEditorHostedTests: XCTestCase {
    func testHostedEditorUsesApprovedSheetGeometryAcrossValidationStates() {
        let model = SettingsModel()
        model.installed = []
        model.modeEditor = ModeEditorState(
            purpose: .add,
            draft: ModeEditorDraft(
                name: "A very long Mode name that remains fully available to accessibility",
                icon: "symbol.that.is.not.available",
                model: "missing:latest",
                transformation: .expanding,
                systemPrompt: "Reshape this text while preserving meaning.",
                vocabularyText: "FoldWise\nBuenos Aires"
            ),
            issues: ModeEditorIssues(
                name: "A Mode named 'Example' already exists.",
                model: "missing:latest isn't installed. Install it in Models before saving.",
                systemPrompt: "Enter Polish instructions."
            ),
            persistenceError: "Couldn't save Mode: permission denied"
        )
        let hosting = NSHostingView(rootView: ModeEditorSheet(model: model))
        hosting.frame = NSRect(x: 0, y: 0, width: 820, height: 570)

        hosting.layoutSubtreeIfNeeded()

        XCTAssertEqual(hosting.fittingSize, NSSize(width: 820, height: 570))
    }

    func testHostedModesPaneRendersSelectedAndEmptyLibraries() {
        let selectedModel = SettingsModel()
        selectedModel.pane = .modes
        let modeID = ModeID.random()
        let mode = Mode(
            id: modeID,
            name: "Long planning notes Mode",
            icon: "text.bubble",
            asrModel: ASRModelCatalog.defaultID,
            llmModel: "missing:latest",
            transformation: .inPlace,
            systemPrompt: "Keep wording.",
            vocabulary: ["FoldWise"]
        )
        selectedModel.modes = [mode]
        selectedModel.modeSelection = ModePresentationFactory.projection(
            modes: [mode], selection: .mode(modeID)
        )
        selectedModel.installed = []
        let selected = hostSettings(selectedModel)

        let emptyModel = SettingsModel()
        emptyModel.pane = .modes
        let empty = hostSettings(emptyModel)

        XCTAssertEqual(
            [selected.fittingSize.width >= 880, empty.fittingSize.width >= 880],
            [true, true]
        )
    }

    private func hostSettings(_ model: SettingsModel) -> NSHostingView<SettingsView> {
        let hosting = NSHostingView(rootView: SettingsView(model: model))
        hosting.frame = NSRect(x: 0, y: 0, width: 980, height: 720)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }
}
