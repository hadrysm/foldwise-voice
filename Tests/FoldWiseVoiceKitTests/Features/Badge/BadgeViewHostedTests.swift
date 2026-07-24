import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class BadgeViewHostedTests: XCTestCase {
    func testNeutralBadgeUsesCanonicalOpaqueSurfaceInLightAndDark() throws {
        let light = try render(state: .idle, colorScheme: .light)
        let dark = try render(state: .idle, colorScheme: .dark)

        XCTAssertGreaterThan(try tokenCount(Theme.surface, in: light, colorScheme: .light), 1500)
        XCTAssertGreaterThan(try tokenCount(Theme.surface, in: dark, colorScheme: .dark), 1500)
    }

    func testPrimaryStatesRenderCanonicalSemanticColors() throws {
        let idle = try render(state: .idle)
        let hover = try render(state: .hover)
        let recording = try render(state: .recording)
        let workingSpinner = try render(state: .working(status: nil))
        let workingStatus = try render(state: .working(status: "downloading 45%"))
        let done = try render(state: .done)
        let error = try render(state: .error(message: "something went wrong"))
        let modeCycle = try render(
            state: .idle,
            modeCycleDisplay: .settled(
                BadgeModeCycleItem(
                    selection: .voiceToText,
                    name: "Voice to Text",
                    icon: "waveform"
                ),
                motion: .standard
            )
        )

        XCTAssertEqual(
            [
                try tokenCount(Theme.accent, in: idle, inset: 8),
                try tokenCount(Theme.accent, in: hover, inset: 8),
                try tokenCount(Theme.accent, in: recording, inset: 8),
                try tokenCount(Theme.accent, in: workingSpinner, inset: 8),
                try tokenCount(Theme.accent, in: workingStatus, inset: 8),
                try tokenCount(Theme.success, in: done, inset: 8),
                try tokenCount(Theme.error, in: error, inset: 8),
                try tokenCount(Theme.accent, in: modeCycle, inset: 8),
            ].map { $0 > 12 },
            Array(repeating: true, count: 8)
        )
    }

    func testReduceMotionFreezesRecordingAtRepresentativeAmplitude() throws {
        let quiet = try render(
            state: .recording,
            reduceMotion: true,
            amplitude: 0.10
        )
        let loud = try render(
            state: .recording,
            reduceMotion: true,
            amplitude: 0.45
        )

        XCTAssertEqual(try pixelData(quiet), try pixelData(loud))
    }

    func testIncreaseContrastStrengthensNeutralBadgeBoundary() throws {
        let standard = try render(state: .idle, increaseContrast: false)
        let increased = try render(state: .idle, increaseContrast: true)

        XCTAssertGreaterThan(
            try tokenCount(Theme.borderStrong, in: increased),
            try tokenCount(Theme.borderStrong, in: standard) + 80
        )
    }

    private func render(
        state: BadgeState,
        modeCycleDisplay: BadgeModeCycleDisplay? = nil,
        colorScheme: ColorScheme = .light,
        increaseContrast: Bool = false,
        reduceMotion: Bool = false,
        amplitude: Double = LevelSmoother.floor
    ) throws -> NSBitmapImageRep {
        let model = BadgeModel()
        model.state = state
        model.modeCycleDisplay = modeCycleDisplay
        model.amplitude = amplitude
        let view = BadgeView(
            model: model,
            onHover: { _ in },
            onClick: {},
            onChangeMode: {},
            onRecord: {},
            onOpenApp: {},
            environmentOverride: BadgeEnvironmentAdaptations(
                reduceMotion: reduceMotion,
                increaseContrast: increaseContrast
            )
        )
        .environment(\.colorScheme, colorScheme)
        .frame(
            width: modeCycleDisplay == nil
                ? state.width
                : BadgeModeCycleReducer.expandedWidth,
            height: Theme.badgeHeight
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
    }

    private func tokenCount(
        _ token: Color,
        in bitmap: NSBitmapImageRep,
        colorScheme: ColorScheme = .light,
        inset: Int = 0
    ) throws -> Int {
        let target = try tokenColor(token, colorScheme: colorScheme)
        var count = 0
        for y in inset ..< (bitmap.pixelsHigh - inset) {
            for x in inset ..< (bitmap.pixelsWide - inset) {
                guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                else { continue }
                let distance = abs(pixel.redComponent - target.redComponent)
                    + abs(pixel.greenComponent - target.greenComponent)
                    + abs(pixel.blueComponent - target.blueComponent)
                if distance < 0.04 {
                    count += 1
                }
            }
        }
        return count
    }

    private func pixelData(_ bitmap: NSBitmapImageRep) throws -> Data {
        let bytes = try XCTUnwrap(bitmap.bitmapData)
        return Data(bytes: bytes, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }

    private func tokenColor(
        _ token: Color,
        colorScheme: ColorScheme
    ) throws -> NSColor {
        let renderer = ImageRenderer(content:
            token
                .environment(\.colorScheme, colorScheme)
                .frame(width: 2, height: 2))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
        return try XCTUnwrap(bitmap.colorAt(x: 1, y: 1)?.usingColorSpace(.sRGB))
    }
}
