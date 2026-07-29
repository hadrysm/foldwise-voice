import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

/// The Live chip is the only signal that a Speech model streams once the clause
/// left `fit`, and it is invisible to the accessibility tree by design. These
/// render it for real and read the pixels back, so "the chip is there" is an
/// observation rather than an assumption.
@MainActor
final class ModelsLiveChipHostedTests: XCTestCase {
    /// Compared against the bare canvas, so the assertion cannot pass just
    /// because the pixel predicate is too generous.
    func testTheChipPaintsAccentPixelsTheBareCanvasDoesNot() throws {
        let withChip = try accentPixels(in: try renderedChip())
        let withoutChip = try accentPixels(in: try renderedCanvasOnly())

        XCTAssertEqual(withoutChip, 0)
        XCTAssertGreaterThan(withChip, 20)
    }

    /// A tinted capsule, not a solid one: the fill has to stay closer to the
    /// canvas behind it than to the accent stroke drawn on top.
    func testTheChipFillIsTintedRatherThanSolidAccent() throws {
        let bitmap = try renderedChip()
        let scale = CGFloat(bitmap.pixelsWide) / chipSize.width
        // Just inside the leading edge, between the capsule border and glyph.
        let fill = try XCTUnwrap(
            bitmap.colorAt(x: Int(2 * scale), y: bitmap.pixelsHigh / 2)?
                .usingColorSpace(.sRGB)
        )
        let canvas = try resolved(Theme.canvas)
        let accent = try resolved(Theme.accent)

        XCTAssertLessThan(distance(fill, canvas), distance(fill, accent))
    }

    private let chipSize = CGSize(width: 46, height: 16)

    /// The appearance the chip is rendered in. The expectations resolve against
    /// this same one, never the host's System Appearance preference.
    private let appearanceName = NSAppearance.Name.darkAqua

    /// `Theme` colors are dynamic, and `NSColor(_:)` resolves them against the
    /// *current drawing* appearance — which outside a draw falls back to the
    /// host's System Appearance. Read against `appearanceName` instead, so the
    /// expectation describes the pixels that were actually rendered rather than
    /// whichever mode the machine running the test happens to be in.
    private func resolved(_ color: Color) throws -> NSColor {
        let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
        var resolvedColor: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolvedColor = NSColor(color).usingColorSpace(.sRGB)
        }
        return try XCTUnwrap(resolvedColor)
    }

    /// Pixels whose red channel dominates the way the accent's does — the chip's
    /// glyph, letters, and border all land here; `Theme.canvas` does not.
    private func accentPixels(in bitmap: NSBitmapImageRep) throws -> Int {
        var count = 0
        for x in 0 ..< bitmap.pixelsWide {
            for y in 0 ..< bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                else { continue }
                if color.redComponent > 0.45,
                   color.redComponent - color.blueComponent > 0.2 {
                    count += 1
                }
            }
        }
        return count
    }

    private func distance(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
        abs(lhs.redComponent - rhs.redComponent)
            + abs(lhs.greenComponent - rhs.greenComponent)
            + abs(lhs.blueComponent - rhs.blueComponent)
    }

    private func renderedChip() throws -> NSBitmapImageRep {
        try rendered { ModelsLiveChip() }
    }

    private func renderedCanvasOnly() throws -> NSBitmapImageRep {
        try rendered { EmptyView() }
    }

    private func rendered(
        @ViewBuilder _ content: () -> some View
    ) throws -> NSBitmapImageRep {
        let controller = NSHostingController(
            rootView: ZStack {
                Theme.canvas
                content()
            }
            .frame(width: chipSize.width, height: chipSize.height)
        )
        controller.view.appearance = NSAppearance(named: appearanceName)
        controller.view.frame = NSRect(origin: .zero, size: chipSize)
        controller.view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(
            controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds)
        )
        controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
        return bitmap
    }
}
