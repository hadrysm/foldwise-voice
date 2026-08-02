import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

/// The inspector's primary slot is a focus stop even when the state it reports
/// has no control to press, so a completed download can move focus onto it. That
/// focusability must not leak to the pointer: making static text first responder
/// on a click paints the system focus ring around a word nobody can press. These
/// host the pane for real and click it for real, then read the responder back:
/// the ring AppKit paints for a first responder never reaches an offscreen
/// render, so the responder is as close to those pixels as a test can get.
@MainActor
final class ModelsInspectorStatusFocusTests: XCTestCase {
    /// The inspector's "Selected" label, at the hosted geometry below.
    private let selectedLabel = CGPoint(x: 687, y: 299)

    func testClickingTheInspectorsSelectedLabelDoesNotFocusIt() throws {
        let pane = HostedPane()
        defer { pane.tearDown() }

        try pane.assertAccentPixelsAroundSelectedLabel()
        XCTAssertFalse(pane.isFocusedSomewhere, "the fixture starts with nothing focused")

        pane.click(at: selectedLabel)

        XCTAssertFalse(
            pane.isFocusedSomewhere,
            "clicking the inspector's static state text made it first responder, which is "
                + "what paints the stray focus ring around the word"
        )
    }

    /// The counterpart to the test above: refusing the pointer must not cost the
    /// inspector the focus move a finished selection makes, nor leave that move
    /// invisible. The ring is counted in pixels because the app draws its own —
    /// the system ring this replaces never reaches an offscreen render.
    func testAFinishedSelectionRingsTheInspectorsSelectedLabel() throws {
        let pane = HostedPane()
        defer { pane.tearDown() }

        let unfocused = try pane.accentPixelsAroundSelectedLabel()
        pane.completeSelection(of: "parakeet-v3")
        let focused = try pane.accentPixelsAroundSelectedLabel()

        XCTAssertGreaterThan(
            focused, unfocused + 40,
            "nothing marks where focus landed once the selection finished"
        )
    }

    /// Hosts the pane with one available, selected Speech model, so the
    /// inspector's primary slot is the static "Selected" label.
    @MainActor
    private final class HostedPane {
        private let hosting: NSHostingView<ModelsCombinedPane>
        private let window: NSWindow
        private let model = SettingsModel()

        init() {
            model.applyASRLifecycleSnapshot(Self.snapshot(operation: nil))
            model.installed = []
            hosting = NSHostingView(rootView: ModelsCombinedPane(
                interface: model.modelsPaneInterface
            ))
            hosting.appearance = NSAppearance(named: .darkAqua)
            hosting.frame = NSRect(x: 0, y: 0, width: 1200, height: 1000)
            window = NSWindow(
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
        }

        func tearDown() {
            window.orderOut(nil)
        }

        /// Whether anything inside the pane holds keyboard focus. SwiftUI parks
        /// focus on a proxy view of its own; an unfocused pane leaves the window
        /// itself as the responder.
        var isFocusedSomewhere: Bool {
            !(window.firstResponder is NSWindow)
        }

        /// Runs a selection to completion, which is the transition that moves
        /// focus to the inspector's primary slot.
        func completeSelection(of modelID: String) {
            model.applyASRLifecycleSnapshot(
                Self.snapshot(operation: .switching(modelID: modelID))
            )
            settle()
            model.applyASRLifecycleSnapshot(Self.snapshot(operation: nil))
            settle()
        }

        func click(at point: CGPoint) {
            let windowPoint = hosting.convert(NSPoint(x: point.x, y: point.y), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                guard let event = NSEvent.mouseEvent(
                    with: type,
                    location: windowPoint,
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 1,
                    pressure: 1
                ) else {
                    XCTFail("Couldn't create a mouse event for the Models inspector.")
                    return
                }
                NSApp.sendEvent(event)
            }
            settle()
        }

        /// Counts the accent pixels in the box the "Selected" label and any ring
        /// around it share. The label's own glyphs are in there too, which is
        /// what makes it a usable landmark: an empty box means the label moved,
        /// not that the ring is missing.
        func accentPixelsAroundSelectedLabel() throws -> Int {
            let bitmap = try XCTUnwrap(
                hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
            )
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / hosting.bounds.width
            var accent = 0
            for x in Int(640 * scale) ... Int(740 * scale) {
                for y in Int(283 * scale) ... Int(316 * scale) {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                    else { continue }
                    if color.redComponent > 0.45,
                       color.redComponent - color.blueComponent > 0.2 {
                        accent += 1
                    }
                }
            }
            return accent
        }

        /// Fails unless the probed point still lands on the "Selected" label, so
        /// a layout change retires the probe loudly rather than quietly clicking
        /// empty canvas.
        func assertAccentPixelsAroundSelectedLabel() throws {
            XCTAssertGreaterThan(
                try accentPixelsAroundSelectedLabel(), 20,
                "the inspector's \"Selected\" label moved away from the probed point"
            )
        }

        private func settle() {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            hosting.layoutSubtreeIfNeeded()
        }

        private static func snapshot(
            operation: ASRModelLifecycleOperation?
        ) -> ASRModelLifecycleSnapshot {
            ASRModelLifecycleSnapshot(
                models: ASRModelCatalog.entries.map {
                    ASRModelDescriptor(entry: $0, isAvailable: $0.id == "parakeet-v3")
                },
                storedSelection: "parakeet-v3",
                effectiveSelection: "parakeet-v3",
                recovery: nil,
                operation: operation,
                failure: nil,
                isDictationBlocked: false
            )
        }
    }
}
