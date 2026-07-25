// The production design-token owner (PRD #260). Colors resolve dynamically so
// the System Appearance preference follows live macOS changes.

import AppKit
import SwiftUI

enum Theme {
    // MARK: - canonical palette

    static let canvas = dynamic(light: 0xF7F3EC, dark: 0x07090B)
    static let navigation = dynamic(light: 0xEEE8DE, dark: 0x090B0E)
    static let surface = dynamic(light: 0xFFFCF7, dark: 0x0D1013)
    static let raised = dynamic(light: 0xF4EFE7, dark: 0x13171B)
    static let hover = dynamic(light: 0xEAE2D7, dark: 0x1A2026)
    static let border = dynamic(light: 0xD8CFC1, dark: 0x262C32)
    static let borderStrong = dynamic(light: 0x978B7C, dark: 0x5B6570)
    static let textPrimary = dynamic(light: 0x1A1714, dark: 0xF4F5F6)
    static let textSecondary = dynamic(light: 0x625C55, dark: 0xA4AAB0)
    static let textTertiary = dynamic(light: 0x766E65, dark: 0x747C85)
    static let accent = dynamic(light: 0xBF4008, dark: 0xFF6A1A)
    static let accentHover = dynamic(light: 0x9E3305, dark: 0xFF8A4A)
    static let accentForeground = dynamic(light: 0xFFFFFF, dark: 0x160900)
    static let success = dynamic(light: 0x147A42, dark: 0x43D17A)
    static let warning = dynamic(light: 0x865B00, dark: 0xF0B44B)
    static let error = dynamic(light: 0xB4232C, dark: 0xFF6464)

    // MARK: - badge palette

    enum Badge {
        static let ribbonPalette: [Color] = [
            Theme.accent,
            Theme.accent.opacity(0.86),
            Theme.warning,
            Theme.accent.opacity(0.58),
        ]
        static let baseline = Theme.accent.opacity(0.5)
    }

    // MARK: - typography (SF Pro / SF Mono behind one seam)

    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let display = font(ThemeTypographyPolicy.display)
    static let body = font(ThemeTypographyPolicy.body)
    static let nav = ui(13.5, .medium)
    static let navActive = ui(13.5, .semibold)
    static let sectionLabel = font(ThemeTypographyPolicy.section)
    static let data = font(ThemeTypographyPolicy.data)
    static let compactData = font(ThemeTypographyPolicy.compactData)
    static let tooltip = ui(11.5, .semibold)
    static let displayTracking = ThemeTypographyPolicy.display.tracking
    static let sectionTracking = ThemeTypographyPolicy.section.tracking

    // MARK: - metrics

    static let spacingUnit: CGFloat = 4
    static let spacingRhythm: [CGFloat] = [4, 8, 12, 16, 20, 24, 28, 32, 36]
    static let surfaceRadius: CGFloat = 8
    static let controlRadius: CGFloat = 6
    static let standardBorderWidth = ThemeBoundaryStrength.standard.width
    static let increasedContrastBorderWidth = ThemeBoundaryStrength.strong.width
    static let selectionIngressWidth: CGFloat = 2
    static let noticeIngressWidth: CGFloat = 3
    static let focusRingWidth: CGFloat = 2
    static let focusGap: CGFloat = 2
    static let contentPaddingWide: CGFloat = 28
    static let contentPaddingCompact: CGFloat = 20

    /// Custom titlebar height in fullscreen only; everywhere else the bar
    /// adopts the window's real titlebar strip (the top safe-area inset) so
    /// its content centers on the traffic lights.
    static let titlebarHeight: CGFloat = 32
    static let sidebarWidth: CGFloat = 190
    static let railWidth: CGFloat = 52
    static let sidebarHorizontalInset: CGFloat = 8
    static let sidebarVerticalInset: CGFloat = 10
    static let sidebarRowHeight: CGFloat = 36
    static let sidebarRowSpacing: CGFloat = 4
    static let homeCompactBreakpoint: Double = 940
    static let badgeHeight: CGFloat = 38

    // MARK: - helpers

    static func essentialBorderWidth(increaseContrast: Bool) -> CGFloat {
        ThemeEnvironmentPolicy.boundary(increaseContrast: increaseContrast).width
    }

    static func essentialBorderColor(increaseContrast: Bool) -> Color {
        ThemeEnvironmentPolicy.boundary(increaseContrast: increaseContrast).color
    }

    static func ordinaryAnimation(reduceMotion: Bool) -> Animation? {
        ThemeEnvironmentPolicy.ordinaryMotionDuration(reduceMotion: reduceMotion)
            .map(Animation.easeOut(duration:))
    }

    /// A dynamic color resolving per the system appearance, from hex sRGB.
    private static func dynamic(
        light: UInt32, dark: UInt32, alpha: CGFloat = 1
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(srgb: appearance.isDark ? dark : light).withAlphaComponent(alpha)
        })
    }

    private static func font(_ role: ThemeTypographyRole) -> Font {
        role.isMonospaced
            ? mono(role.size, role.weight.fontWeight)
            : ui(role.size, role.weight.fontWeight)
    }
}

enum EmberSurfaceLevel {
    case standard
    case raised

    var color: Color {
        switch self {
        case .standard: Theme.surface
        case .raised: Theme.raised
        }
    }
}

struct EmberSurface<Content: View>: View {
    let level: EmberSurfaceLevel
    let increaseContrastOverride: Bool?
    @ViewBuilder let content: Content
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    init(
        level: EmberSurfaceLevel = .standard,
        increaseContrast: Bool? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.level = level
        increaseContrastOverride = increaseContrast
        self.content = content()
    }

    var body: some View {
        content
            .background(level.color, in: RoundedRectangle(cornerRadius: Theme.surfaceRadius))
            // The silhouette governs the content: square-edged children — a
            // flush leading EmberIngress, a full-bleed row background — would
            // otherwise reach past the rounded corners and read as a nub
            // hanging off the boundary arc.
            .clipShape(RoundedRectangle(cornerRadius: Theme.surfaceRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.surfaceRadius)
                    .strokeBorder(
                        Theme.essentialBorderColor(increaseContrast: usesStrongBoundary),
                        lineWidth: Theme.essentialBorderWidth(increaseContrast: usesStrongBoundary)
                    )
            }
    }

    private var usesStrongBoundary: Bool {
        increaseContrastOverride ?? (colorSchemeContrast == .increased)
    }
}

struct EmberIngress: View {
    let color: Color
    var width = Theme.selectionIngressWidth

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: width)
            .accessibilityHidden(true)
    }
}

struct EmberHairline: View {
    let axis: Axis
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        Rectangle()
            .fill(Theme.essentialBorderColor(increaseContrast: usesStrongBoundary))
            .frame(
                width: axis == .vertical ? lineWidth : nil,
                height: axis == .horizontal ? lineWidth : nil
            )
            .frame(
                width: axis == .vertical ? layoutWidth : nil,
                height: axis == .horizontal ? layoutWidth : nil
            )
            .accessibilityHidden(true)
    }

    private var usesStrongBoundary: Bool {
        colorSchemeContrast == .increased
    }

    private var lineWidth: CGFloat {
        Theme.essentialBorderWidth(increaseContrast: usesStrongBoundary)
    }

    private var layoutWidth: CGFloat {
        ThemeEnvironmentPolicy.boundary(increaseContrast: usesStrongBoundary).layoutWidth
    }
}

struct EmberSectionLabel: View {
    let title: String
    var symbolName: String?

    init(_ title: String, symbolName: String? = nil) {
        self.title = title
        self.symbolName = symbolName
    }

    var body: some View {
        HStack(spacing: 6) {
            if let symbolName {
                Image(systemName: symbolName)
                    .accessibilityHidden(true)
            }
            Text(title)
        }
        .font(Theme.sectionLabel)
        .tracking(Theme.sectionTracking)
        .textCase(.uppercase)
        .foregroundStyle(Theme.textTertiary)
    }
}

struct EmberStatusNotice: View {
    let kind: EmberStatusKind
    let title: String
    var detail: String?
    var ingressWidth = Theme.noticeIngressWidth
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            EmberIngress(color: kind.colorRole.color, width: ingressWidth)
            Image(systemName: kind.symbolName)
                .foregroundStyle(kind.colorRole.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.ui(12, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let detail {
                    Text(detail)
                        .font(Theme.ui(10.5))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(EmberButtonStyle(kind: .quiet))
            }
        }
        .background(Theme.raised)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(kind.accessibilityName): \(title)")
    }
}

struct EmberEmptyState: View {
    let symbolName: String
    let title: String
    let detail: String

    var body: some View {
        EmberSurface {
            VStack(spacing: 8) {
                Image(systemName: symbolName)
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Theme.ui(15, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(Theme.ui(11.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
        }
        .accessibilityElement(children: .combine)
    }
}

struct EmberSelectionLabel<Content: View>: View {
    let isSelected: Bool
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 9) {
            EmberIngress(color: isSelected ? Theme.accent : .clear)
                .frame(height: 22)
            content
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
            }
        }
        .background(isSelected ? Theme.raised : .clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius))
    }
}

enum EmberButtonKind {
    case primary
    case quiet
    case destructive
}

struct EmberButtonStyle: ButtonStyle {
    let kind: EmberButtonKind

    func makeBody(configuration: Configuration) -> some View {
        EmberButtonBody(configuration: configuration, kind: kind)
    }
}

struct EmberPlainButtonStyle: ButtonStyle {
    var cornerRadius = Theme.controlRadius

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

private struct EmberButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let kind: EmberButtonKind
    @State private var isHovering = false
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .font(Theme.ui(10.5, .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(minHeight: 28)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            .overlay {
                if kind != .primary {
                    RoundedRectangle(cornerRadius: Theme.controlRadius)
                        .strokeBorder(
                            Theme.essentialBorderColor(increaseContrast: usesStrongBoundary),
                            lineWidth: Theme.essentialBorderWidth(
                                increaseContrast: usesStrongBoundary
                            )
                        )
                }
            }
            .onHover { isHovering = $0 }
            .opacity(isEnabled ? 1 : 0.46)
            .focusEffectDisabled()
            .emberFocusRing(isFocused)
    }

    private var foreground: Color {
        switch kind {
        case .primary: Theme.accentForeground
        case .quiet: Theme.textPrimary
        case .destructive: Theme.error
        }
    }

    private var background: Color {
        switch kind {
        case .primary:
            configuration.isPressed || isHovering ? Theme.accentHover : Theme.accent
        case .quiet, .destructive:
            configuration.isPressed || isHovering ? Theme.hover : Theme.surface
        }
    }

    private var usesStrongBoundary: Bool {
        colorSchemeContrast == .increased
    }
}

private struct EmberFocusRing: ViewModifier {
    enum Placement {
        case outside
        case inset
    }

    let isFocused: Bool
    let cornerRadius: CGFloat
    let placement: Placement

    func body(content: Content) -> some View {
        content
            .overlay {
                if isFocused {
                    focusRing
                }
            }
    }

    @ViewBuilder
    private var focusRing: some View {
        switch placement {
        case .outside:
            RoundedRectangle(cornerRadius: cornerRadius + Theme.focusGap)
                .stroke(Theme.canvas, lineWidth: Theme.focusGap)
                .padding(-Theme.focusGap)
            RoundedRectangle(
                cornerRadius: cornerRadius + Theme.focusGap + Theme.focusRingWidth
            )
            .stroke(Theme.accent, lineWidth: Theme.focusRingWidth)
            .padding(-(Theme.focusGap + Theme.focusRingWidth))
        case .inset:
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    Theme.canvas,
                    lineWidth: Theme.focusRingWidth + Theme.focusGap
                )
                .padding(Theme.focusGap)
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Theme.accent, lineWidth: Theme.focusRingWidth)
                .padding(Theme.focusGap)
        }
    }
}

private struct EmberControlSurface: ViewModifier {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func body(content: Content) -> some View {
        content
            .background(
                Theme.raised,
                in: RoundedRectangle(cornerRadius: Theme.controlRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .strokeBorder(
                        Theme.essentialBorderColor(increaseContrast: usesStrongBoundary),
                        lineWidth: Theme.essentialBorderWidth(
                            increaseContrast: usesStrongBoundary
                        )
                    )
            }
    }

    private var usesStrongBoundary: Bool {
        colorSchemeContrast == .increased
    }
}

extension View {
    func emberControlSurface() -> some View {
        modifier(EmberControlSurface())
    }

    func emberFocusRing(_ isFocused: Bool) -> some View {
        modifier(EmberFocusRing(
            isFocused: isFocused,
            cornerRadius: Theme.controlRadius,
            placement: .outside
        ))
    }

    func emberInsetFocusRing(
        _ isFocused: Bool,
        cornerRadius: CGFloat = Theme.controlRadius
    ) -> some View {
        modifier(EmberFocusRing(
            isFocused: isFocused,
            cornerRadius: cornerRadius,
            placement: .inset
        ))
    }
}

private extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

private extension ThemeBoundaryStrength {
    var color: Color {
        switch self {
        case .standard: Theme.border
        case .strong: Theme.borderStrong
        }
    }
}

private extension ThemeTypographyWeight {
    var fontWeight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

private extension EmberSemanticColorRole {
    var color: Color {
        switch self {
        case .success: Theme.success
        case .warning: Theme.warning
        case .error: Theme.error
        }
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
