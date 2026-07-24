import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

final class StatsActivityStyleTests: XCTestCase {
    func testWaveformFillPatternMapsEachIntensityToItsFilledBarCount() {
        XCTAssertEqual(
            StatsProjection.Day.Intensity.allCases.map(StatsActivityStyle.waveformFillPattern),
            [
                [false, false, false, false, false],
                [true, false, false, false, false],
                [true, true, false, false, false],
                [true, true, true, false, false],
                [true, true, true, true, false],
                [true, true, true, true, true],
            ]
        )
    }

    func testFutureDayUsesOpaqueRaisedAndTertiaryPalette() throws {
        let style = StatsActivityStyle(
            day: day(state: .future),
            focused: false,
            hovered: false,
            increaseContrast: false
        )

        XCTAssertEqual(
            try resolvedColors(
                [style.background, style.foreground],
                appearances: [.aqua, .darkAqua]
            ),
            [
                ["F4EFE7@1.00", "766E65@1.00"],
                ["13171B@1.00", "747C85@1.00"],
            ]
        )
    }

    func testTodayUsesOpaqueRaisedPaletteAndPersistentOutline() throws {
        let style = StatsActivityStyle(
            day: day(state: .today),
            focused: false,
            hovered: false,
            increaseContrast: false
        )

        XCTAssertEqual(
            try resolvedColors(
                [style.background, style.foreground, style.outline],
                appearances: [.aqua, .darkAqua]
            ),
            [
                ["F4EFE7@1.00", "625C55@1.00", "978B7C@1.00"],
                ["13171B@1.00", "A4AAB0@1.00", "5B6570@1.00"],
            ]
        )
    }

    func testHoveredDayUsesOpaqueHoverPaletteAndStandardOutline() throws {
        let style = StatsActivityStyle(
            day: day(state: .elapsed),
            focused: false,
            hovered: true,
            increaseContrast: false
        )

        XCTAssertEqual(
            try resolvedColors(
                [style.background, style.foreground, style.outline],
                appearances: [.aqua, .darkAqua]
            ),
            [
                ["EAE2D7@1.00", "625C55@1.00", "D8CFC1@1.00"],
                ["1A2026@1.00", "A4AAB0@1.00", "262C32@1.00"],
            ]
        )
    }

    func testIncreaseContrastStrengthensDayBoundaryWithoutChangingLayout() {
        let day = day(state: .elapsed)

        XCTAssertEqual(
            [
                StatsActivityStyle(
                    day: day,
                    focused: false,
                    hovered: false,
                    increaseContrast: false
                ).boundaryWidth,
                StatsActivityStyle(
                    day: day,
                    focused: false,
                    hovered: false,
                    increaseContrast: true
                ).boundaryWidth,
            ],
            [1, 2]
        )
    }

    func testNormalMotionUsesCrossfadeTransitionPolicy() {
        XCTAssertEqual(StatsTransitionPolicy.resolve(reduceMotion: false), .crossfade)
    }

    func testReduceMotionUsesImmediateTransitionPolicy() {
        XCTAssertEqual(StatsTransitionPolicy.resolve(reduceMotion: true), .immediate)
    }

    func testCalendarClearsInheritedAnimation() {
        var transaction = Transaction(animation: .linear(duration: 1))

        StatsTransitionPolicy.clearInheritedAnimation(in: &transaction)

        XCTAssertNil(transaction.animation)
    }

    private func resolvedColors(
        _ colors: [Color],
        appearances: [NSAppearance.Name]
    ) throws -> [[String]] {
        try appearances.map { try resolvedColors(colors, appearance: $0) }
    }

    private func resolvedColors(
        _ colors: [Color],
        appearance name: NSAppearance.Name
    ) throws -> [String] {
        let appearance = try XCTUnwrap(NSAppearance(named: name))
        return try colors.map { color in
            var resolvedColor: NSColor?
            appearance.performAsCurrentDrawingAppearance {
                resolvedColor = NSColor(color).usingColorSpace(.sRGB)
            }
            let resolved = try XCTUnwrap(resolvedColor)
            return String(
                format: "%02X%02X%02X@%.2f",
                Int((resolved.redComponent * 255).rounded()),
                Int((resolved.greenComponent * 255).rounded()),
                Int((resolved.blueComponent * 255).rounded()),
                resolved.alphaComponent
            )
        }
    }

    private func day(
        state: StatsProjection.Day.State,
        intensity: StatsProjection.Day.Intensity = .neutral
    ) -> StatsProjection.Day {
        StatsProjection.Day(
            date: Date(timeIntervalSince1970: 0),
            state: state,
            dayNumber: "1",
            savedSessionCount: 0,
            spokenWords: 0,
            intensity: intensity,
            compactSpokenWords: nil,
            fullDate: "Thursday, January 1, 1970",
            detailActivity: "No saved Dictation sessions",
            detailTiming: nil,
            accessibilityLabel: "Thursday, January 1, 1970",
            accessibilityValue: "No dictated words. No saved Dictation sessions"
        )
    }
}
