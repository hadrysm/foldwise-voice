import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

final class ThemeAppearanceTests: XCTestCase {
    func testWindowBackgroundResolvesToApprovedVariants() throws {
        try assertColor(Theme.windowBackground, appearance: .aqua, hex: 0xFCFBF8)
        try assertColor(Theme.windowBackground, appearance: .darkAqua, hex: 0x161411)
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
