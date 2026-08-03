import AppKit
import SwiftUI
import Vision
import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class ModeEditorHostedTests: XCTestCase {
    /// Inside the rendered Move up control's leading edge, outside its centred label.
    private let moveUpLeadingEdge = NSPoint(x: 563, y: 198)

    private struct RenderedSelectionCues {
        let leadingAccent: Int
        let iconAccent: Int
        let titlePrimary: Int
        let checkmarkAccent: Int
        let totalAccent: Int
        let totalPixels: Int
    }

    func testHostedSelectedCommandLedgerRowRendersPermanentCuesWithoutAccentWash() throws {
        let selected = try renderedSelectionCues(isSelected: true)
        let unselected = try renderedSelectionCues(isSelected: false)

        XCTAssertEqual(
            [
                selected.leadingAccent > 70,
                selected.iconAccent > unselected.iconAccent + 10,
                selected.titlePrimary > unselected.titlePrimary,
                selected.checkmarkAccent > unselected.checkmarkAccent + 20,
                selected.totalAccent < selected.totalPixels / 8,
            ],
            [true, true, true, true, true],
            "Selected: \(selected), unselected: \(unselected)"
        )
    }

    private func renderedSelectionCues(isSelected: Bool) throws -> RenderedSelectionCues {
        let item = ModeSelectionItem(
            id: .voiceToText,
            name: "Voice to Text",
            icon: "waveform",
            summary: "Raw transcription — no Polish",
            isSelected: isSelected,
            isProtected: true
        )
        let controller = NSHostingController(rootView: CommandLedgerSelectionRow(
            item: item,
            onSelect: {}
        )
        .frame(width: 320)
        .environment(\.colorScheme, .light))
        controller.view.frame = NSRect(x: 0, y: 0, width: 320, height: 52)
        controller.view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(
            controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds)
        )
        controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)

        return RenderedSelectionCues(
            leadingAccent: pixelCount(in: 0 ..< 4, bitmap: bitmap, matching: isAccent),
            iconAccent: pixelCount(in: 8 ..< 44, bitmap: bitmap, matching: isAccent),
            titlePrimary: pixelCount(in: 44 ..< 250, bitmap: bitmap, matching: isPrimary),
            checkmarkAccent: pixelCount(in: 280 ..< 320, bitmap: bitmap, matching: isAccent),
            totalAccent: pixelCount(in: 0 ..< 320, bitmap: bitmap, matching: isAccent),
            totalPixels: bitmap.pixelsWide * bitmap.pixelsHigh
        )
    }

    func testHostedEditorKeepsTitleAndFooterInsideVisibleBounds() {
        let model = modeEditorModel()
        let (hosting, window) = hostModeEditor(model)
        defer { window.orderOut(nil) }

        let visibleText = recognizedText(in: hosting)

        XCTAssertEqual(
            ["Add Mode", "Cancel", "Save"].map(visibleText.contains),
            [true, true, true],
            "Visible text: \(visibleText)"
        )
    }

    func testHostedEditorCloseButtonCancelsEditing() {
        let model = modeEditorModel()
        var cancellations = 0
        model.onCancelModeEditor = { cancellations += 1 }
        let (_, window) = hostModeEditor(model)
        defer { window.orderOut(nil) }

        click(at: NSPoint(x: 790, y: 540), in: window)

        XCTAssertEqual(cancellations, 1)
    }

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

    func testHostedModesPaneMoveUpLeadingEdgeRoutesAction() throws {
        let model = SettingsModel()
        model.pane = .modes
        let first = mode(name: "Email")
        let second = mode(name: "Casual")
        let secondID = try XCTUnwrap(second.id)
        model.modes = [first, second]
        model.modeSelection = ModePresentationFactory.projection(
            modes: model.modes,
            selection: .mode(secondID)
        )
        var moved: ModeMoveDirection?
        model.onMoveMode = { _, direction in moved = direction }
        let hosting = hostSettings(model)
        let window = hostInKeyWindow(hosting)
        defer { window.orderOut(nil) }

        click(at: moveUpLeadingEdge, in: window)

        XCTAssertEqual(moved, .up)
    }

    func testHostedModeDetailChromePreservesEveryInteractionState() throws {
        let idle = try renderedModeDetailChrome()
        let hovered = try renderedModeDetailChrome(isHovered: true)
        let focused = try renderedModeDetailChrome(isFocused: true)
        let disabled = try renderedModeDetailChrome(isEnabled: false)
        let increasedContrast = try renderedModeDetailChrome(increaseContrast: true)

        XCTAssertEqual(
            [
                differingPixelCount(idle, hovered) > 40,
                differingPixelCount(idle, focused) > 40,
                differingPixelCount(idle, disabled) > 40,
                differingPixelCount(idle, increasedContrast) > 40,
            ],
            [true, true, true, true]
        )
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
        runModalBounded(window)
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

    private func modeEditorModel() -> SettingsModel {
        let model = SettingsModel()
        model.installed = []
        model.modeEditor = ModeEditorState(
            purpose: .add,
            draft: ModeEditorDraft(
                name: "",
                icon: "wand.and.stars",
                model: "gemma3:4b",
                transformation: .inPlace,
                systemPrompt: "",
                vocabularyText: ""
            )
        )
        return model
    }

    private func hostModeEditor(
        _ model: SettingsModel
    ) -> (NSHostingView<ModeEditorSheet>, NSWindow) {
        let hosting = NSHostingView(rootView: ModeEditorSheet(model: model))
        hosting.frame = NSRect(x: 0, y: 0, width: 820, height: 570)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        NSApp.finishLaunching()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        return (hosting, window)
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

    private func renderedModeDetailChrome(
        isHovered: Bool = false,
        isFocused: Bool = false,
        isEnabled: Bool = true,
        increaseContrast: Bool = false
    ) throws -> NSBitmapImageRep {
        let view = ModeDetailControlChrome(
            surfaces: [
                .init(
                    frame: CGRect(x: 4, y: 4, width: 112, height: 28),
                    isHovered: isHovered,
                    isFocused: isFocused,
                    isEnabled: isEnabled
                ),
            ],
            increaseContrast: increaseContrast
        )
        .frame(width: 120, height: 36)
        .environment(\.colorScheme, .light)
        let controller = NSHostingController(rootView: view)
        controller.view.frame = NSRect(x: 0, y: 0, width: 120, height: 36)
        controller.view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(
            controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds)
        )
        controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
        return bitmap
    }

    private func differingPixelCount(
        _ lhs: NSBitmapImageRep,
        _ rhs: NSBitmapImageRep
    ) -> Int {
        guard lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh else {
            return .max
        }
        var count = 0
        for x in 0 ..< lhs.pixelsWide {
            for y in 0 ..< lhs.pixelsHigh {
                guard
                    let left = lhs.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                    let right = rhs.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                else {
                    continue
                }
                if abs(left.redComponent - right.redComponent) > 0.01
                    || abs(left.greenComponent - right.greenComponent) > 0.01
                    || abs(left.blueComponent - right.blueComponent) > 0.01
                    || abs(left.alphaComponent - right.alphaComponent) > 0.01 {
                    count += 1
                }
            }
        }
        return count
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

    private func recognizedText(in view: NSView) -> String {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            XCTFail("Couldn't create a bitmap for the hosted Mode editor.")
            return ""
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let image = bitmap.cgImage else {
            XCTFail("Couldn't render the hosted Mode editor.")
            return ""
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        do {
            try VNImageRequestHandler(cgImage: image).perform([request])
        } catch {
            XCTFail("Couldn't recognize Mode editor text: \(error)")
            return ""
        }
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    private func pixelCount(
        in pointRange: Range<CGFloat>,
        bitmap: NSBitmapImageRep,
        matching predicate: (NSColor) -> Bool
    ) -> Int {
        let scale = CGFloat(bitmap.pixelsWide) / 320
        let pixelRange = Int(pointRange.lowerBound * scale) ..< Int(pointRange.upperBound * scale)
        return pixelRange.reduce(into: 0) { count, x in
            for y in 0 ..< bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }
                if predicate(color) {
                    count += 1
                }
            }
        }
    }

    private func isAccent(_ color: NSColor) -> Bool {
        (0.65 ... 0.85).contains(color.redComponent)
            && (0.15 ... 0.35).contains(color.greenComponent)
            && color.blueComponent < 0.15
    }

    private func isPrimary(_ color: NSColor) -> Bool {
        color.redComponent < 0.2
            && color.greenComponent < 0.2
            && color.blueComponent < 0.2
    }

    private func click(at point: NSPoint, in window: NSWindow) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            ) else {
                XCTFail("Couldn't create a mouse event for the Mode editor close button.")
                return
            }
            NSApp.sendEvent(event)
        }
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
        runModalBounded(window)
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
