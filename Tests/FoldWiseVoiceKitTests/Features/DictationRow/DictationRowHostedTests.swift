import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class DictationRowHostedTests: XCTestCase {
    private struct KeyInput {
        let code: UInt16
        let characters: String
        let modifiers: NSEvent.ModifierFlags
    }

    private struct RenderedColorCounts {
        let accent: Int
        let canvas: Int
    }

    func testHostedHomeAndHistoryRowsKeepTheSameFortyFourPointGeometry() {
        let presentation = DictationRowPresentation(
            entry: entry(),
            calendar: utcCalendar()
        )
        let home = hostedRow(presentation: presentation, moreCapabilities: nil)
        let history = hostedRow(
            presentation: presentation,
            moreCapabilities: DictationRowMoreCapabilities(
                canCopyRaw: true,
                polishModes: [.init(id: .random(), name: "Clean")]
            )
        )

        XCTAssertEqual([home.fittingSize.height, history.fittingSize.height], [44, 44])
    }

    func testHostedRowRendersCanonicalAccentIngress() throws {
        XCTAssertGreaterThan(try renderedColorCounts(focused: false).accent, 80)
    }

    func testHostedFocusedRowRendersCanonicalAccentRing() throws {
        let resting = try renderedColorCounts(focused: false)
        let focused = try renderedColorCounts(focused: true)

        XCTAssertGreaterThan(focused.accent, resting.accent + 200)
    }

    func testHostedFocusedRowSeparatesRingWithCanvasGap() throws {
        let resting = try renderedColorCounts(focused: false)
        let focused = try renderedColorCounts(focused: true)

        XCTAssertGreaterThan(focused.canvas, resting.canvas + 200)
    }

    func testHostedHistoryIgnoresUnrelatedModelPublicationForProjection() {
        let model = SettingsModel()
        model.historyEntries = [entry()]
        var executionCount = 0
        let cache = HistoryProjectionCache { input in
            executionCount += 1
            return HistoryProjection.project(
                input,
                now: Date(timeIntervalSince1970: 1_783_512_000),
                calendar: self.utcCalendar(),
                locale: Locale(identifier: "en_US")
            )
        }
        let hosting = NSHostingView(
            rootView: HistoryPane(model: model, projectionCache: cache)
                .frame(width: 800)
        )
        hosting.layoutSubtreeIfNeeded()
        let initialExecutions = executionCount

        model.customModel = "unrelated publication"
        hosting.needsLayout = true
        hosting.layoutSubtreeIfNeeded()

        XCTAssertEqual([initialExecutions, executionCount], [1, 1])
    }

    func testHostedHistoryRefreshesRelativeHeadersWhenTheCalendarDayChanges() throws {
        let model = SettingsModel()
        model.historyEntries = [entry()]
        let notificationCenter = NotificationCenter()
        let calendar = utcCalendar()
        var currentNow = Date(timeIntervalSince1970: 1_783_512_000)
        var projectedHeaders: [[String]] = []
        let cache = HistoryProjectionCache(
            now: { currentNow },
            calendar: calendar,
            project: { input in
                let projection = HistoryProjection.project(
                    input,
                    now: currentNow,
                    calendar: calendar,
                    locale: Locale(identifier: "en_US")
                )
                projectedHeaders.append(projection.sections.map(\.header))
                return projection
            }
        )
        let hosting = NSHostingView(
            rootView: HistoryPane(
                model: model,
                projectionCache: cache,
                notificationCenter: notificationCenter
            )
            .frame(width: 800)
        )
        hosting.layoutSubtreeIfNeeded()

        currentNow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: currentNow))
        notificationCenter.post(name: .NSCalendarDayChanged, object: nil)
        hosting.needsLayout = true
        hosting.layoutSubtreeIfNeeded()

        XCTAssertEqual(projectedHeaders, [["Today"], ["Yesterday"]])
    }

    func testHostedHomeRowKeyboardTraversalReachesCopyAndFlag() {
        let interaction = DictationRowInteractionState(hasMore: false)
        interaction.setFocused(.row)
        let hosting = NSHostingView(rootView: DictationRowContent(
            presentation: DictationRowPresentation(entry: entry(), calendar: utcCalendar()),
            moreCapabilities: nil,
            onCommand: { _ in },
            interactionState: interaction,
            copyFeedback: DictationRowCopyFeedback()
        ))
        let window = hostInKeyWindow(hosting)

        sendKeys([tab, tab], to: window)
        window.orderOut(nil)

        let actionsRevealed = DictationRowInteraction.actionsRevealed(
            isHovered: interaction.isHovered,
            hasFocus: interaction.hasVisibleFocusIndicator,
            isCopyConfirmed: false
        )
        XCTAssertEqual(
            [
                interaction.focusedTarget == .flag,
                interaction.hasVisibleFocusIndicator,
                actionsRevealed,
            ],
            [true, true, true]
        )
    }

    func testHostedHistoryRowKeyboardTraversalReachesMore() {
        let interaction = DictationRowInteractionState(hasMore: true)
        interaction.setFocused(.row)
        let hosting = NSHostingView(rootView: DictationRowContent(
            presentation: DictationRowPresentation(entry: entry(), calendar: utcCalendar()),
            moreCapabilities: DictationRowMoreCapabilities(
                canCopyRaw: true,
                polishModes: [.init(id: .random(), name: "Clean")]
            ),
            onCommand: { _ in },
            interactionState: interaction,
            copyFeedback: DictationRowCopyFeedback()
        ))
        let window = hostInKeyWindow(hosting)

        sendKeys([tab, tab, tab], to: window)
        window.orderOut(nil)

        XCTAssertEqual(
            [interaction.focusedTarget == .more, interaction.hasVisibleFocusIndicator],
            [true, true]
        )
    }

    private func hostedRow(
        presentation: DictationRowPresentation,
        moreCapabilities: DictationRowMoreCapabilities?
    ) -> NSHostingView<DictationRow> {
        let hosting = NSHostingView(rootView: DictationRow(
            presentation: presentation,
            moreCapabilities: moreCapabilities,
            onCommand: { _ in }
        ))
        hosting.frame = NSRect(x: 0, y: 0, width: 700, height: 44)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    private func renderedColorCounts(focused: Bool) throws -> RenderedColorCounts {
        let interaction = DictationRowInteractionState(hasMore: false)
        if focused {
            interaction.setFocused(.row)
        }
        let controller = NSHostingController(rootView: DictationRowContent(
            presentation: DictationRowPresentation(entry: entry(), calendar: utcCalendar()),
            moreCapabilities: nil,
            onCommand: { _ in },
            interactionState: interaction,
            copyFeedback: DictationRowCopyFeedback()
        )
        .frame(width: 700, height: 44)
        .environment(\.colorScheme, .light))
        controller.view.frame = NSRect(x: 0, y: 0, width: 700, height: 44)
        controller.view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(
            controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds)
        )
        controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)

        var accentCount = 0
        var canvasCount = 0
        for y in 0 ..< bitmap.pixelsHigh {
            for x in 0 ..< bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }
                if (0.65 ... 0.85).contains(color.redComponent),
                   (0.15 ... 0.35).contains(color.greenComponent),
                   color.blueComponent < 0.15 {
                    accentCount += 1
                }
                if abs(color.redComponent - 247 / 255) < 0.015,
                   abs(color.greenComponent - 243 / 255) < 0.015,
                   abs(color.blueComponent - 236 / 255) < 0.015 {
                    canvasCount += 1
                }
            }
        }
        return RenderedColorCounts(accent: accentCount, canvas: canvasCount)
    }

    private func hostInKeyWindow(_ hosting: NSHostingView<some View>) -> NSWindow {
        hosting.frame = NSRect(x: 0, y: 0, width: 700, height: 44)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        NSApp.finishLaunching()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        _ = window.makeFirstResponder(hosting)
        hosting.layoutSubtreeIfNeeded()
        return window
    }

    private func hostingLayout(_ window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private var tab: KeyInput {
        KeyInput(code: 48, characters: "\t", modifiers: [])
    }

    private func sendKeys(
        _ keys: [KeyInput],
        to window: NSWindow
    ) {
        DispatchQueue.main.async {
            for key in keys {
                guard let event = NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: key.modifiers,
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    characters: key.characters,
                    charactersIgnoringModifiers: key.characters,
                    isARepeat: false,
                    keyCode: key.code
                ) else {
                    continue
                }
                NSApp.sendEvent(event)
            }
            NSApp.abortModal()
        }
        NSApp.runModal(for: window)
        hostingLayout(window)
    }

    private func entry() -> HistoryEntry {
        HistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_783_499_700),
            text: "Displayed words",
            rawText: "raw words",
            isPolished: true,
            modeName: "Clean",
            wordCount: 2,
            sourceApp: nil,
            durationMs: nil,
            flagged: true,
            flagReason: nil
        )
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }
}
