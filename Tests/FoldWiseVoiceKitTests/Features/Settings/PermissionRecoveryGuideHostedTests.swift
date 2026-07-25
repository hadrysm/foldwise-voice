import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class PermissionRecoveryGuideHostedTests: XCTestCase {
    private struct HostedNode {
        let element: AXUIElement
        let identifier: String?
        let value: String?
    }

    func testHostedGuideExposesFullRecoveryAndShortcutFallbackStates() throws {
        let model = makeModel()
        model.onRevealShortcutFallback = {
            PermissionRecoveryWorkflow.reduce(
                state: &model.permissionRecovery,
                action: .revealShortcutFallback
            )
        }
        let window = host(model)
        defer { window.orderOut(nil) }

        let initiallyVisible = identifiers(in: window).contains(
            "permission-recovery.input-monitoring.status"
        )
        try press("permission-recovery.input-monitoring.reveal", in: window)

        XCTAssertEqual(
            try [
                initiallyVisible ? "Visible" : "Hidden",
                node("permission-recovery.microphone.status", in: window).value,
                node("permission-recovery.accessibility.status", in: window).value,
                node("permission-recovery.input-monitoring.status", in: window).value,
            ],
            ["Hidden", "Granted", "Missing", "Optional shortcut fallback"]
        )
    }

    func testHostedGuideRoutesPermissionAndDismissActions() throws {
        let model = makeModel()
        enum RoutedAction: Equatable {
            case request(PermissionKind)
            case settings(PermissionKind)
            case dismiss
        }
        var actions: [RoutedAction] = []
        model.onRevealShortcutFallback = {
            PermissionRecoveryWorkflow.reduce(
                state: &model.permissionRecovery,
                action: .revealShortcutFallback
            )
        }
        model.onRequestPermission = { actions.append(.request($0)) }
        model.onOpenPermissionSettings = { actions.append(.settings($0)) }
        model.onDismissPermissionRecovery = { actions.append(.dismiss) }
        let window = host(model)
        defer { window.orderOut(nil) }

        try press("permission-recovery.accessibility.request", in: window)
        try press("permission-recovery.input-monitoring.reveal", in: window)
        try press("permission-recovery.input-monitoring.settings", in: window)
        try press("permission-recovery.dismiss", in: window)

        XCTAssertEqual(
            actions,
            [.request(.accessibility), .settings(.inputMonitoring), .dismiss]
        )
    }

    func testHostedGuideUsesPermissionSpecificStaleGuidance() throws {
        let model = SettingsModel()
        let unresolved = PermissionRecoverySnapshot(
            microphone: .denied,
            accessibilityGranted: false,
            inputMonitoringGranted: false
        )
        PermissionRecoveryWorkflow.reduce(
            state: &model.permissionRecovery,
            action: .launch(unresolved)
        )
        PermissionRecoveryWorkflow.reduce(
            state: &model.permissionRecovery,
            action: .openedSystemSettings(.microphone)
        )
        PermissionRecoveryWorkflow.reduce(
            state: &model.permissionRecovery,
            action: .returnedFromSystemSettings(unresolved)
        )
        PermissionRecoveryWorkflow.reduce(
            state: &model.permissionRecovery,
            action: .openedSystemSettings(.accessibility)
        )
        PermissionRecoveryWorkflow.reduce(
            state: &model.permissionRecovery,
            action: .returnedFromSystemSettings(unresolved)
        )
        PermissionRecoveryWorkflow.reduce(
            state: &model.permissionRecovery,
            action: .revealShortcutFallback
        )
        PermissionRecoveryWorkflow.reduce(
            state: &model.permissionRecovery,
            action: .openedSystemSettings(.inputMonitoring)
        )
        PermissionRecoveryWorkflow.reduce(
            state: &model.permissionRecovery,
            action: .returnedFromSystemSettings(unresolved)
        )
        let window = host(model)
        defer { window.orderOut(nil) }

        let microphone = try XCTUnwrap(
            node("permission-recovery.microphone.stale", in: window).value
        )
        let accessibility = try XCTUnwrap(
            node("permission-recovery.accessibility.stale", in: window).value
        )
        let inputMonitoring = try XCTUnwrap(
            node("permission-recovery.input-monitoring.stale", in: window).value
        )

        XCTAssertTrue(microphone.contains("enable the current FoldWise Voice"))
        XCTAssertFalse(microphone.contains("remove"))
        XCTAssertTrue(accessibility.contains("remove"))
        XCTAssertTrue(inputMonitoring.contains("remove"))
    }

    private func makeModel() -> SettingsModel {
        let model = SettingsModel()
        PermissionRecoveryWorkflow.reduce(
            state: &model.permissionRecovery,
            action: .launch(
                PermissionRecoverySnapshot(
                    microphone: .authorized,
                    accessibilityGranted: false,
                    inputMonitoringGranted: false
                )
            )
        )
        return model
    }

    private func host(_ model: SettingsModel) -> NSWindow {
        let hosting = NSHostingView(rootView: PermissionRecoveryGuide(model: model))
        hosting.frame = NSRect(x: 0, y: 0, width: 620, height: 560)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Permission recovery hosted test \(UUID().uuidString)"
        window.contentView = hosting
        NSApp.finishLaunching()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        return window
    }

    private func press(_ identifier: String, in window: NSWindow) throws {
        XCTAssertEqual(
            AXUIElementPerformAction(
                try node(identifier, in: window).element,
                kAXPressAction as CFString
            ),
            .success
        )
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private func node(_ identifier: String, in window: NSWindow) throws -> HostedNode {
        let allNodes = try nodes(in: window)
        return try XCTUnwrap(
            allNodes.first { $0.identifier == identifier },
            "Available identifiers: \(allNodes.compactMap(\.identifier))"
        )
    }

    private func identifiers(in window: NSWindow) -> [String] {
        (try? nodes(in: window).compactMap(\.identifier)) ?? []
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
        let node = HostedNode(
            element: root,
            identifier: axString(attribute: kAXIdentifierAttribute, from: root),
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

    private func axAttribute(attribute: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }
}
