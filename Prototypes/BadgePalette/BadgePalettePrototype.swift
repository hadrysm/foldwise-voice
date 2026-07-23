// THROWAWAY PROTOTYPE — visual decision aid for Wayfinder ticket
// "Prototype the orange-led Badge palette across states".
//
// Three palette-role treatments of the same exact Badge geometry and state
// content, switchable from the bottom review bar. This is isolated from
// production navigation and logic. The approved answer belongs in the issue
// and the later visual specification, not in these prototype abstractions.

import AppKit
import SwiftUI

private enum PaletteTreatment: String, CaseIterable, Identifiable {
    case ember
    case copper
    case notch

    var id: String {
        rawValue
    }

    var key: String {
        switch self {
        case .ember: "A"
        case .copper: "B"
        case .notch: "C"
        }
    }

    var title: String {
        switch self {
        case .ember: "Ember Trace"
        case .copper: "Copper Key"
        case .notch: "Signal Notch"
        }
    }

    var thesis: String {
        switch self {
        case .ember:
            "Orange traces live work; semantic green and red own the outcomes."
        case .copper:
            "A muted copper identity at rest; bright orange appears only when action starts."
        case .notch:
            "State color gains a fixed positional cue inside the unchanged capsule."
        }
    }

    var tradeoff: String {
        switch self {
        case .ember:
            "Best match for Ember Edge and the approved screenshot; restrained but unmistakably FoldWise."
        case .copper:
            "Calmest on busy wallpapers, though Idle reads less immediately orange-led."
        case .notch:
            "Strongest Differentiate Without Color cue, with more visual structure in a small surface."
        }
    }

    var hasSignalNotch: Bool {
        self == .notch
    }

    func palette(for appearance: PrototypeAppearance) -> BadgePalette {
        switch (self, appearance) {
        case (.ember, .dark):
            BadgePalette(
                canvas: 0x07090B,
                pill: 0x0D1013,
                pillRaised: 0x13171B,
                border: 0x3A4149,
                borderStrong: 0x69747F,
                text: 0xF4F5F6,
                secondary: 0xA4AAB0,
                identity: 0xFF8A4A,
                accent: 0xFF6A1A,
                accentSoft: 0xFFB078,
                accentForeground: 0x160900,
                success: 0x43D17A,
                error: 0xFF6464,
                wallpaperStart: 0x252A30,
                wallpaperEnd: 0x0C1116,
                ribbons: [0xFF6A1A, 0xFF8A4A, 0xFFB078, 0xF0B44B]
            )
        case (.ember, .light):
            BadgePalette(
                canvas: 0xF7F3EC,
                pill: 0xFFFCF7,
                pillRaised: 0xF4EFE7,
                border: 0xB8AD9E,
                borderStrong: 0x74695D,
                text: 0x1A1714,
                secondary: 0x625C55,
                identity: 0x9E3305,
                accent: 0xBF4008,
                accentSoft: 0xD9672C,
                accentForeground: 0xFFFFFF,
                success: 0x147A42,
                error: 0xB4232C,
                wallpaperStart: 0xDDD3C5,
                wallpaperEnd: 0xF7F3EC,
                ribbons: [0x9E3305, 0xBF4008, 0xD9672C, 0x9B6300]
            )
        case (.copper, .dark):
            BadgePalette(
                canvas: 0x07090B,
                pill: 0x11100F,
                pillRaised: 0x191614,
                border: 0x514239,
                borderStrong: 0x80695A,
                text: 0xF4F5F6,
                secondary: 0xB3A79E,
                identity: 0xCF7B4B,
                accent: 0xFF6A1A,
                accentSoft: 0xF7A16F,
                accentForeground: 0x160900,
                success: 0x43D17A,
                error: 0xFF6464,
                wallpaperStart: 0x302822,
                wallpaperEnd: 0x0D0B0A,
                ribbons: [0xB96638, 0xE27B3E, 0xFF6A1A, 0xF2B06F]
            )
        case (.copper, .light):
            BadgePalette(
                canvas: 0xF7F3EC,
                pill: 0xFFFAF3,
                pillRaised: 0xF4EADF,
                border: 0xBFA995,
                borderStrong: 0x776455,
                text: 0x1A1714,
                secondary: 0x695D54,
                identity: 0x9B4B21,
                accent: 0xBF4008,
                accentSoft: 0xD8753F,
                accentForeground: 0xFFFFFF,
                success: 0x147A42,
                error: 0xB4232C,
                wallpaperStart: 0xD5C2AF,
                wallpaperEnd: 0xF8F0E7,
                ribbons: [0x87401D, 0xA94B1F, 0xBF4008, 0x956000]
            )
        case (.notch, .dark):
            BadgePalette(
                canvas: 0x07090B,
                pill: 0x0B0E11,
                pillRaised: 0x12171B,
                border: 0x424A52,
                borderStrong: 0x75818D,
                text: 0xF4F5F6,
                secondary: 0xA4AAB0,
                identity: 0xFF8A4A,
                accent: 0xFF6A1A,
                accentSoft: 0xFFB078,
                accentForeground: 0x160900,
                success: 0x43D17A,
                error: 0xFF6464,
                wallpaperStart: 0x1E2932,
                wallpaperEnd: 0x080C10,
                ribbons: [0xFF6A1A, 0xFF8A4A, 0xF0B44B, 0xFFD09A]
            )
        case (.notch, .light):
            BadgePalette(
                canvas: 0xF7F3EC,
                pill: 0xFFFCF7,
                pillRaised: 0xF2EEE8,
                border: 0xADA397,
                borderStrong: 0x6F665D,
                text: 0x1A1714,
                secondary: 0x625C55,
                identity: 0x9E3305,
                accent: 0xBF4008,
                accentSoft: 0xD9672C,
                accentForeground: 0xFFFFFF,
                success: 0x147A42,
                error: 0xB4232C,
                wallpaperStart: 0xCCD6D9,
                wallpaperEnd: 0xF6F0E7,
                ribbons: [0x9E3305, 0xBF4008, 0xC76321, 0x8A5B00]
            )
        }
    }
}

private enum PrototypeAppearance: String, CaseIterable, Identifiable {
    case light = "Light"
    case dark = "Dark"

    var id: String {
        rawValue
    }

    var scheme: ColorScheme {
        self == .light ? .light : .dark
    }
}

private enum ContrastPreview: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case increased = "Contrast+"

    var id: String {
        rawValue
    }
}

private enum MotionPreview: String, CaseIterable, Identifiable {
    case standard = "Motion"
    case reduced = "Reduced"

    var id: String {
        rawValue
    }
}

private enum BadgePreviewState: String, CaseIterable, Identifiable {
    case idle
    case hover
    case recordingQuiet
    case recordingNormal
    case workingSpinner
    case workingProgress
    case done
    case clipboardError
    case pipelineError
    case modeCycle

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .idle: "Idle"
        case .hover: "Hover"
        case .recordingQuiet: "Recording · quiet"
        case .recordingNormal: "Recording · normal"
        case .workingSpinner: "Working · spinner"
        case .workingProgress: "Working · status"
        case .done: "Done"
        case .clipboardError: "Error · clipboard"
        case .pipelineError: "Error · pipeline"
        case .modeCycle: "Mode-cycle · settled"
        }
    }

    var note: String {
        switch self {
        case .idle: "Static identity glyph"
        case .hover: "Selection · Dictate · Open"
        case .recordingQuiet: "Mic-reactive ribbons · 0:03"
        case .recordingNormal: "Mic-reactive ribbons · 0:14"
        case .workingSpinner: "Calm ribbons · indeterminate"
        case .workingProgress: "Calm ribbons · downloading 45%"
        case .done: "Checkmark + text · 0.6 s"
        case .clipboardError: "Warning icon + recovery text · 3 s"
        case .pipelineError: "Warning icon + failure text · 3 s"
        case .modeCycle: "Icon + full selection identity · 0.9 s"
        }
    }

    var width: CGFloat {
        switch self {
        case .idle: 88
        case .hover: 132
        case .modeCycle: 176
        default: 208
        }
    }

    var role: BadgeStateRole {
        switch self {
        case .idle, .hover, .modeCycle: .neutral
        case .recordingQuiet, .recordingNormal: .active
        case .workingSpinner, .workingProgress: .working
        case .done: .done
        case .clipboardError, .pipelineError: .error
        }
    }
}

private enum BadgeStateRole: String, CaseIterable, Identifiable {
    case neutral = "Neutral"
    case active = "Active"
    case working = "Working"
    case done = "Done"
    case error = "Error"

    var id: String {
        rawValue
    }

    var symbol: String {
        switch self {
        case .neutral: "minus"
        case .active: "waveform"
        case .working: "ellipsis"
        case .done: "checkmark"
        case .error: "exclamationmark"
        }
    }
}

private struct BadgePalette {
    let canvasHex: UInt32
    let pillHex: UInt32
    let pillRaisedHex: UInt32
    let borderHex: UInt32
    let borderStrongHex: UInt32
    let textHex: UInt32
    let secondaryHex: UInt32
    let identityHex: UInt32
    let accentHex: UInt32
    let accentSoftHex: UInt32
    let accentForegroundHex: UInt32
    let successHex: UInt32
    let errorHex: UInt32
    let wallpaperStartHex: UInt32
    let wallpaperEndHex: UInt32
    let ribbonHexes: [UInt32]

    init(
        canvas: UInt32,
        pill: UInt32,
        pillRaised: UInt32,
        border: UInt32,
        borderStrong: UInt32,
        text: UInt32,
        secondary: UInt32,
        identity: UInt32,
        accent: UInt32,
        accentSoft: UInt32,
        accentForeground: UInt32,
        success: UInt32,
        error: UInt32,
        wallpaperStart: UInt32,
        wallpaperEnd: UInt32,
        ribbons: [UInt32]
    ) {
        canvasHex = canvas
        pillHex = pill
        pillRaisedHex = pillRaised
        borderHex = border
        borderStrongHex = borderStrong
        textHex = text
        secondaryHex = secondary
        identityHex = identity
        accentHex = accent
        accentSoftHex = accentSoft
        accentForegroundHex = accentForeground
        successHex = success
        errorHex = error
        wallpaperStartHex = wallpaperStart
        wallpaperEndHex = wallpaperEnd
        ribbonHexes = ribbons
    }

    var canvas: Color {
        Color(hex: canvasHex)
    }

    var pill: Color {
        Color(hex: pillHex)
    }

    var pillRaised: Color {
        Color(hex: pillRaisedHex)
    }

    var border: Color {
        Color(hex: borderHex)
    }

    var borderStrong: Color {
        Color(hex: borderStrongHex)
    }

    var text: Color {
        Color(hex: textHex)
    }

    var secondary: Color {
        Color(hex: secondaryHex)
    }

    var identity: Color {
        Color(hex: identityHex)
    }

    var accent: Color {
        Color(hex: accentHex)
    }

    var accentSoft: Color {
        Color(hex: accentSoftHex)
    }

    var accentForeground: Color {
        Color(hex: accentForegroundHex)
    }

    var success: Color {
        Color(hex: successHex)
    }

    var error: Color {
        Color(hex: errorHex)
    }

    var wallpaperStart: Color {
        Color(hex: wallpaperStartHex)
    }

    var wallpaperEnd: Color {
        Color(hex: wallpaperEndHex)
    }

    var ribbons: [Color] {
        ribbonHexes.map { Color(hex: $0) }
    }

    func stateColor(for role: BadgeStateRole) -> Color {
        switch role {
        case .neutral: identity
        case .active, .working: accent
        case .done: success
        case .error: error
        }
    }
}

@main
private enum BadgePalettePrototypeApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        if CommandLine.arguments.contains("--render") {
            renderSnapshots()
            return
        }
        application.setActivationPolicy(.regular)
        let delegate = PrototypeAppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }

    @MainActor
    private static func renderSnapshots() {
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".context/badge-palette-shots", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: output,
            withIntermediateDirectories: true
        )
        if let staleFiles = try? FileManager.default.contentsOfDirectory(
            at: output,
            includingPropertiesForKeys: nil
        ) {
            for file in staleFiles where file.pathExtension == "png" {
                try? FileManager.default.removeItem(at: file)
            }
        }

        let size = CGSize(width: 1260, height: 900)
        for appearance in PrototypeAppearance.allCases {
            for treatment in PaletteTreatment.allCases {
                let root = PrototypeRoot(
                    initialTreatment: treatment,
                    initialAppearance: appearance,
                    initialMotion: .reduced
                )
                .frame(width: size.width, height: size.height)
                let hosting = NSHostingView(rootView: root)
                hosting.frame = NSRect(origin: .zero, size: size)
                hosting.appearance = NSAppearance(
                    named: appearance == .light ? .aqua : .darkAqua
                )
                let window = NSWindow(
                    contentRect: hosting.frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                window.contentView = hosting
                window.appearance = hosting.appearance
                window.orderFrontRegardless()
                RunLoop.main.run(until: Date().addingTimeInterval(0.12))
                hosting.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
                else { continue }
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:])
                else { continue }
                let name = "\(treatment.key.lowercased())-\(treatment.rawValue)-\(appearance.rawValue.lowercased()).png"
                try? png.write(to: output.appendingPathComponent(name))
                window.orderOut(nil)
            }
        }
    }
}

@MainActor
private final class PrototypeAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hosting = NSHostingController(rootView: PrototypeRoot())
        let window = NSWindow(contentViewController: hosting)
        window.title = "FoldWise Badge palette prototype"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.setContentSize(CGSize(width: 1260, height: 900))
        window.contentMinSize = CGSize(width: 1060, height: 760)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

private struct PrototypeRoot: View {
    @State private var treatment: PaletteTreatment
    @State private var appearance: PrototypeAppearance
    @State private var contrast: ContrastPreview
    @State private var motion: MotionPreview

    init(
        initialTreatment: PaletteTreatment = .ember,
        initialAppearance: PrototypeAppearance = .dark,
        initialContrast: ContrastPreview = .standard,
        initialMotion: MotionPreview = .standard
    ) {
        _treatment = State(initialValue: initialTreatment)
        _appearance = State(initialValue: initialAppearance)
        _contrast = State(initialValue: initialContrast)
        _motion = State(initialValue: initialMotion)
    }

    private var palette: BadgePalette {
        treatment.palette(for: appearance)
    }

    var body: some View {
        ZStack {
            palette.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                PrototypeTitlebar(palette: palette)
                Rectangle()
                    .fill(contrast == .increased ? palette.borderStrong : palette.border)
                    .frame(height: contrast == .increased ? 2 : 1)
                BadgeGallery(
                    treatment: treatment,
                    appearance: appearance,
                    contrast: contrast,
                    motion: motion,
                    palette: palette
                )
            }
            .animation(
                motion == .reduced ? nil : .easeOut(duration: 0.16),
                value: treatment
            )

            VStack {
                Spacer()
                ReviewBar(
                    treatment: $treatment,
                    appearance: $appearance,
                    contrast: $contrast,
                    motion: $motion
                )
                .padding(.bottom, 12)
            }
        }
        .preferredColorScheme(appearance.scheme)
        .frame(minWidth: 1060, minHeight: 760)
    }
}

private struct PrototypeTitlebar: View {
    let palette: BadgePalette

    var body: some View {
        HStack(spacing: 10) {
            Spacer().frame(width: 74)
            WaveMark(color: palette.accent)
                .frame(width: 21, height: 18)
            Text("FoldWise Voice")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(palette.secondary)
            Text("BADGE PALETTE LAB")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(palette.secondary.opacity(0.72))
            Spacer()
        }
        .frame(height: 38)
        .background(palette.pill)
    }
}

private struct BadgeGallery: View {
    let treatment: PaletteTreatment
    let appearance: PrototypeAppearance
    let contrast: ContrastPreview
    let motion: MotionPreview
    let palette: BadgePalette

    private let columns = [
        GridItem(.flexible(minimum: 280), spacing: 12),
        GridItem(.flexible(minimum: 280), spacing: 12),
        GridItem(.flexible(minimum: 280), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                StateRoleStrip(palette: palette)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(BadgePreviewState.allCases) { state in
                        StatePreviewCard(
                            state: state,
                            treatment: treatment,
                            palette: palette,
                            contrast: contrast,
                            motion: motion
                        )
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 82)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(treatment.key) — \(treatment.title)")
                    .font(.system(size: 30, weight: .semibold))
                    .tracking(-0.55)
                    .foregroundStyle(palette.text)
                Text(treatment.thesis)
                    .font(.system(size: 13.5))
                    .foregroundStyle(palette.secondary)
                Text(treatment.tradeoff)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.secondary.opacity(0.82))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text("ACTUAL SIZE · 38 PT HEIGHT")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.65)
                    .foregroundStyle(palette.accent)
                Text("88 · 132 · 176 · 208 pt widths")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(palette.secondary)
                Text("\(appearance.rawValue) · \(contrast.rawValue) · \(motion.rawValue)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(palette.secondary.opacity(0.78))
            }
        }
    }
}

private struct StateRoleStrip: View {
    let palette: BadgePalette

    var body: some View {
        HStack(spacing: 0) {
            ForEach(BadgeStateRole.allCases) { role in
                HStack(spacing: 8) {
                    Image(systemName: role.symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.stateColor(for: role))
                        .frame(width: 18, height: 18)
                        .background(
                            palette.stateColor(for: role).opacity(0.13),
                            in: Circle()
                        )
                    Text(role.rawValue)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(palette.text)
                }
                .frame(maxWidth: .infinity)
                if role != .error {
                    Rectangle()
                        .fill(palette.border)
                        .frame(width: 1, height: 24)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(palette.pillRaised, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(palette.border, lineWidth: 1)
        }
    }
}

private struct StatePreviewCard: View {
    let state: BadgePreviewState
    let treatment: PaletteTreatment
    let palette: BadgePalette
    let contrast: ContrastPreview
    let motion: MotionPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Wallpaper(palette: palette)
                BadgePreview(
                    state: state,
                    treatment: treatment,
                    palette: palette,
                    contrast: contrast,
                    motion: motion
                )
            }
            .frame(height: 80)
            .clipped()

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Text(state.note)
                        .font(.system(size: 9.5))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(Int(state.width)) × 38")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.secondary.opacity(0.78))
            }
            .padding(11)
            .background(palette.pillRaised)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    contrast == .increased ? palette.borderStrong : palette.border,
                    lineWidth: contrast == .increased ? 2 : 1
                )
        }
    }
}

private struct Wallpaper: View {
    let palette: BadgePalette

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [palette.wallpaperStart, palette.wallpaperEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(palette.accent.opacity(0.08))
                .frame(width: 150, height: 150)
                .blur(radius: 32)
                .offset(x: 100, y: -35)
            VStack(spacing: 8) {
                ForEach(0 ..< 4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(palette.text.opacity(index == 0 ? 0.09 : 0.045))
                        .frame(width: CGFloat(190 - index * 22), height: 5)
                }
            }
            .offset(x: -84, y: -8)
        }
    }
}

private struct BadgePreview: View {
    let state: BadgePreviewState
    let treatment: PaletteTreatment
    let palette: BadgePalette
    let contrast: ContrastPreview
    let motion: MotionPreview

    var body: some View {
        ZStack {
            Capsule().fill(palette.pill.opacity(0.97))
            content
            if treatment.hasSignalNotch {
                SignalNotch(color: palette.stateColor(for: state.role))
            }
        }
        .overlay {
            Capsule()
                .strokeBorder(
                    borderColor,
                    lineWidth: contrast == .increased ? 2 : 1
                )
        }
        .frame(width: state.width, height: 38)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(state.title)
    }

    private var borderColor: Color {
        switch state.role {
        case .neutral:
            contrast == .increased ? palette.borderStrong : palette.border
        case .active, .working:
            palette.accent.opacity(contrast == .increased ? 1 : 0.78)
        case .done:
            palette.success.opacity(contrast == .increased ? 1 : 0.82)
        case .error:
            palette.error
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle:
            IdleGlyph(treatment: treatment, palette: palette)
        case .hover:
            HoverControls(treatment: treatment, palette: palette)
        case .recordingQuiet:
            recording(amplitude: 0.18, timer: "0:03")
        case .recordingNormal:
            recording(amplitude: 0.38, timer: "0:14")
        case .workingSpinner:
            HStack(spacing: 10) {
                RibbonPreview(
                    live: false,
                    amplitude: 0.18,
                    colors: palette.ribbons,
                    reducedMotion: motion == .reduced
                )
                .frame(height: 20)
                SpinnerPreview(
                    color: palette.accent,
                    reducedMotion: motion == .reduced
                )
            }
            .padding(.horizontal, 13)
        case .workingProgress:
            HStack(spacing: 10) {
                RibbonPreview(
                    live: false,
                    amplitude: 0.18,
                    colors: palette.ribbons,
                    reducedMotion: motion == .reduced
                )
                .frame(height: 20)
                Text("downloading 45%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 13)
        case .done:
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.success)
                Text("inserted")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.text)
            }
        case .clipboardError:
            errorLine("copied — press ⌘V")
        case .pipelineError:
            errorLine("something went wrong")
        case .modeCycle:
            HStack(spacing: 8) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.identity)
                Text("Email")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.text)
            }
        }
    }

    private func recording(amplitude: Double, timer: String) -> some View {
        HStack(spacing: 10) {
            RibbonPreview(
                live: true,
                amplitude: amplitude,
                colors: palette.ribbons,
                reducedMotion: motion == .reduced
            )
            .frame(height: 20)
            Text(timer)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.text)
        }
        .padding(.horizontal, 13)
    }

    private func errorLine(_ text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.error)
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 13)
    }
}

private struct SignalNotch: View {
    let color: Color

    var body: some View {
        HStack {
            Capsule()
                .fill(color)
                .frame(width: 3, height: 12)
                .padding(.leading, 8)
            Spacer()
        }
        .allowsHitTesting(false)
    }
}

private struct IdleGlyph: View {
    let treatment: PaletteTreatment
    let palette: BadgePalette
    private let heights: [CGFloat] = [3.5, 3.5, 3.5, 12, 3.5, 7, 3.5]

    var body: some View {
        HStack(alignment: .center, spacing: 3.5) {
            ForEach(Array(heights.enumerated()), id: \.offset) { item in
                Capsule()
                    .fill(color(for: item.offset, height: item.element))
                    .frame(width: 3.5, height: item.element)
            }
        }
        .accessibilityHidden(true)
    }

    private func color(for index: Int, height: CGFloat) -> Color {
        switch treatment {
        case .ember:
            height > 3.5 ? palette.identity : palette.secondary
        case .copper:
            index == 3 ? palette.identity : palette.secondary
        case .notch:
            palette.secondary
        }
    }
}

private struct HoverControls: View {
    let treatment: PaletteTreatment
    let palette: BadgePalette

    var body: some View {
        HStack(spacing: 8) {
            roundButton(symbol: "sparkles", emphasized: false)
            roundButton(symbol: "mic.fill", emphasized: true)
            roundButton(
                symbol: "arrow.up.left.and.arrow.down.right",
                emphasized: false
            )
        }
        .padding(.horizontal, 6)
    }

    private func roundButton(symbol: String, emphasized: Bool) -> some View {
        let diameter: CGFloat = emphasized ? 30 : 28
        return Image(systemName: symbol)
            .font(.system(size: diameter * 0.36, weight: .semibold))
            .foregroundStyle(emphasized ? palette.accentForeground : palette.identity)
            .frame(width: diameter, height: diameter)
            .background(
                emphasized
                    ? palette.accent
                    : palette.identity.opacity(treatment == .copper ? 0.14 : 0.10),
                in: Circle()
            )
    }
}

private struct SpinnerPreview: View {
    let color: Color
    let reducedMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reducedMotion)) { context in
            let turn = reducedMotion
                ? 0.12
                : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .frame(width: 12, height: 12)
                .rotationEffect(.degrees(turn * 360))
        }
        .allowsHitTesting(false)
    }
}

private struct RibbonPreview: View {
    let live: Bool
    let amplitude: Double
    let colors: [Color]
    let reducedMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reducedMotion)) { context in
            let time = reducedMotion ? 730.0 : context.date.timeIntervalSinceReferenceDate * 1000
            Canvas { graphics, size in
                drawBaseline(&graphics, size: size)
                drawStrands(&graphics, size: size, time: time)
            }
        }
        .allowsHitTesting(false)
    }

    private func drawBaseline(_ graphics: inout GraphicsContext, size: CGSize) {
        var line = Path()
        line.move(to: CGPoint(x: 0, y: size.height / 2))
        line.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        let gradient = Gradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: colors[0].opacity(0.45), location: 0.15),
            .init(color: colors[1].opacity(0.45), location: 0.85),
            .init(color: .clear, location: 1),
        ])
        graphics.stroke(
            line,
            with: .linearGradient(
                gradient,
                startPoint: .zero,
                endPoint: CGPoint(x: size.width, y: 0)
            ),
            lineWidth: 1
        )
    }

    private func drawStrands(
        _ graphics: inout GraphicsContext,
        size: CGSize,
        time: Double
    ) {
        let width = size.width
        let height = size.height
        let speed = live ? 0.0009 : 0.00045
        for strand in 0 ..< min(4, colors.count) {
            let index = Double(strand)
            let phase = index * 1.7
            let frequency = 0.010 + index * 0.0032
            var path = Path()
            var x = 0.0
            while x <= width {
                let unit = x / width
                let envelopeUnit = min(1, max(0, (unit - 0.09) / 0.82))
                let envelope = pow(sin(.pi * envelopeUnit), 2)
                let y = height / 2
                    + sin(x * frequency + time * speed * (1 + index * 0.13) + phase)
                    * height * amplitude * envelope
                if x == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                x += 2
            }
            graphics.stroke(
                path,
                with: .color(colors[strand].opacity(0.76)),
                lineWidth: strand == 0 ? 1.6 : 1
            )
        }
    }
}

private struct WaveMark: View {
    let color: Color
    private let heights: [CGFloat] = [5, 11, 17, 9, 15, 7, 12]

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(heights.enumerated()), id: \.offset) { item in
                    Capsule()
                        .fill(color)
                        .frame(width: 2, height: min(item.element, geometry.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

private struct ReviewBar: View {
    @Binding var treatment: PaletteTreatment
    @Binding var appearance: PrototypeAppearance
    @Binding var contrast: ContrastPreview
    @Binding var motion: MotionPreview

    var body: some View {
        HStack(spacing: 9) {
            Button { cycle(-1) } label: {
                Image(systemName: "chevron.left")
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command])
            .help("Previous treatment (Command–Left Arrow)")

            Text("\(treatment.key) — \(treatment.title)")
                .font(.system(size: 11.5, weight: .semibold))
                .frame(minWidth: 124)

            Button { cycle(1) } label: {
                Image(systemName: "chevron.right")
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command])
            .help("Next treatment (Command–Right Arrow)")

            Divider().frame(height: 18)

            Picker("Appearance", selection: $appearance) {
                ForEach(PrototypeAppearance.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 110)

            Picker("Contrast", selection: $contrast) {
                ForEach(ContrastPreview.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 146)

            Picker("Motion", selection: $motion) {
                ForEach(MotionPreview.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 128)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 11))
        .shadow(color: .black.opacity(0.28), radius: 16, y: 6)
        .environment(\.colorScheme, .dark)
    }

    private func cycle(_ offset: Int) {
        let treatments = PaletteTreatment.allCases
        guard let index = treatments.firstIndex(of: treatment) else { return }
        treatment = treatments[
            (index + offset + treatments.count) % treatments.count
        ]
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
