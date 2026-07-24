import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class ContinuousFrameHostedTests: XCTestCase {
    private struct HostedNode {
        let element: AXUIElement
        let identifier: String?
        let role: String?
        let frame: CGRect?
        let isEnabled: Bool?
        let isFocused: Bool?
        let value: String?
    }

    func testHostedFrameAttachesRecoveryAndStatusOnlyToDestinationColumn() throws {
        let model = SettingsModel()
        model.configurationRecoveryMessage = "The configuration file is invalid."
        model.status = "The change could not be saved."
        model.statusIsError = true
        let window = host(model)
        defer { window.orderOut(nil) }

        let titlebar = try node("continuous-frame.titlebar", in: window)
        let navigation = try node("continuous-frame.navigation", in: window)
        let destination = try node("continuous-frame.destination", in: window)
        let recovery = try node("continuous-frame.recovery", in: window)
        let status = try node("continuous-frame.status", in: window)
        let titlebarFrame = try XCTUnwrap(titlebar.frame)
        let navigationFrame = try XCTUnwrap(navigation.frame)
        let destinationFrame = try XCTUnwrap(destination.frame)
        let recoveryFrame = try XCTUnwrap(recovery.frame)
        let statusFrame = try XCTUnwrap(status.frame)

        XCTAssertLessThanOrEqual(titlebarFrame.minX, navigationFrame.minX)
        XCTAssertGreaterThanOrEqual(titlebarFrame.maxX, destinationFrame.maxX)
        XCTAssertGreaterThanOrEqual(recoveryFrame.minX, navigationFrame.maxX)
        XCTAssertGreaterThanOrEqual(statusFrame.minX, navigationFrame.maxX)
    }

    func testHostedGlobalSaveConfirmationIsACompactBottomRightToast() throws {
        let model = SettingsModel()
        var committedOwner: SettingsFeedbackOwner?
        model.onCommit = { owner in
            committedOwner = owner
            model.status = "Saved ✓"
            model.statusOwner = owner
        }
        let window = host(model)
        defer { window.orderOut(nil) }

        XCTAssertEqual(
            AXUIElementPerformAction(
                try node("continuous-frame.sidebar-toggle", in: window).element,
                kAXPressAction as CFString
            ),
            .success
        )
        window.contentView?.layoutSubtreeIfNeeded()
        settleToastAnimation(in: window)

        let destinationFrame = try XCTUnwrap(
            node("continuous-frame.destination", in: window).frame
        )
        let statusFrame = try XCTUnwrap(
            node("continuous-frame.status", in: window).frame
        )

        XCTAssertEqual(committedOwner, .global)
        XCTAssertTrue(model.sidebar.prefersCollapsed)
        XCTAssertLessThanOrEqual(
            statusFrame.width, 240,
            "a save confirmation should not span the destination column"
        )
        XCTAssertLessThanOrEqual(
            statusFrame.height, 48,
            "a save confirmation should not grow into a large panel"
        )
        XCTAssertEqual(
            statusFrame.maxX, destinationFrame.maxX - 16, accuracy: 1,
            "the toast should be inset from the destination's right edge"
        )
        XCTAssertEqual(
            statusFrame.maxY, destinationFrame.maxY - 16, accuracy: 1,
            "the toast should be inset from the destination's bottom edge"
        )
    }

    func testHostedDisablingHistoryShowsACompactBottomRightToast() throws {
        let model = SettingsModel()
        model.pane = .history
        model.saveHistory = true
        var committedOwner: SettingsFeedbackOwner?
        model.onCommit = { owner in
            committedOwner = owner
            model.status = "Saved ✓"
            model.statusOwner = owner
        }
        let window = host(model)
        defer { window.orderOut(nil) }

        let savingPreference = try node("history.preference.saving", in: window)
        let savingToggle = try XCTUnwrap(
            descendants(of: savingPreference.element).first {
                $0.role == kAXCheckBoxRole as String
                    || $0.role == "AXSwitch"
            },
            "The saving preference should expose its switch; found roles "
                + "\(descendants(of: savingPreference.element).compactMap(\.role))"
        )
        XCTAssertEqual(
            AXUIElementPerformAction(savingToggle.element, kAXPressAction as CFString),
            .success
        )
        window.contentView?.layoutSubtreeIfNeeded()
        settleToastAnimation(in: window)

        let destinationFrame = try XCTUnwrap(
            node("continuous-frame.destination", in: window).frame
        )
        let statusFrame = try XCTUnwrap(
            node("continuous-frame.status", in: window).frame
        )

        XCTAssertFalse(model.saveHistory)
        XCTAssertEqual(committedOwner, .global)
        XCTAssertLessThanOrEqual(statusFrame.width, 240)
        XCTAssertLessThanOrEqual(statusFrame.height, 48)
        XCTAssertEqual(statusFrame.maxX, destinationFrame.maxX - 16, accuracy: 1)
        XCTAssertEqual(statusFrame.maxY, destinationFrame.maxY - 16, accuracy: 1)
    }

    func testHostedGlobalToastDoesNotDrawASecondLeadingSuccessStripe() throws {
        let model = SettingsModel()
        model.pane = .modes
        model.status = "Saved ✓"
        model.statusOwner = .global
        let window = host(model)
        defer { window.orderOut(nil) }

        let content = try XCTUnwrap(window.contentView)
        content.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(
            content.bitmapImageRepForCachingDisplay(in: content.bounds)
        )
        content.cacheDisplay(in: content.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsHigh) / content.bounds.height

        XCTAssertLessThan(
            CGFloat(maximumVerticalSuccessRun(in: bitmap)) / scale,
            20,
            "the toast icon may be green, but there should be no full-height green stripe"
        )
    }

    func testHostedGlobalToastRisesFromBelowThenSettlesAtItsCorner() throws {
        let model = SettingsModel()
        model.pane = .modes
        let window = host(model)
        defer { window.orderOut(nil) }

        model.statusOwner = .global
        model.status = "Saved ✓"
        _ = RunLoop.main.run(
            mode: .default,
            before: Date(timeIntervalSinceNow: 0.01)
        )
        window.contentView?.layoutSubtreeIfNeeded()
        let enteringFrame = try XCTUnwrap(
            node("continuous-frame.status", in: window).frame
        )

        settleToastAnimation(in: window)
        let settledFrame = try XCTUnwrap(
            node("continuous-frame.status", in: window).frame
        )

        XCTAssertGreaterThan(
            enteringFrame.maxY,
            settledFrame.maxY + 8,
            "the toast should enter from below and travel upward into its corner"
        )
        XCTAssertLessThan(
            enteringFrame.width,
            settledFrame.width,
            "the toast should gently scale into place while it rises"
        )
    }

    func testHostedRecoveryDisablesOnlyConfigurationOwningDestinations() throws {
        let model = SettingsModel()
        model.configurationRecoveryMessage = "The configuration file is invalid."
        let window = host(model)
        defer { window.orderOut(nil) }

        let states = try SettingsModel.Pane.allCases.map {
            try node(
                "continuous-frame.navigation.\($0.rawValue.lowercased())",
                in: window
            ).isEnabled
        }

        XCTAssertEqual(states, [true, false, false, false, true, false])
    }

    func testHostedRecoveryKeepsHomeAndStatsDestinationContentReadable() throws {
        var windows: [NSWindow] = []
        defer { windows.forEach { $0.orderOut(nil) } }

        let states = try SettingsModel.Pane.allCases.map { pane in
            let model = SettingsModel()
            model.pane = pane
            model.configurationRecoveryMessage = "The configuration file is invalid."
            let window = host(model)
            windows.append(window)
            return try node("continuous-frame.destination", in: window).value
        }

        XCTAssertEqual(
            states,
            ["Available", "Read-only", "Read-only", "Read-only", "Available", "Read-only"]
        )
    }

    func testHostedVoiceToTextSelectionExplainsNextDictation() throws {
        let model = SettingsModel()
        model.pane = .modes
        let window = host(model)
        defer { window.orderOut(nil) }

        XCTAssertEqual(
            try node("modes.inspector.voice-to-text-detail", in: window).value,
            "Voice to Text is selected for the next Dictation session. "
                + "Select a Mode to review or edit its Polish instructions."
        )
    }

    func testHostedVersionFooterRemainsInExpandedAndRailNavigation() throws {
        let expandedModel = SettingsModel()
        let expandedWindow = host(expandedModel)
        defer { expandedWindow.orderOut(nil) }

        let railModel = SettingsModel()
        railModel.sidebar = SidebarPresentation(prefersCollapsed: true)
        let railWindow = host(railModel)
        defer { railWindow.orderOut(nil) }

        XCTAssertEqual(
            [
                try node("continuous-frame.footer", in: expandedWindow).identifier,
                try node("continuous-frame.footer", in: railWindow).identifier,
            ],
            ["continuous-frame.footer", "continuous-frame.footer"]
        )
    }

    func testHostedRecoveryButtonsAcceptKeyboardFocus() throws {
        let model = SettingsModel()
        model.configurationRecoveryMessage = "The configuration file is invalid."
        let window = host(model)
        defer { window.orderOut(nil) }

        let reset = try node("continuous-frame.recovery.reset", in: window)
        XCTAssertEqual(
            AXUIElementSetAttributeValue(
                reset.element,
                kAXFocusedAttribute as CFString,
                kCFBooleanTrue
            ),
            .success
        )

        XCTAssertEqual(
            try node("continuous-frame.recovery.reset", in: window).isFocused,
            true
        )
    }

    func testHostedAppearanceChoicesCrossTheExactContentWidthBoundary() throws {
        let exactBoundaryWindowWidth = 650
            + Double(Theme.sidebarWidth)
            + 1
            + Double(Theme.contentPaddingCompact * 2)
        let horizontalModel = SettingsModel()
        horizontalModel.pane = .settings
        horizontalModel.sidebar.toggle(width: exactBoundaryWindowWidth)
        let horizontalWindow = host(horizontalModel, width: exactBoundaryWindowWidth)
        defer { horizontalWindow.orderOut(nil) }

        let verticalModel = SettingsModel()
        verticalModel.pane = .settings
        verticalModel.sidebar.toggle(width: exactBoundaryWindowWidth - 1)
        let verticalWindow = host(verticalModel, width: exactBoundaryWindowWidth - 1)
        defer { verticalWindow.orderOut(nil) }

        let horizontalFrames = try appearanceFrames(in: horizontalWindow)
        let verticalFrames = try appearanceFrames(in: verticalWindow)

        XCTAssertEqual(Set(horizontalFrames.map(\.midY)).count, 1)
        XCTAssertEqual(Set(verticalFrames.map(\.midX)).count, 1)
    }

    func testHostedSectionFeedbackStaysAttachedToOwningLedger() throws {
        let cases: [(SettingsFeedbackOwner, String)] = [
            (.shortcuts, "settings.shortcuts.feedback"),
            (.input, "settings.input.feedback"),
            (.sound, "settings.sound.feedback"),
            (.appearance, "settings.appearance.feedback"),
        ]
        var windows: [NSWindow] = []
        defer { windows.forEach { $0.orderOut(nil) } }

        for (owner, identifier) in cases {
            let model = SettingsModel()
            model.pane = .settings
            model.status = "The setting could not be saved."
            model.statusIsError = true
            model.statusOwner = owner
            let window = host(model)
            windows.append(window)

            XCTAssertEqual(try node(identifier, in: window).identifier, identifier)
            XCTAssertNil(
                try nodes(in: window).first { $0.identifier == "continuous-frame.status" }
            )
        }
    }

    func testHostedInputLifecycleFeedbackStaysAttachedToInputRoster() throws {
        let builtIn = AudioInputDevice(uid: "built-in", name: "MacBook Microphone")
        let preferred = AudioInputDevice(uid: "usb", name: "Studio Microphone")
        let model = SettingsModel()
        model.pane = .settings
        model.inputState = AudioInputState(
            devices: [builtIn], systemDefault: builtIn,
            preferredUID: preferred.uid, preferredName: preferred.name,
            effectiveDevice: builtIn, pendingDevice: nil,
            status: .fallback(preferred: preferred.name, effective: builtIn.name)
        )
        let window = host(model)
        defer { window.orderOut(nil) }

        let inputLabelFrame = try XCTUnwrap(node(withValue: "INPUT", in: window).frame)
        let lifecycleFrame = try XCTUnwrap(node("settings.input.lifecycle", in: window).frame)
        let soundLabelFrame = try XCTUnwrap(node(withValue: "SOUND", in: window).frame)
        let globalStatus = try nodes(in: window).first {
            $0.identifier == "continuous-frame.status"
        }
        XCTAssertTrue(
            lifecycleFrame.minY >= inputLabelFrame.maxY
                && lifecycleFrame.maxY <= soundLabelFrame.minY
                && globalStatus == nil
        )
    }

    private func appearanceFrames(in window: NSWindow) throws -> [CGRect] {
        try ["system", "light", "dark"].map {
            try XCTUnwrap(node("settings.appearance.\($0)", in: window).frame)
        }
    }

    private func host(_ model: SettingsModel, width: CGFloat = 980) -> NSWindow {
        let hosting = NSHostingView(rootView: SettingsView(model: model))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 720)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Continuous Frame hosted test \(UUID().uuidString)"
        window.contentView = hosting
        NSApp.finishLaunching()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        return window
    }

    private func node(_ identifier: String, in window: NSWindow) throws -> HostedNode {
        let allNodes = try nodes(in: window)
        return try XCTUnwrap(
            allNodes.first { $0.identifier == identifier },
            "Available identifiers: \(allNodes.compactMap(\.identifier))"
        )
    }

    private func node(withValue value: String, in window: NSWindow) throws -> HostedNode {
        let allNodes = try nodes(in: window)
        return try XCTUnwrap(
            allNodes.first { $0.value == value },
            "Available values: \(allNodes.compactMap(\.value))"
        )
    }

    private func nodes(in window: NSWindow) throws -> [HostedNode] {
        let application = AXUIElementCreateApplication(getpid())
        let windows = axElements(attribute: kAXWindowsAttribute, from: application)
        let hostedWindow = try XCTUnwrap(windows.first {
            axString(attribute: kAXTitleAttribute, from: $0) == window.title
        })
        return axTree(root: hostedWindow)
    }

    private func axTree(root: AXUIElement) -> [HostedNode] {
        let position = axPoint(attribute: kAXPositionAttribute, from: root)
        let size = axSize(attribute: kAXSizeAttribute, from: root)
        let frame = position.flatMap { position in
            size.map { CGRect(origin: position, size: $0) }
        }
        let node = HostedNode(
            element: root,
            identifier: axString(attribute: kAXIdentifierAttribute, from: root),
            role: axString(attribute: kAXRoleAttribute, from: root),
            frame: frame,
            isEnabled: axAttribute(attribute: kAXEnabledAttribute, from: root) as? Bool,
            isFocused: axAttribute(attribute: kAXFocusedAttribute, from: root) as? Bool,
            value: axString(attribute: kAXValueDescriptionAttribute, from: root)
                ?? axString(attribute: kAXValueAttribute, from: root)
        )
        return [node] + axElements(attribute: kAXChildrenAttribute, from: root).flatMap(axTree)
    }

    private func descendants(of element: AXUIElement) -> [HostedNode] {
        axElements(attribute: kAXChildrenAttribute, from: element).flatMap(axTree)
    }

    private func settleToastAnimation(in window: NSWindow) {
        let deadline = Date(timeIntervalSinceNow: 0.25)
        repeat {
            _ = RunLoop.main.run(
                mode: .default,
                before: min(deadline, Date(timeIntervalSinceNow: 0.01))
            )
        } while Date() < deadline
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private func maximumVerticalSuccessRun(in bitmap: NSBitmapImageRep) -> Int {
        var maximum = 0
        for x in 0 ..< bitmap.pixelsWide {
            var run = 0
            for y in 0 ..< bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                else {
                    run = 0
                    continue
                }
                let isSuccess = color.greenComponent > 0.35
                    && color.greenComponent > color.redComponent * 1.6
                    && color.greenComponent > color.blueComponent * 1.35
                if isSuccess {
                    run += 1
                    maximum = max(maximum, run)
                } else {
                    run = 0
                }
            }
        }
        return maximum
    }

    private func axElements(attribute: String, from element: AXUIElement) -> [AXUIElement] {
        axAttribute(attribute: attribute, from: element) as? [AXUIElement] ?? []
    }

    private func axString(attribute: String, from element: AXUIElement) -> String? {
        axAttribute(attribute: attribute, from: element) as? String
    }

    private func axPoint(attribute: String, from element: AXUIElement) -> CGPoint? {
        guard let value = accessibilityValue(attribute: attribute, from: element),
              AXValueGetType(value) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    private func axSize(attribute: String, from element: AXUIElement) -> CGSize? {
        guard let value = accessibilityValue(attribute: attribute, from: element),
              AXValueGetType(value) == .cgSize else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    private func accessibilityValue(
        attribute: String,
        from element: AXUIElement
    ) -> AXValue? {
        guard let value = axAttribute(attribute: attribute, from: element),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXValue.self)
    }

    private func axAttribute(attribute: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }
}
