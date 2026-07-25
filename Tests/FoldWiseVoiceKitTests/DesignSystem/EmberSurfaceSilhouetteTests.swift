// A leading EmberIngress is a square-cornered bar; the EmberSurface around it
// is a rounded rectangle. Unless the surface clips its content, the bar's
// square ends escape the card silhouette — the accent stripe sprouts nubs past
// the rounded corners and the boundary arc cuts across it.

import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

final class EmberSurfaceSilhouetteTests: XCTestCase {
    private static let card = CGSize(width: 220, height: 58)

    @MainActor
    func testLeadingIngressStaysWithinTheRoundedSurface() throws {
        XCTAssertEqual(try escapedAccentPixels(), 0)
    }

    @MainActor
    func testRoundedCornersStayClearOfTheIngress() throws {
        let bitmap = try renderCard()
        let corners = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0, y: CGFloat(bitmap.pixelsHigh - 1)),
        ]

        for corner in corners {
            let pixel = try XCTUnwrap(
                bitmap.colorAt(x: Int(corner.x), y: Int(corner.y))?
                    .usingColorSpace(.sRGB)
            )
            XCTAssertFalse(
                readsAsAccent(pixel),
                "the surface's rounded corner at \(corner) is covered by the ingress"
            )
        }
    }

    /// Accent-colored pixels sitting clearly outside the surface silhouette —
    /// the antialiasing band along the arc is excluded, so any hit is a leak.
    @MainActor
    private func escapedAccentPixels() throws -> Int {
        let bitmap = try renderCard()
        let allowance: CGFloat = 1.5
        let silhouette = CGPath(
            roundedRect: CGRect(origin: .zero, size: Self.card)
                .insetBy(dx: -allowance, dy: -allowance),
            cornerWidth: Theme.surfaceRadius + allowance,
            cornerHeight: Theme.surfaceRadius + allowance,
            transform: nil
        )

        var escaped = 0
        for y in 0 ..< bitmap.pixelsHigh {
            for x in 0 ..< bitmap.pixelsWide {
                let center = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                guard !silhouette.contains(center),
                      let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                else { continue }
                if readsAsAccent(pixel) {
                    escaped += 1
                }
            }
        }
        return escaped
    }

    /// Both appearances render the accent as a saturated orange; the surface,
    /// its boundary, and the white ground are all near-neutral.
    private func readsAsAccent(_ pixel: NSColor) -> Bool {
        pixel.redComponent - pixel.blueComponent > 0.25
    }

    @MainActor
    private func renderCard() throws -> NSBitmapImageRep {
        let canvas = ZStack {
            Color.white
            EmberSurface(level: .raised) {
                HStack(spacing: 12) {
                    EmberIngress(color: Theme.accent)
                    Text("All systems go")
                        .font(Theme.ui(12, .semibold))
                    Spacer(minLength: 12)
                }
                .frame(width: Self.card.width, height: Self.card.height)
            }
        }
        .frame(width: Self.card.width, height: Self.card.height)

        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1
        return NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
    }
}
