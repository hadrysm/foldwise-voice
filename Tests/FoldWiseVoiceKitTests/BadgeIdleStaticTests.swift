// The idle Badge glyph must sit still (PRD #103 QA): while the user is not
// dictating, any per-element height/opacity motion reads as "listening".
// Rendering the idle glyph at two moments over a second apart must produce
// identical pixels — a breathing glyph fails, a static one passes.

import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

final class BadgeIdleStaticTests: XCTestCase {
    @MainActor
    func testIdleGlyphRendersIdenticallyAtDifferentTimes() throws {
        let first = try renderIdleGlyph()
        // 1.2s is far enough into the old 3.4s breath cycle that several of
        // the seven staggered elements are guaranteed mid-swing.
        Thread.sleep(forTimeInterval: 1.2)
        let second = try renderIdleGlyph()

        XCTAssertEqual(first.count, second.count, "renders should be the same size")
        var differing = 0
        for i in 0 ..< min(first.count, second.count)
            where abs(Int(first[i]) - Int(second[i])) > 2 {
            differing += 1
        }
        XCTAssertEqual(
            differing, 0,
            "idle glyph must not animate — \(differing) bytes changed between renders 1.2s apart"
        )
    }

    @MainActor
    private func renderIdleGlyph() throws -> [UInt8] {
        let content = ZStack {
            Color.black
            BadgeIdleGlyph()
        }
        .frame(width: BadgeState.idle.width, height: Theme.badgeHeight)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        let rep = NSBitmapImageRep(cgImage: image)
        let data = try XCTUnwrap(rep.bitmapData)
        return Array(UnsafeBufferPointer(
            start: data, count: rep.bytesPerPlane * rep.numberOfPlanes
        ))
    }
}
