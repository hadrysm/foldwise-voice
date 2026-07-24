import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class AppearancePropagationHostedTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("foldwise-hosted-appearance-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testLiveSystemLightDarkChangesUpdateHostedShellAndBadgeTokensTogether() throws {
        let (mainWindow, mainHosting) = hostMainWindow()
        let (badgePanel, badgeHosting) = hostBadge()
        let previousAppearance = NSApp.appearance
        defer {
            NSApp.appearance = previousAppearance
            mainWindow.orderOut(nil)
            badgePanel.orderOut(nil)
        }
        let config = Config.defaultConfig(path: directory.appendingPathComponent("config.json"))
        let reactor = AppearanceReactor(config: config)
        let systemSample = try sampleProductionSurfaces(
            mainHosting: mainHosting,
            badgeHosting: badgeHosting
        )

        try config.setAppearance(.light)
        let lightSample = try sampleProductionSurfaces(
            mainHosting: mainHosting,
            badgeHosting: badgeHosting
        )

        try config.setAppearance(.dark)
        let darkSample = try sampleProductionSurfaces(
            mainHosting: mainHosting,
            badgeHosting: badgeHosting
        )

        withExtendedLifetime(reactor) {}
        XCTAssertTrue(
            pair(systemSample, matches: lightSample)
                || pair(systemSample, matches: darkSample)
        )
        let lightMainWindow = try components(of: lightSample.mainWindow)
        let darkMainWindow = try components(of: darkSample.mainWindow)
        let lightBadge = try components(of: lightSample.badge)
        let darkBadge = try components(of: darkSample.badge)
        XCTAssertGreaterThan(lightMainWindow.red - darkMainWindow.red, 0.8)
        XCTAssertGreaterThan(lightMainWindow.green - darkMainWindow.green, 0.8)
        XCTAssertGreaterThan(lightMainWindow.blue - darkMainWindow.blue, 0.8)
        XCTAssertGreaterThan(lightBadge.red - darkBadge.red, 0.8)
        XCTAssertGreaterThan(lightBadge.green - darkBadge.green, 0.8)
        XCTAssertGreaterThan(lightBadge.blue - darkBadge.blue, 0.8)
    }

    private func hostMainWindow() -> (NSWindow, NSHostingView<SettingsView>) {
        let hosting = NSHostingView(rootView: SettingsView(model: SettingsModel()))
        hosting.frame = NSRect(x: 0, y: 0, width: 980, height: 720)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderFront(nil)
        return (window, hosting)
    }

    private func hostBadge() -> (BadgePanel, NSHostingView<BadgeView>) {
        let badge = BadgeView(
            model: BadgeModel(),
            onHover: { _ in },
            onClick: {},
            onChangeMode: {},
            onRecord: {},
            onOpenApp: {}
        )
        let hosting = NSHostingView(rootView: badge)
        hosting.frame = NSRect(x: 0, y: 0, width: 88, height: Theme.badgeHeight)
        let panel = BadgePanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.contentView = hosting
        panel.orderFront(nil)
        return (panel, hosting)
    }

    private func sampleProductionSurfaces(
        mainHosting: NSHostingView<SettingsView>,
        badgeHosting: NSHostingView<BadgeView>
    ) throws -> (mainWindow: NSColor, badge: NSColor) {
        let mainWindowColor = try sample(
            in: mainHosting,
            at: CGPoint(x: 900, y: 710)
        )
        let badgeColor = try sample(
            in: badgeHosting,
            at: CGPoint(x: 10, y: Theme.badgeHeight / 2)
        )
        return (mainWindowColor, badgeColor)
    }

    private func sample(in hosting: NSView, at point: CGPoint) throws -> NSColor {
        hosting.needsLayout = true
        hosting.needsDisplay = true
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let representation = try XCTUnwrap(
            hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
        )
        hosting.cacheDisplay(in: hosting.bounds, to: representation)
        let scale = CGFloat(representation.pixelsWide) / hosting.bounds.width
        return try XCTUnwrap(
            representation.colorAt(
                x: Int(point.x * scale),
                y: Int(point.y * scale)
            )
        )
    }

    private func pair(
        _ lhs: (mainWindow: NSColor, badge: NSColor),
        matches rhs: (mainWindow: NSColor, badge: NSColor)
    ) -> Bool {
        color(lhs.mainWindow, matches: rhs.mainWindow)
            && color(lhs.badge, matches: rhs.badge)
    }

    private func components(of color: NSColor) throws -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let color = try XCTUnwrap(color.usingColorSpace(.sRGB))
        return (color.redComponent, color.greenComponent, color.blueComponent)
    }

    private func color(_ actual: NSColor, matches expected: NSColor) -> Bool {
        guard let actual = actual.usingColorSpace(.sRGB),
              let expected = expected.usingColorSpace(.sRGB) else { return false }
        // AppKit's cached display performs device-color conversion; allow one
        // quantization step plus that conversion while still distinguishing
        // every canonical Light and Dark sample.
        let tolerance = 4.0 / 255
        return abs(actual.redComponent - expected.redComponent) <= tolerance
            && abs(actual.greenComponent - expected.greenComponent) <= tolerance
            && abs(actual.blueComponent - expected.blueComponent) <= tolerance
    }
}
