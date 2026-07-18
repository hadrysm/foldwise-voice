// The Badge must not bleed outside its capsule: rendered over white, every
// pixel beyond the pill (plus an antialiasing allowance) stays white. Glow
// and drop-shadow blurs smudge light wallpapers — the pill reads as a crisp
// dark object, not a halo.

import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

final class BadgeHaloTests: XCTestCase {
    @MainActor
    func testIdlePillCastsNoHaloOntoAWhiteBackground() throws {
        let pill = CGSize(width: BadgeState.idle.width, height: Theme.badgeHeight)
        let badge = BadgeView(
            model: BadgeModel(), onHover: { _ in }, onClick: {},
            onChangeMode: {}, onRecord: {}, onOpenApp: {}
        )
        .frame(width: pill.width, height: pill.height)
        let canvas = ZStack {
            Color.white
            badge
        }
        .frame(width: pill.width + 120, height: pill.height + 120)

        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        let rep = NSBitmapImageRep(cgImage: image)

        var nonWhite = 0
        for y in 0 ..< rep.pixelsHigh {
            for x in 0 ..< rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                else { continue }
                let dimmest = min(color.redComponent, color.greenComponent, color.blueComponent)
                if dimmest < 0.98 {
                    nonWhite += 1
                }
            }
        }

        // The pill's own bounding box, plus slack for edge antialiasing.
        // A blur halo multiplies the non-white count several times over.
        let budget = Int(pill.width * pill.height) + 1500
        XCTAssertLessThanOrEqual(
            nonWhite, budget,
            "pixels outside the pill should stay white — no glow/shadow halo"
        )
    }
}
