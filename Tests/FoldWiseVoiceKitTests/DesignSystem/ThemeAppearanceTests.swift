import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

final class ThemeAppearanceTests: XCTestCase {
    func testCanonicalPaletteResolvesToApprovedVariants() throws {
        let tokens: [(Color, UInt32, UInt32)] = [
            (Theme.canvas, 0xF7F3EC, 0x07090B),
            (Theme.navigation, 0xEEE8DE, 0x090B0E),
            (Theme.surface, 0xFFFCF7, 0x0D1013),
            (Theme.raised, 0xF4EFE7, 0x13171B),
            (Theme.hover, 0xEAE2D7, 0x1A2026),
            (Theme.border, 0xD8CFC1, 0x262C32),
            (Theme.borderStrong, 0x978B7C, 0x5B6570),
            (Theme.textPrimary, 0x1A1714, 0xF4F5F6),
            (Theme.textSecondary, 0x625C55, 0xA4AAB0),
            (Theme.textTertiary, 0x766E65, 0x747C85),
            (Theme.accent, 0xBF4008, 0xFF6A1A),
            (Theme.accentHover, 0x9E3305, 0xFF8A4A),
            (Theme.accentForeground, 0xFFFFFF, 0x160900),
            (Theme.success, 0x147A42, 0x43D17A),
            (Theme.warning, 0x865B00, 0xF0B44B),
            (Theme.error, 0xB4232C, 0xFF6464),
        ]

        for (color, light, dark) in tokens {
            try assertColor(color, appearance: .aqua, hex: light)
            try assertColor(color, appearance: .darkAqua, hex: dark)
        }
    }

    func testBadgeBackgroundResolvesToApprovedVariants() throws {
        try assertColor(
            Theme.Badge.pillBackground, appearance: .aqua, hex: 0xF7F5FB, alpha: 0.96
        )
        try assertColor(
            Theme.Badge.pillBackground, appearance: .darkAqua, hex: 0x100D16, alpha: 0.96
        )
    }

    func testBadgeForegroundResolvesToApprovedVariants() throws {
        try assertColor(Theme.Badge.iconEmphasized, appearance: .aqua, hex: 0x211A32)
        try assertColor(Theme.Badge.iconEmphasized, appearance: .darkAqua, hex: 0xE8E2F7)
    }

    private func assertColor(
        _ color: Color,
        appearance name: NSAppearance.Name,
        hex: UInt32,
        alpha: CGFloat = 1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let appearance = try XCTUnwrap(NSAppearance(named: name))
        var resolvedColor: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolvedColor = NSColor(color).usingColorSpace(.sRGB)
        }
        let resolved = try XCTUnwrap(resolvedColor)
        let expected = NSColor(srgb: hex).withAlphaComponent(alpha)

        XCTAssertEqual(resolved.redComponent, expected.redComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(resolved.greenComponent, expected.greenComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(resolved.blueComponent, expected.blueComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(resolved.alphaComponent, expected.alphaComponent, accuracy: 0.001, file: file, line: line)
    }
}
