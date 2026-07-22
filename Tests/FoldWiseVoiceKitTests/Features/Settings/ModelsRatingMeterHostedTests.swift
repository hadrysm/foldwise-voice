import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class ModelsRatingMeterHostedTests: XCTestCase {
    func testRatedMeterShowsOneFilledSegmentPerPoint() throws {
        let filledSegmentCounts = try (1 ... 5).map { value in
            try filledSegmentCount(for: value)
        }

        XCTAssertEqual(filledSegmentCounts, [1, 2, 3, 4, 5])
    }

    func testHighlightedMeterChangesFilledSegmentsToAccentColor() throws {
        let neutral = try filledSegmentColor(isHighlighted: false)
        let highlighted = try filledSegmentColor(isHighlighted: true)
        let colorDistance = abs(neutral.redComponent - highlighted.redComponent)
            + abs(neutral.greenComponent - highlighted.greenComponent)
            + abs(neutral.blueComponent - highlighted.blueComponent)

        XCTAssertGreaterThan(colorDistance, 0.4)
    }

    private func filledSegmentCount(for value: Int) throws -> Int {
        let bitmap = try renderedBitmap(value: value, isHighlighted: false)
        let y = bitmap.pixelsHigh / 2
        var count = 0
        var previousPixelWasFilled = false
        for x in 0 ..< bitmap.pixelsWide {
            let color = try XCTUnwrap(
                bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
            )
            let isFilled = (
                color.redComponent + color.greenComponent + color.blueComponent
            ) / 3 > 0.4
            if isFilled, !previousPixelWasFilled {
                count += 1
            }
            previousPixelWasFilled = isFilled
        }
        return count
    }

    private func filledSegmentColor(isHighlighted: Bool) throws -> NSColor {
        let bitmap = try renderedBitmap(value: 5, isHighlighted: isHighlighted)
        let scale = CGFloat(bitmap.pixelsWide) / 42
        return try XCTUnwrap(
            bitmap.colorAt(x: Int(7 * scale), y: bitmap.pixelsHigh / 2)?
                .usingColorSpace(.sRGB)
        )
    }

    private func renderedBitmap(
        value: Int,
        isHighlighted: Bool
    ) throws -> NSBitmapImageRep {
        let controller = NSHostingController(
            rootView: ZStack {
                Theme.windowBackground
                ModelsRatingMeter(rating: .rated(value), isHighlighted: isHighlighted)
            }
            .frame(width: 42, height: 14)
        )
        controller.view.appearance = NSAppearance(named: .darkAqua)
        controller.view.frame = NSRect(x: 0, y: 0, width: 42, height: 14)
        controller.view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(
            controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds)
        )
        controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
        return bitmap
    }
}
