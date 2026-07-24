import AppKit
import ApplicationServices
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class ModeSelectionToastHostedTests: XCTestCase {
    func testDictationSelectionConfirmationRendersAsCompactBottomTrailingToast() throws {
        let model = SettingsModel()
        model.pane = .modes
        model.status = "Dictation selection updated ✓"
        model.statusIsError = false
        model.statusOwner = .global

        let window = host(model)
        defer { window.orderOut(nil) }

        let (toast, _) = try node("continuous-frame.status", in: window)
        let (destination, _) = try node("continuous-frame.destination", in: window)
        let toastFrame = try XCTUnwrap(toast.frame)
        let destinationFrame = try XCTUnwrap(destination.frame)

        XCTAssertLessThanOrEqual(toastFrame.width, 360)
        XCTAssertLessThanOrEqual(toastFrame.height, 64)
        XCTAssertLessThanOrEqual(abs(toastFrame.maxX - destinationFrame.maxX), 40)
        XCTAssertLessThanOrEqual(abs(toastFrame.maxY - destinationFrame.maxY), 40)
    }

    private func host(_ model: SettingsModel) -> NSWindow {
        let hosting = NSHostingView(rootView: SettingsView(model: model))
        hosting.frame = NSRect(x: 0, y: 0, width: 980, height: 720)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Mode selection toast hosted test \(UUID().uuidString)"
        window.contentView = hosting
        NSApp.finishLaunching()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        return window
    }

    private func node(
        _ identifier: String,
        in window: NSWindow
    ) throws -> (node: HostedNode, windowFrame: CGRect) {
        let application = AXUIElementCreateApplication(getpid())
        let windows = axElements(attribute: kAXWindowsAttribute, from: application)
        let hostedWindow = try XCTUnwrap(windows.first {
            axString(attribute: kAXTitleAttribute, from: $0) == window.title
        })
        let hostedWindowNode = axTree(root: hostedWindow)
        return (
            try XCTUnwrap(hostedWindowNode.first { $0.identifier == identifier }),
            try XCTUnwrap(hostedWindowNode.first?.frame)
        )
    }

    private func axTree(root: AXUIElement) -> [HostedNode] {
        let position = axPoint(attribute: kAXPositionAttribute, from: root)
        let size = axSize(attribute: kAXSizeAttribute, from: root)
        let frame = position.flatMap { position in
            size.map { CGRect(origin: position, size: $0) }
        }
        let node = HostedNode(
            identifier: axString(attribute: kAXIdentifierAttribute, from: root),
            frame: frame
        )
        return [node] + axElements(attribute: kAXChildrenAttribute, from: root)
            .flatMap(axTree(root:))
    }

    private func axElements(attribute: String, from element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let values = value as? [AXUIElement] else {
            return []
        }
        return values
    }

    private func axString(attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else {
            return nil
        }
        return value as? String
    }

    private func axPoint(attribute: String, from element: AXUIElement) -> CGPoint? {
        guard let value = axValue(attribute: attribute, from: element),
              AXValueGetType(value) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    private func axSize(attribute: String, from element: AXUIElement) -> CGSize? {
        guard let value = axValue(attribute: attribute, from: element),
              AXValueGetType(value) == .cgSize else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    private func axValue(attribute: String, from element: AXUIElement) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else {
            return nil
        }
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXValue.self)
    }
}

private struct HostedNode {
    let identifier: String?
    let frame: CGRect?
}
