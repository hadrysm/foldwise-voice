import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

final class StatsActivityStyleTests: XCTestCase {
    func testActivityLevelsResolveFromLightAccent() throws {
        XCTAssertEqual(
            try resolvedLevelColors(appearance: .aqua),
            [
                "FCFBF8@0.72", "C24A22@0.20", "C24A22@0.36",
                "C24A22@0.54", "C24A22@0.76", "C24A22@0.96",
            ]
        )
    }

    func testActivityLevelsResolveFromDarkAccent() throws {
        XCTAssertEqual(
            try resolvedLevelColors(appearance: .darkAqua),
            [
                "161411@0.72", "E06A3E@0.20", "E06A3E@0.36",
                "E06A3E@0.54", "E06A3E@0.76", "E06A3E@0.96",
            ]
        )
    }

    func testDayStatesResolveFromLightPalette() throws {
        XCTAssertEqual(
            try resolvedDayStateColors(appearance: .aqua),
            [
                "FCFBF8@0.28", "B0A995@0.42",
                "FCFBF8@0.72", "1B1813@1.00", "8F887A@0.72",
                "C24A22@0.54", "1B1813@1.00", "1B1813@1.00", "1B1813@0.22",
                "000000@1.00",
            ]
        )
    }

    func testDayStatesResolveFromDarkPalette() throws {
        XCTAssertEqual(
            try resolvedDayStateColors(appearance: .darkAqua),
            [
                "161411@0.28", "6B655A@0.42",
                "161411@0.72", "F2EFE8@1.00", "87816F@0.72",
                "E06A3E@0.54", "F2EFE8@1.00", "F2EFE8@1.00", "F2EFE8@0.22",
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
