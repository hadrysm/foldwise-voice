// The idle Badge glyph must read as a deliberate static mark rather than a
// listening waveform. Its seven-element dot/bar silhouette is a stable visual
// invariant that can be checked from one render without wall-clock timing.

import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

final class BadgeIdleStaticTests: XCTestCase {
    @MainActor
    func testIdleGlyphKeepsItsDotBarSilhouette() throws {
        let heights = try renderedElementHeights()
        let silhouette = heights.map { height in
            switch height {
            case ...5: "dot"
            case ...9: "medium"
            default: "tall"
            }
        }
        XCTAssertEqual(
            silhouette,
            ["dot", "dot", "dot", "tall", "dot", "medium", "dot"]
        )
    }

    @MainActor
    private func renderedElementHeights() throws -> [Int] {
        let content = ZStack {
            Color.black
            BadgeIdleGlyph()
        }
        .frame(width: BadgeState.idle.width, height: Theme.badgeHeight)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        let rep = NSBitmapImageRep(cgImage: image)

        func isGlyphPixel(x: Int, y: Int) -> Bool {
            guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                return false
            }
            return max(color.redComponent, color.greenComponent, color.blueComponent) > 0.2
        }

        let occupiedColumns = (0 ..< rep.pixelsWide).map { x in
            (0 ..< rep.pixelsHigh).contains { y in isGlyphPixel(x: x, y: y) }
        }
        var runs: [ClosedRange<Int>] = []
        var start: Int?
        for (x, occupied) in occupiedColumns.enumerated() {
            if occupied, start == nil { start = x }
            if !occupied, let runStart = start {
                runs.append(runStart ... (x - 1))
                start = nil
            }
        }
        if let start { runs.append(start ... (rep.pixelsWide - 1)) }

        return runs.map { run in
            let rows = (0 ..< rep.pixelsHigh).filter { y in
                run.contains { x in isGlyphPixel(x: x, y: y) }
            }
            guard let first = rows.first, let last = rows.last else { return 0 }
            return last - first + 1
        }
    }
}
