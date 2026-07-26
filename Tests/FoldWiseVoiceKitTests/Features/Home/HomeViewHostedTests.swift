import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class HomeViewHostedTests: XCTestCase {
    private struct HostedNode {
        let identifier: String?
        let position: CGPoint?
    }

    func testHostedHomeRendersFourMetricsAcrossAtTheBreakpoint() throws {
        let window = hostHome(width: 940)
        defer { window.orderOut(nil) }

        XCTAssertEqual(try metricRowCount(in: window), 1)
    }

    func testHostedHomeRendersMetricsTwoByTwoBelowTheBreakpoint() throws {
        let window = hostHome(width: 939)
        defer { window.orderOut(nil) }

        XCTAssertEqual(try metricRowCount(in: window), 2)
    }

    func testHostedHomeExposesFourMetrics() throws {
        let window = hostHome(width: 940)
        defer { window.orderOut(nil) }

        XCTAssertEqual(try metricNodes(in: window).count, 4)
    }

    func testHostedHomeRefreshesRelativeHeadersWhenTheCalendarDayChanges() throws {
        let calendar = try utcCalendar()
        var currentNow = Date(timeIntervalSince1970: 1_783_512_000)
        let store = PaneProjectionStore()
        let model = SettingsModel(
            panePerformance: PaneNavigationPerformance(),
            paneProjections: store
        )
        model.historyEntries = [entry(createdAt: currentNow.addingTimeInterval(-60 * 60))]
        let notificationCenter = NotificationCenter()
        let hosting = NSHostingView(rootView: HomeView(
            interface: model.homePaneInterface,
            now: { currentNow },
            calendar: { calendar },
            locale: Locale(identifier: "en_US"),
            notificationCenter: notificationCenter
        ))
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 640)
        hosting.layoutSubtreeIfNeeded()
        let initial = try XCTUnwrap(store.completedHome)

        currentNow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: currentNow))
        notificationCenter.post(name: .NSCalendarDayChanged, object: nil)
        hosting.needsLayout = true
        hosting.layoutSubtreeIfNeeded()
        let refreshed = try XCTUnwrap(store.completedHome)

        XCTAssertEqual(
            [
                initial.value.recent.sections.map(\.header),
                refreshed.value.recent.sections.map(\.header),
            ],
            [["Today"], ["Yesterday"]]
        )
    }

    private func entry(createdAt: Date) -> HistoryEntry {
        HistoryEntry(
            id: UUID(),
            createdAt: createdAt,
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

    private func utcCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        return calendar
    }

    private func hostHome(width: CGFloat) -> NSWindow {
        let model = SettingsModel()
        model.windowWidth = width
        let hosting = NSHostingView(
            rootView: HomeView(interface: model.homePaneInterface)
        )
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 640)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Home hosted test \(UUID().uuidString)"
        window.contentView = hosting
        NSApp.finishLaunching()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        return window
    }

    private func metricRowCount(in window: NSWindow) throws -> Int {
        Set(try metricNodes(in: window).compactMap {
            $0.position.map { Int($0.y.rounded()) }
        }).count
    }

    private func metricNodes(in window: NSWindow) throws -> [HostedNode] {
        try nodes(in: window).filter {
            $0.identifier?.hasPrefix("home.metric.") == true
        }
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
            identifier: axString(attribute: kAXIdentifierAttribute, from: root),
            position: axPoint(attribute: kAXPositionAttribute, from: root)
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
        guard let value = axAttribute(attribute: attribute, from: element),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let positionValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(positionValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(positionValue, .cgPoint, &point) ? point : nil
    }

    private func axAttribute(attribute: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }
}
