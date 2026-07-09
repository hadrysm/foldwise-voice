// The sidebar-toggle glyph shares the titlebar row with the macOS window
// controls: its vertical center matches the traffic lights', and it stays
// small enough to read as their peer rather than a second, larger control on
// a row of its own. Renders the real SettingsView inside the real main-window
// chrome (SettingsController.makeMainWindow) and measures the glyph's pixels
// against the close button's actual frame.

import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

final class TitlebarAlignmentTests: XCTestCase {
    /// Horizontal strip the glyph lives in, in points from the window's left
    /// edge: right of the traffic lights (~62pt), left of the "FoldWise
    /// Voice" title (~115pt).
    private static let glyphColumns: ClosedRange<CGFloat> = 64 ... 110

    @MainActor
    func testSidebarToggleGlyphSharesTheTrafficLightRowAndStaysSmall() throws {
        let hosting = NSHostingController(
            rootView: SettingsView(model: SettingsModel())
        )
        let win = SettingsController.makeMainWindow(contentViewController: hosting)
        let content = try XCTUnwrap(win.contentView)
        content.layoutSubtreeIfNeeded()

        // Where AppKit actually put the traffic lights, from the window's top.
        let close = try XCTUnwrap(win.standardWindowButton(.closeButton))
        let closeFrame = close.convert(close.bounds, to: nil)
        let lightsCenter = win.frame.height - closeFrame.midY

        // Search the titlebar band around the lights' row. The band is tall
        // enough to catch a mis-centered glyph, short enough to never reach
        // sidebar content below the bar.
        let rows = max(0, lightsCenter - 26) ... lightsCenter + 26
        let rep = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / content.bounds.width

        func sRGB(_ x: CGFloat, _ y: CGFloat) -> NSColor? {
            rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB)
        }
        // The bar background, sampled on the lights' row just left of where
        // the glyph can start (the glyph never reaches x=65).
        let bg = try XCTUnwrap(sRGB(65, lightsCenter))
        func isGlyph(_ color: NSColor) -> Bool {
            max(
                abs(color.redComponent - bg.redComponent),
                abs(color.greenComponent - bg.greenComponent),
                abs(color.blueComponent - bg.blueComponent)
            ) > 0.12
        }

        // Bounding box of every pixel that contrasts with the bar background.
        var minY = CGFloat.infinity
        var maxY = -CGFloat.infinity
        for y in stride(from: rows.lowerBound, through: rows.upperBound, by: 1 / scale) {
            for x in stride(
                from: Self.glyphColumns.lowerBound,
                through: Self.glyphColumns.upperBound,
                by: 1 / scale
            ) {
                guard let color = sRGB(x, y), isGlyph(color) else { continue }
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }

        XCTAssertTrue(
            minY.isFinite,
            "no glyph pixels within ±26pt of the traffic-light row "
                + "(lights center \(lightsCenter)pt from top) — the toggle is not next to them"
        )
        guard minY.isFinite else { return }
        let center = (minY + maxY) / 2
        XCTAssertEqual(
            center, lightsCenter, accuracy: 1.5,
            "glyph center \(center)pt from top; traffic lights at \(lightsCenter)pt — not the same row"
        )
        XCTAssertLessThanOrEqual(
            maxY - minY, 17.5,
            "glyph is \(maxY - minY)pt tall — should stay small next to the 12pt traffic lights"
        )
    }
}
