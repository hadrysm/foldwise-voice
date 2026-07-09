// The design-token layer for the Editorial redesign (PRD #103): every color,
// font, spacing, and radius the redesigned surfaces use, in one place. Window
// colors adapt to the system light/dark appearance via dynamic NSColors; the
// Badge carries its own fixed palette because it floats over any wallpaper.
// Fonts route through `Theme.ui`/`Theme.mono` exclusively, so bundling
// Instrument Sans / IBM Plex Mono later is a one-file change.

import AppKit
import SwiftUI

enum Theme {
    // MARK: - window palette (light / dark per the design spec)

    static let windowBackground = dynamic(light: 0xFCFBF8, dark: 0x161411)
    static let sidebarBackground = dynamic(light: 0xF7F5F0, dark: 0x1B1815)
    static let hairline = dynamic(light: 0xE9E5DC, dark: 0x2C2822)
    static let textPrimary = dynamic(light: 0x1B1813, dark: 0xF2EFE8)
    static let textSecondary = dynamic(light: 0x6E675A, dark: 0x9B9482)
    static let textTertiary = dynamic(light: 0x8F887A, dark: 0x87816F)
    static let textFaint = dynamic(light: 0xB0A995, dark: 0x6B655A)
    static let accent = dynamic(light: 0xC24A22, dark: 0xE06A3E)
    static let keycapBackground = dynamic(light: 0xFFFFFF, dark: 0x211E19)
    static let keycapBorder = dynamic(light: 0xD8D2C4, dark: 0x4A453B)
    static let activeNavBackground = dynamic(light: 0xFCFBF8, dark: 0x26221C)
    static let activeNavShadow = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark
            ? NSColor.black.withAlphaComponent(0.25)
            : NSColor(srgb: 0x322A1E).withAlphaComponent(0.07)
    })
    /// Rail tooltip chips invert against the window: dark chip in light mode,
    /// light chip in dark mode.
    static let tooltipBackground = dynamic(light: 0x1B1813, dark: 0xF2EFE8)
    static let tooltipText = dynamic(light: 0xF7F5F0, dark: 0x1B1813)
    /// Card fill for the grouped settings rows, one step off the window.
    static let cardBackground = dynamic(light: 0xF7F5F0, dark: 0x1B1815)

    // MARK: - badge palette (fixed — the pill floats over any wallpaper)

    enum Badge {
        static let pillBackground = Color(red: 16 / 255, green: 13 / 255, blue: 22 / 255, opacity: 0.96)
        static let border = Color(red: 167 / 255, green: 139 / 255, blue: 250 / 255, opacity: 0.22)
        static let borderRecording = Color(red: 167 / 255, green: 139 / 255, blue: 250 / 255, opacity: 0.45)
        static let borderError = Color(red: 250 / 255, green: 160 / 255, blue: 120 / 255, opacity: 0.55)
        static let iconIdle = Color(srgb: 0xB8AEDB)
        static let iconEmphasized = Color(srgb: 0xE8E2F7)
        static let timerText = Color(srgb: 0xCFC4EA)
        static let buttonBackground = Color(red: 167 / 255, green: 139 / 255, blue: 250 / 255, opacity: 0.16)
        static let buttonHover = Color(red: 167 / 255, green: 139 / 255, blue: 250 / 255, opacity: 0.30)
        /// Silk-ribbon strand colors, in strand order.
        static let ribbonPalette: [Color] = [
            Color(red: 196 / 255, green: 132 / 255, blue: 252 / 255),
            Color(red: 124 / 255, green: 93 / 255, blue: 250 / 255),
            Color(red: 94 / 255, green: 214 / 255, blue: 255 / 255),
            Color(red: 244 / 255, green: 158 / 255, blue: 255 / 255),
        ]
        static let baselineLeft = Color(red: 180 / 255, green: 150 / 255, blue: 255 / 255, opacity: 0.5)
        static let baselineRight = Color(red: 120 / 255, green: 220 / 255, blue: 255 / 255, opacity: 0.5)
    }

    // MARK: - typography (SF Pro / SF Mono behind one seam)

    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let pageTitle = ui(28, .semibold)
    static let statNumber = ui(27, .semibold)
    static let body = ui(13.5)
    static let nav = ui(13.5, .medium)
    static let navActive = ui(13.5, .semibold)
    static let sectionLabel = ui(11, .bold)
    static let timestamp = mono(11)
    static let modeTag = mono(10.5)
    static let tooltip = ui(11.5, .semibold)

    // MARK: - metrics

    static let sidebarWidth: CGFloat = 190
    static let railWidth: CGFloat = 52
    static let statsRailWidth: CGFloat = 212
    static let contentPadding: CGFloat = 36
    static let navRadius: CGFloat = 8
    static let railTileRadius: CGFloat = 9
    static let cardRadius: CGFloat = 8
    static let keycapRadius: CGFloat = 6
    static let tooltipRadius: CGFloat = 6
    static let badgeHeight: CGFloat = 38
    /// Sidebar collapse/expand and Badge width animation.
    static let sidebarAnimation = Animation.easeOut(duration: 0.3)
    static let badgeCrossFade = Animation.easeOut(duration: 0.22)

    // MARK: - helpers

    /// A dynamic color resolving per the system appearance, from hex sRGB.
    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(srgb: appearance.isDark ? dark : light)
        })
    }
}

private extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

extension NSColor {
    /// An opaque sRGB color from a 0xRRGGBB literal.
    convenience init(srgb hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

private extension Color {
    init(srgb hex: UInt32) {
        self.init(nsColor: NSColor(srgb: hex))
    }
}
