import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class ModeEditorHostedTests: XCTestCase {
    func testHostedEditorUsesApprovedSheetGeometryWithValidationErrors() {
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

    func testHostedModesPaneKeepsMinimumWidthForSelectedAndEmptyLibraries() {
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

    func testHostedModesPaneKeyboardShortcutMovesSelectedModeDown() throws {
        let model = SettingsModel()
        model.pane = .modes
        let first = mode(name: "First")
        let second = mode(name: "Second")
        let firstID = try XCTUnwrap(first.id)
        model.modes = [first, second]
        model.modeSelection = ModePresentationFactory.projection(
            modes: model.modes,
            selection: .mode(firstID)
        )
        var moved: ModeMoveDirection?
        model.onMoveMode = { _, direction in moved = direction }
        let hosting = hostSettings(model)
        let window = hostInKeyWindow(hosting)

        sendMoveDownShortcut(to: window)
        window.orderOut(nil)

        XCTAssertEqual(moved, .down)
    }

    func testHostedDeletionAlertKeepsConfirmationWhenDeleteFails() {
        let model = SettingsModel()
        let pending = ModeDeletionState(
            id: .random(),
            title: "Delete Example?",
            message: "History remains and the AI model is not uninstalled."
        )
        model.modePendingDeletion = pending
        var confirmations = 0
        var cancellations = 0
        model.onConfirmModeDeletion = { confirmations += 1 }
        model.onCancelModeDeletion = {
            cancellations += 1
            model.modePendingDeletion = nil
        }
        let hosting = hostSettings(model)
        let window = makeWindow(hosting)
        let observer = SheetObserver {
            DispatchQueue.main.async {
                guard let button = Self.button(
                    named: "Delete",
                    in: window.attachedSheet?.contentView
                ) else {
                    XCTFail("The deletion alert did not expose its destructive action.")
                    NSApp.abortModal()
                    return
                }
                button.performClick(nil)
                DispatchQueue.main.async { NSApp.abortModal() }
            }
        }
        window.delegate = observer

        showInKeyWindow(window, hosting: hosting)
        NSApp.runModal(for: window)
        window.delegate = nil
        window.orderOut(nil)

        XCTAssertEqual(
            [confirmations, cancellations, model.modePendingDeletion == pending ? 1 : 0],
            [1, 0, 1]
        )
    }

    private func hostSettings(_ model: SettingsModel) -> NSHostingView<SettingsView> {
        let hosting = NSHostingView(rootView: SettingsView(model: model))
        hosting.frame = NSRect(x: 0, y: 0, width: 980, height: 720)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    private func mode(name: String) -> Mode {
        Mode(
            id: .random(),
            name: name,
            icon: "text.bubble",
            asrModel: ASRModelCatalog.defaultID,
            llmModel: "qwen2.5:3b",
            transformation: .inPlace,
            systemPrompt: "Keep wording.",
            vocabulary: []
        )
    }

    private func hostInKeyWindow(_ hosting: NSHostingView<SettingsView>) -> NSWindow {
        let window = makeWindow(hosting)
        showInKeyWindow(window, hosting: hosting)
        return window
    }

    private func makeWindow(_ hosting: NSHostingView<SettingsView>) -> NSWindow {
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        return window
    }

    private func showInKeyWindow(
        _ window: NSWindow,
        hosting: NSHostingView<SettingsView>
    ) {
        NSApp.finishLaunching()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
    }

    private static func button(named title: String, in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton, button.title == title {
            return button
        }
        return view.subviews.lazy.compactMap { button(named: title, in: $0) }.first
    }

    private func sendMoveDownShortcut(to window: NSWindow) {
        DispatchQueue.main.async {
            if let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command, .option],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "\u{F701}",
                charactersIgnoringModifiers: "\u{F701}",
                isARepeat: false,
                keyCode: 125
            ) {
                NSApp.sendEvent(event)
            }
            NSApp.abortModal()
        }
        NSApp.runModal(for: window)
        window.contentView?.layoutSubtreeIfNeeded()
    }
}

@MainActor
private final class SheetObserver: NSObject, NSWindowDelegate {
    private let onBegin: () -> Void

    init(onBegin: @escaping () -> Void) {
        self.onBegin = onBegin
    }

    func windowWillBeginSheet(_: Notification) {
        onBegin()
    }
}
