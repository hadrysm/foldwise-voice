import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

final class StatsActivityStyleTests: XCTestCase {
    func testActivityLevelsResolveFromLightAccent() throws {
        XCTAssertEqual(
            try resolvedLevelColors(appearance: .aqua),
            [
                "F7F3EC@0.72", "BF4008@0.20", "BF4008@0.36",
                "BF4008@0.54", "BF4008@0.76", "BF4008@0.96",
            ]
        )
    }

    func testActivityLevelsResolveFromDarkAccent() throws {
        XCTAssertEqual(
            try resolvedLevelColors(appearance: .darkAqua),
            [
                "07090B@0.72", "FF6A1A@0.20", "FF6A1A@0.36",
                "FF6A1A@0.54", "FF6A1A@0.76", "FF6A1A@0.96",
            ]
        )
    }

    func testDayStatesResolveFromLightPalette() throws {
        XCTAssertEqual(
            try resolvedDayStateColors(appearance: .aqua),
            [
                "F7F3EC@0.28", "766E65@0.42",
                "F7F3EC@0.72", "1A1714@1.00", "766E65@0.72",
                "BF4008@0.54", "1A1714@1.00", "1A1714@1.00", "1A1714@0.22",
                "000000@1.00",
            ]
        )
    }

    func testDayStatesResolveFromDarkPalette() throws {
        XCTAssertEqual(
            try resolvedDayStateColors(appearance: .darkAqua),
            [
                "07090B@0.28", "747C85@0.42",
                "07090B@0.72", "F4F5F6@1.00", "747C85@0.72",
                "FF6A1A@0.54", "F4F5F6@1.00", "F4F5F6@1.00", "F4F5F6@0.22",
                "000000@1.00",
            ]
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

    private func resolvedLevelColors(appearance name: NSAppearance.Name) throws -> [String] {
        try resolvedColors(
            (0 ... 5).map(StatsActivityStyle.legendFill(level:)),
            appearance: name
        )
    }

    private func resolvedDayStateColors(appearance name: NSAppearance.Name) throws -> [String] {
        let future = StatsActivityStyle(day: day(state: .future), focused: false)
        let today = StatsActivityStyle(day: day(state: .today), focused: false)
        let focused = StatsActivityStyle(
            day: day(state: .elapsed, intensity: .medium),
            focused: true
        )
        let veryHigh = StatsActivityStyle(
            day: day(state: .elapsed, intensity: .veryHigh),
            focused: false
        )
        return try resolvedColors(
            [
                future.background, future.foreground,
                today.background, today.foreground, today.outline,
                focused.background, focused.foreground, focused.outline, focused.shadow,
                veryHigh.foreground,
            ],
            appearance: name
        )
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
