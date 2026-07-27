import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class HistoryPaneHostedTests: XCTestCase {
    private struct HostedNode {
        let element: AXUIElement
        let identifier: String?
        let frame: CGRect?
    }

    func testHostedFirstRunHistoryKeepsLocalAssuranceAndDistinctEmptyState() throws {
        let window = host(SettingsModel())
        defer { window.orderOut(nil) }

        XCTAssertEqual(
            try identifiers(in: window).intersection([
                "history.assurance",
                "history.empty.first-run",
                "history.preference.saving",
                "history.preference.retention",
            ]),
            [
                "history.assurance",
                "history.empty.first-run",
                "history.preference.saving",
                "history.preference.retention",
            ]
        )
    }

    func testHostedHistoryRendersSavingAndRetentionAsEqualCells() throws {
        let window = host(SettingsModel())
        defer { window.orderOut(nil) }

        let savingFrame = try XCTUnwrap(node("history.preference.saving", in: window).frame)
        let retentionFrame = try XCTUnwrap(node("history.preference.retention", in: window).frame)

        XCTAssertEqual(savingFrame.width, retentionFrame.width, accuracy: 1)
        XCTAssertEqual(savingFrame.midY, retentionFrame.midY, accuracy: 1)
    }

    func testHostedHistoryKeepsBothPreferenceCellsWhenSavingIsOff() throws {
        let model = SettingsModel()
        model.saveHistory = false
        let window = host(model)
        defer { window.orderOut(nil) }

        XCTAssertEqual(
            try identifiers(in: window).intersection([
                "history.preference.saving",
                "history.preference.retention",
            ]),
            [
                "history.preference.saving",
                "history.preference.retention",
            ]
        )
    }

    func testHostedHistoryMakesSavingOffWithRetainedDataExplicit() throws {
        let model = SettingsModel()
        model.saveHistory = false
        model.historyEntries = [entry()]
        let window = host(model)
        defer { window.orderOut(nil) }

        XCTAssertEqual(
            try identifiers(in: window).intersection([
                "history.saving-off",
                "history.collection",
                "history.utility",
            ]),
            [
                "history.saving-off",
                "history.collection",
                "history.utility",
            ]
        )
    }

    func testHostedHistoryDistinguishesFlaggedOnlyNoResult() throws {
        let model = SettingsModel()
        model.historyEntries = [entry()]
        let window = host(model)
        defer { window.orderOut(nil) }

        let flaggedOnly = try node("history.flagged-only", in: window)
        try requireSuccess(
            "Press Flagged only",
            flaggedOnly.element,
            kAXPressAction as CFString
        )

        try waitForIdentifier("history.empty.no-flagged", in: window)
    }

    func testHostedHistoryDistinguishesSearchNoResult() throws {
        let model = SettingsModel()
        model.historyEntries = [entry()]
        let window = host(model)
        defer { window.orderOut(nil) }

        let search = try node("history.search", in: window)
        try requireSuccess(
            "Focus History search",
            search.element,
            kAXFocusedAttribute as CFString,
            value: kCFBooleanTrue
        )
        try requireSuccess(
            "Enter History search",
            search.element,
            kAXValueAttribute as CFString,
            value: "not present" as CFString
        )
        _ = AXUIElementPerformAction(search.element, kAXConfirmAction as CFString)

        try waitForIdentifier("history.empty.no-results", in: window)
    }

    private func host(_ model: SettingsModel) -> NSWindow {
        _ = model.paneProjections.history(
            search: "",
            flaggedOnly: false,
            in: .init(
                now: Date(),
                calendar: .autoupdatingCurrent,
                locale: .autoupdatingCurrent
            )
        )
        let hosting = NSHostingView(
            rootView: HistoryPane(interface: model.historyPaneInterface)
        )
        hosting.frame = NSRect(x: 0, y: 0, width: 760, height: 600)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "History hosted test \(UUID().uuidString)"
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
            "Missing \(identifier); found \(Set(allNodes.compactMap(\.identifier)).sorted())"
        )
    }

    private func waitForIdentifier(
        _ identifier: String,
        in window: NSWindow,
        timeout: TimeInterval = 1
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            window.contentView?.needsLayout = true
            window.contentView?.layoutSubtreeIfNeeded()
            if try identifiers(in: window).contains(identifier) {
                return
            }
            _ = RunLoop.main.run(
                mode: .default,
                before: min(deadline, Date().addingTimeInterval(0.01))
            )
        } while Date() < deadline
        XCTFail("Timed out waiting for \(identifier)")
    }

    private func requireSuccess(
        _ operation: String,
        _ element: AXUIElement,
        _ action: CFString
    ) throws {
        let result = AXUIElementPerformAction(element, action)
        guard result == .success else {
            throw HostedAccessibilityError(operation: operation, result: result)
        }
    }

    private func requireSuccess(
        _ operation: String,
        _ element: AXUIElement,
        _ attribute: CFString,
        value: CFTypeRef
    ) throws {
        let result = AXUIElementSetAttributeValue(element, attribute, value)
        guard result == .success else {
            throw HostedAccessibilityError(operation: operation, result: result)
        }
    }

    private func identifiers(in window: NSWindow) throws -> Set<String> {
        Set(try nodes(in: window).compactMap(\.identifier))
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
        return [
            HostedNode(
                element: root,
                identifier: axString(attribute: kAXIdentifierAttribute, from: root),
                frame: frame
            ),
        ] + axElements(attribute: kAXChildrenAttribute, from: root).flatMap(axTree)
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
            flagged: false,
            flagReason: nil
        )
    }
}

private struct HostedAccessibilityError: Error, CustomStringConvertible {
    let operation: String
    let result: AXError

    var description: String {
        "\(operation) failed with AX error \(result.rawValue)"
    }
}
