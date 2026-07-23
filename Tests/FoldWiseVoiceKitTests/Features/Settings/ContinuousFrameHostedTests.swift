import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class ContinuousFrameHostedTests: XCTestCase {
    private struct HostedNode {
        let element: AXUIElement
        let identifier: String?
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
        let horizontalModel = SettingsModel()
        horizontalModel.pane = .settings
        horizontalModel.sidebar.toggle(width: 913)
        let horizontalWindow = host(horizontalModel, width: 913)
        defer { horizontalWindow.orderOut(nil) }

        let verticalModel = SettingsModel()
        verticalModel.pane = .settings
        verticalModel.sidebar.toggle(width: 912)
        let verticalWindow = host(verticalModel, width: 912)
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
            frame: frame,
            isEnabled: axAttribute(attribute: kAXEnabledAttribute, from: root) as? Bool,
            isFocused: axAttribute(attribute: kAXFocusedAttribute, from: root) as? Bool,
            value: axString(attribute: kAXValueDescriptionAttribute, from: root)
                ?? axString(attribute: kAXValueAttribute, from: root)
        )
        return [node] + axElements(attribute: kAXChildrenAttribute, from: root).flatMap(axTree)
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
