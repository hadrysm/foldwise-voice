// THROWAWAY PROTOTYPE — visual decision aid for Wayfinder ticket
// "Calibrate the orange-led cross-appearance visual grammar".
//
// Three orange-led calibrations of the same component/state sampler, switchable
// from the bottom review bar. This is isolated from production navigation and
// logic on purpose; the approved answer belongs in the issue and later visual
// specification, not in this prototype's abstractions.

import AppKit
import SwiftUI

private enum GrammarVariant: String, CaseIterable, Identifiable {
    case ember
    case ledger
    case relay

    var id: String {
        rawValue
    }

    var key: String {
        switch self {
        case .ember: "A"
        case .ledger: "B"
        case .relay: "C"
        }
    }

    var title: String {
        switch self {
        case .ember: "Ember Edge"
        case .ledger: "Signal Ledger"
        case .relay: "Warm Relay"
        }
    }

    var thesis: String {
        switch self {
        case .ember:
            "Orange enters from an edge; typography and layered surfaces do the rest."
        case .ledger:
            "A precise working ledger: square rhythm, tabular labels, orange rules, zero glow."
        case .relay:
            "A warmer native control room: softer materials, generous rhythm, decisive orange actions."
        }
    }

    var metrics: GrammarMetrics {
        switch self {
        case .ember:
            GrammarMetrics(radius: 8, controlRadius: 6, gap: 12, inset: 16, border: 1)
        case .ledger:
            GrammarMetrics(radius: 4, controlRadius: 3, gap: 8, inset: 14, border: 1)
        case .relay:
            GrammarMetrics(radius: 12, controlRadius: 9, gap: 16, inset: 18, border: 1)
        }
    }

    func palette(for appearance: PrototypeAppearance) -> Palette {
        switch (self, appearance) {
        case (.ember, .dark):
            Palette(
                canvas: 0x07090B, sidebar: 0x090B0E, surface: 0x0D1013,
                raised: 0x13171B, hover: 0x1A2026, border: 0x262C32,
                borderStrong: 0x5B6570, text: 0xF4F5F6, secondary: 0xA4AAB0,
                tertiary: 0x747C85, accent: 0xFF6A1A, accentHover: 0xFF8A4A,
                accentText: 0x160900, success: 0x43D17A, warning: 0xF0B44B,
                error: 0xFF6464
            )
        case (.ember, .light):
            Palette(
                canvas: 0xF7F3EC, sidebar: 0xEEE8DE, surface: 0xFFFCF7,
                raised: 0xF4EFE7, hover: 0xEAE2D7, border: 0xD8CFC1,
                borderStrong: 0x978B7C, text: 0x1A1714, secondary: 0x625C55,
                tertiary: 0x766E65, accent: 0xBF4008, accentHover: 0x9E3305,
                accentText: 0xFFFFFF, success: 0x147A42, warning: 0x865B00,
                error: 0xB4232C
            )
        case (.ledger, .dark):
            Palette(
                canvas: 0x060708, sidebar: 0x08090A, surface: 0x0B0D0F,
                raised: 0x101316, hover: 0x171B1F, border: 0x30363C,
                borderStrong: 0x5B646D, text: 0xF2F2EF, secondary: 0xB0B1AC,
                tertiary: 0x7F827D, accent: 0xFF751F, accentHover: 0xFF9B5C,
                accentText: 0x160A02, success: 0x55D88A, warning: 0xF4C45C,
                error: 0xFF6B72
            )
        case (.ledger, .light):
            Palette(
                canvas: 0xF2F0EA, sidebar: 0xE9E6DE, surface: 0xFBFAF6,
                raised: 0xF0EEE7, hover: 0xE4E0D7, border: 0xCBC6BB,
                borderStrong: 0x948D81, text: 0x171716, secondary: 0x555650,
                tertiary: 0x70726B, accent: 0xB93D06, accentHover: 0x922E02,
                accentText: 0xFFFFFF, success: 0x147640, warning: 0x7B5600,
                error: 0xAC2630
            )
        case (.relay, .dark):
            Palette(
                canvas: 0x0D0B09, sidebar: 0x120F0C, surface: 0x17130F,
                raised: 0x1E1914, hover: 0x29211A, border: 0x3A3027,
                borderStrong: 0x755F4B, text: 0xFAF5EF, secondary: 0xBDB1A5,
                tertiary: 0x887B70, accent: 0xFF7126, accentHover: 0xFF955D,
                accentText: 0x1A0901, success: 0x55D68A, warning: 0xF0BE58,
                error: 0xFF6A66
            )
        case (.relay, .light):
            Palette(
                canvas: 0xF6F0E7, sidebar: 0xECE3D6, surface: 0xFFF9F0,
                raised: 0xF3E9DC, hover: 0xE8DACA, border: 0xD6C7B5,
                borderStrong: 0x9D8975, text: 0x201A15, secondary: 0x675C52,
                tertiary: 0x776A60, accent: 0xBD410A, accentHover: 0x963104,
                accentText: 0xFFFFFF, success: 0x197943, warning: 0x815800,
                error: 0xB52A30
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

private enum CuePreview: String, CaseIterable, Identifiable {
    case standard = "Cues"
    case emphasized = "Cues+"

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

private struct GrammarMetrics {
    let radius: CGFloat
    let controlRadius: CGFloat
    let gap: CGFloat
    let inset: CGFloat
    let border: CGFloat
}

private struct Palette {
    let canvasHex: UInt32
    let sidebarHex: UInt32
    let surfaceHex: UInt32
    let raisedHex: UInt32
    let hoverHex: UInt32
    let borderHex: UInt32
    let borderStrongHex: UInt32
    let textHex: UInt32
    let secondaryHex: UInt32
    let tertiaryHex: UInt32
    let accentHex: UInt32
    let accentHoverHex: UInt32
    let accentTextHex: UInt32
    let successHex: UInt32
    let warningHex: UInt32
    let errorHex: UInt32

    init(
        canvas: UInt32, sidebar: UInt32, surface: UInt32, raised: UInt32,
        hover: UInt32, border: UInt32, borderStrong: UInt32, text: UInt32,
        secondary: UInt32, tertiary: UInt32, accent: UInt32,
        accentHover: UInt32, accentText: UInt32, success: UInt32,
        warning: UInt32, error: UInt32
    ) {
        canvasHex = canvas
        sidebarHex = sidebar
        surfaceHex = surface
        raisedHex = raised
        hoverHex = hover
        borderHex = border
        borderStrongHex = borderStrong
        textHex = text
        secondaryHex = secondary
        tertiaryHex = tertiary
        accentHex = accent
        accentHoverHex = accentHover
        accentTextHex = accentText
        successHex = success
        warningHex = warning
        errorHex = error
    }

    var canvas: Color {
        Color(hex: canvasHex)
    }

    var sidebar: Color {
        Color(hex: sidebarHex)
    }

    var surface: Color {
        Color(hex: surfaceHex)
    }

    var raised: Color {
        Color(hex: raisedHex)
    }

    var hover: Color {
        Color(hex: hoverHex)
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

    var tertiary: Color {
        Color(hex: tertiaryHex)
    }

    var accent: Color {
        Color(hex: accentHex)
    }

    var accentHover: Color {
        Color(hex: accentHoverHex)
    }

    var accentText: Color {
        Color(hex: accentTextHex)
    }

    var success: Color {
        Color(hex: successHex)
    }

    var warning: Color {
        Color(hex: warningHex)
    }

    var error: Color {
        Color(hex: errorHex)
    }

    func hex(_ value: UInt32) -> String {
        String(format: "#%06X", value)
    }
}

@main
private enum VisualGrammarPrototypeApp {
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
            .appendingPathComponent(".context/visual-grammar-shots", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: output, withIntermediateDirectories: true
        )
        if let staleFiles = try? FileManager.default.contentsOfDirectory(
            at: output, includingPropertiesForKeys: nil
        ) {
            for file in staleFiles where file.pathExtension == "png" {
                try? FileManager.default.removeItem(at: file)
            }
        }

        let size = CGSize(width: 1180, height: 780)
        for appearance in PrototypeAppearance.allCases {
            for variant in GrammarVariant.allCases {
                let root = PrototypeRoot(
                    initialVariant: variant,
                    initialAppearance: appearance
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
                RunLoop.main.run(until: Date().addingTimeInterval(0.08))
                hosting.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
                else { continue }
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:])
                else { continue }
                let name = "\(variant.key.lowercased())-\(variant.rawValue)-\(appearance.rawValue.lowercased()).png"
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
        window.title = "FoldWise visual grammar calibration"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.setContentSize(CGSize(width: 1180, height: 780))
        window.contentMinSize = CGSize(width: 980, height: 700)
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
    @State private var variant: GrammarVariant
    @State private var appearance: PrototypeAppearance
    @State private var contrast: ContrastPreview
    @State private var cues: CuePreview
    @State private var motion: MotionPreview

    init(
        initialVariant: GrammarVariant = .ember,
        initialAppearance: PrototypeAppearance = .dark,
        initialContrast: ContrastPreview = .standard,
        initialCues: CuePreview = .emphasized,
        initialMotion: MotionPreview = .standard
    ) {
        _variant = State(initialValue: initialVariant)
        _appearance = State(initialValue: initialAppearance)
        _contrast = State(initialValue: initialContrast)
        _cues = State(initialValue: initialCues)
        _motion = State(initialValue: initialMotion)
    }

    private var palette: Palette {
        variant.palette(for: appearance)
    }

    var body: some View {
        ZStack {
            palette.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                PrototypeTitlebar(palette: palette)
                Rectangle()
                    .fill(contrast == .increased ? palette.borderStrong : palette.border)
                    .frame(height: contrast == .increased ? 2 : 1)
                GrammarCanvas(
                    variant: variant,
                    appearance: appearance,
                    palette: palette,
                    contrast: contrast,
                    cues: cues,
                    motion: motion
                )
            }
            .animation(
                motion == .reduced ? nil : .easeOut(duration: 0.16),
                value: variant
            )

            VStack {
                Spacer()
                ReviewBar(
                    variant: $variant,
                    appearance: $appearance,
                    contrast: $contrast,
                    cues: $cues,
                    motion: $motion
                )
                .padding(.bottom, 12)
            }
        }
        .preferredColorScheme(appearance.scheme)
        .frame(minWidth: 980, minHeight: 700)
    }
}

private struct PrototypeTitlebar: View {
    let palette: Palette

    var body: some View {
        HStack(spacing: 10) {
            Spacer().frame(width: 74)
            WaveMark(color: palette.accent)
                .frame(width: 21, height: 18)
            Text("FoldWise Voice")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(palette.secondary)
            Text("VISUAL GRAMMAR LAB")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(palette.tertiary)
            Spacer()
        }
        .frame(height: 38)
        .background(palette.sidebar)
    }
}

private struct GrammarCanvas: View {
    let variant: GrammarVariant
    let appearance: PrototypeAppearance
    let palette: Palette
    let contrast: ContrastPreview
    let cues: CuePreview
    let motion: MotionPreview

    private var metrics: GrammarMetrics {
        variant.metrics
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                layout
            }
            .padding(.horizontal, 30)
            .padding(.top, 24)
            .padding(.bottom, 86)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(variant.key) — \(variant.title)")
                    .font(.system(size: variant == .ledger ? 27 : 30, weight: .semibold))
                    .tracking(variant == .ledger ? -0.25 : -0.55)
                    .foregroundStyle(palette.text)
                Text(variant.thesis)
                    .font(.system(size: 13.5))
                    .foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(appearance.rawValue.uppercased()) / \(contrast.rawValue.uppercased())")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(palette.accent)
                Text("SF Pro + SF Mono · 4 pt base grid")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(palette.tertiary)
                Text(motion == .reduced ? "State changes: immediate" : "State changes: 160 ms ease-out")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(palette.tertiary)
            }
        }
    }

    @ViewBuilder
    private var layout: some View {
        switch variant {
        case .ember:
            HStack(alignment: .top, spacing: metrics.gap) {
                VStack(spacing: metrics.gap) {
                    PalettePanel(palette: palette, variant: variant, contrast: contrast)
                    TypePanel(palette: palette, variant: variant, contrast: contrast)
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: metrics.gap) {
                    ComponentPanel(
                        palette: palette, variant: variant,
                        contrast: contrast, cues: cues
                    )
                    BadgePanel(
                        palette: palette, variant: variant,
                        contrast: contrast, cues: cues
                    )
                }
                .frame(maxWidth: .infinity)
            }
        case .ledger:
            VStack(spacing: metrics.gap) {
                HStack(alignment: .top, spacing: metrics.gap) {
                    PalettePanel(palette: palette, variant: variant, contrast: contrast)
                    TypePanel(palette: palette, variant: variant, contrast: contrast)
                    BadgePanel(
                        palette: palette, variant: variant,
                        contrast: contrast, cues: cues
                    )
                }
                ComponentPanel(
                    palette: palette, variant: variant,
                    contrast: contrast, cues: cues
                )
            }
        case .relay:
            VStack(spacing: metrics.gap) {
                ComponentPanel(
                    palette: palette, variant: variant,
                    contrast: contrast, cues: cues
                )
                HStack(alignment: .top, spacing: metrics.gap) {
                    TypePanel(palette: palette, variant: variant, contrast: contrast)
                    PalettePanel(palette: palette, variant: variant, contrast: contrast)
                    BadgePanel(
                        palette: palette, variant: variant,
                        contrast: contrast, cues: cues
                    )
                }
            }
        }
    }
}

private struct PalettePanel: View {
    let palette: Palette
    let variant: GrammarVariant
    let contrast: ContrastPreview

    private var swatches: [(String, UInt32)] {
        [
            ("Canvas", palette.canvasHex),
            ("Surface", palette.surfaceHex),
            ("Raised", palette.raisedHex),
            ("Border", contrast == .increased ? palette.borderStrongHex : palette.borderHex),
            ("Text", palette.textHex),
            ("Secondary", palette.secondaryHex),
            ("Orange", palette.accentHex),
            ("Error", palette.errorHex),
        ]
    }

    var body: some View {
        SurfacePanel(
            title: "Palette",
            subtitle: "Semantic, appearance-specific, no opacity for essential contrast",
            palette: palette,
            variant: variant,
            contrast: contrast
        ) {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 8
            ) {
                ForEach(swatches, id: \.0) { swatch in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: swatch.1))
                            .frame(width: 28, height: 28)
                            .overlay {
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(palette.borderStrong, lineWidth: 1)
                            }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(swatch.0)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(palette.secondary)
                            Text(palette.hex(swatch.1))
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(palette.tertiary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}

private struct TypePanel: View {
    let palette: Palette
    let variant: GrammarVariant
    let contrast: ContrastPreview

    var body: some View {
        SurfacePanel(
            title: "Typography + rhythm",
            subtitle: "SF Pro for language, SF Mono only for time, keys, and model data",
            palette: palette,
            variant: variant,
            contrast: contrast
        ) {
            VStack(alignment: .leading, spacing: variant.metrics.gap) {
                TypeSample(
                    role: "DISPLAY / 30 · SEMIBOLD · −0.5",
                    sample: "Ready when you are.",
                    font: .system(size: 24, weight: .semibold),
                    color: palette.text
                )
                TypeSample(
                    role: "SECTION / 11 · BOLD · +0.7",
                    sample: "TODAY",
                    font: .system(size: 11, weight: .bold),
                    color: palette.secondary,
                    tracking: 0.7
                )
                TypeSample(
                    role: "BODY / 13.5 · REGULAR",
                    sample: "Hold right ⌘ and speak — release to insert.",
                    font: .system(size: 13.5),
                    color: palette.secondary
                )
                TypeSample(
                    role: "DATA / 11 · MEDIUM · MONO",
                    sample: "18:51   parakeet-tdt-v3   125 wpm",
                    font: .system(size: 11, weight: .medium, design: .monospaced),
                    color: palette.tertiary
                )
                HStack(spacing: 8) {
                    RulePill(text: "4", palette: palette)
                    RulePill(text: "8", palette: palette)
                    RulePill(text: "12", palette: palette)
                    RulePill(text: "16", palette: palette)
                    Text("Base spacing · 4 pt")
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.tertiary)
                }
            }
        }
    }
}

private struct ComponentPanel: View {
    let palette: Palette
    let variant: GrammarVariant
    let contrast: ContrastPreview
    let cues: CuePreview

    @State private var hoveringRow = false
    @State private var hoveringButton = false

    private var metrics: GrammarMetrics {
        variant.metrics
    }

    var body: some View {
        SurfacePanel(
            title: "Component grammar",
            subtitle: "Selection, hover, focus, status, and actions keep shape and text cues",
            palette: palette,
            variant: variant,
            contrast: contrast
        ) {
            if variant == .ledger {
                HStack(alignment: .top, spacing: metrics.gap) {
                    navigationSamples
                    interactionSamples
                    statusSamples
                }
            } else {
                HStack(alignment: .top, spacing: metrics.gap) {
                    VStack(spacing: 8) { navigationSamples }
                    VStack(spacing: 8) { interactionSamples }
                    VStack(spacing: 8) { statusSamples }
                }
            }
        }
    }

    private var navigationSamples: some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroLabel("SELECTION", palette: palette)
            NavigationRow(
                title: "Home", symbol: "house",
                active: true, palette: palette, variant: variant,
                emphasizedCues: cues == .emphasized
            )
            NavigationRow(
                title: "History", symbol: "clock",
                active: false, palette: palette, variant: variant,
                emphasizedCues: cues == .emphasized
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var interactionSamples: some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroLabel("POINTER + FOCUS", palette: palette)
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundStyle(palette.accent)
                Text("Dictation row")
                    .foregroundStyle(palette.text)
                Spacer()
                Image(systemName: hoveringRow ? "doc.on.doc.fill" : "ellipsis")
                    .foregroundStyle(palette.secondary)
            }
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(hoveringRow ? palette.hover : palette.raised)
            .clipShape(RoundedRectangle(cornerRadius: metrics.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: metrics.controlRadius)
                    .strokeBorder(
                        contrast == .increased ? palette.borderStrong : palette.border,
                        lineWidth: contrast == .increased ? 2 : 1
                    )
            }
            .onHover { hoveringRow = $0 }

            Text("Focus ring: 2 pt orange + 2 pt canvas gap")
                .font(.system(size: 10.5))
                .foregroundStyle(palette.text)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: metrics.controlRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: metrics.controlRadius + 2)
                        .strokeBorder(palette.canvas, lineWidth: 4)
                        .padding(-4)
                    RoundedRectangle(cornerRadius: metrics.controlRadius + 4)
                        .strokeBorder(palette.accent, lineWidth: 2)
                        .padding(-6)
                }
                .padding(6)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusSamples: some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroLabel("ACTION + STATUS", palette: palette)
            Button {} label: {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text(hoveringButton ? "Download model" : "Download")
                }
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(palette.accentText)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(hoveringButton ? palette.accentHover : palette.accent)
                .clipShape(RoundedRectangle(cornerRadius: metrics.controlRadius))
            }
            .buttonStyle(.plain)
            .onHover { hoveringButton = $0 }

            StatusLine(
                symbol: cues == .emphasized ? "checkmark.seal.fill" : "checkmark.circle.fill",
                text: "All systems go",
                color: palette.success,
                palette: palette,
                underlined: cues == .emphasized
            )
            StatusLine(
                symbol: cues == .emphasized ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill",
                text: "Model unavailable",
                color: palette.error,
                palette: palette,
                underlined: cues == .emphasized
            )
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BadgePanel: View {
    let palette: Palette
    let variant: GrammarVariant
    let contrast: ContrastPreview
    let cues: CuePreview

    var body: some View {
        SurfacePanel(
            title: "Badge bridge",
            subtitle: "Same orange family; fixed 38 pt capsule and semantic error remain distinct",
            palette: palette,
            variant: variant,
            contrast: contrast
        ) {
            VStack(alignment: .leading, spacing: 9) {
                BadgeSample(
                    kind: .idle, palette: palette,
                    contrast: contrast, cues: cues
                )
                BadgeSample(
                    kind: .recording, palette: palette,
                    contrast: contrast, cues: cues
                )
                BadgeSample(
                    kind: .done, palette: palette,
                    contrast: contrast, cues: cues
                )
                BadgeSample(
                    kind: .error, palette: palette,
                    contrast: contrast, cues: cues
                )
                Text("No glow · fixed silhouette · icon + text + border error")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(palette.tertiary)
            }
        }
    }
}

private enum BadgeSampleKind {
    case idle
    case recording
    case done
    case error

    var width: CGFloat {
        switch self {
        case .idle: 88
        default: 208
        }
    }
}

private struct BadgeSample: View {
    let kind: BadgeSampleKind
    let palette: Palette
    let contrast: ContrastPreview
    let cues: CuePreview

    var body: some View {
        HStack(spacing: 8) {
            switch kind {
            case .idle:
                WaveMark(color: palette.accent)
                    .frame(width: 30, height: 16)
            case .recording:
                WaveMark(color: palette.accent)
                    .frame(width: 38, height: 18)
                Text("0:12")
            case .done:
                Image(systemName: cues == .emphasized ? "checkmark.seal.fill" : "checkmark")
                Text("inserted")
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                Text("copied — press ⌘V")
            }
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(kind == .error ? palette.error : palette.text)
        .frame(width: kind.width, height: 38)
        .background(palette.surface, in: Capsule())
        .overlay {
            Capsule().strokeBorder(
                kind == .error
                    ? palette.error
                    : (contrast == .increased ? palette.borderStrong : palette.border),
                lineWidth: contrast == .increased || kind == .error ? 2 : 1
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SurfacePanel<Content: View>: View {
    let title: String
    let subtitle: String
    let palette: Palette
    let variant: GrammarVariant
    let contrast: ContrastPreview
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: variant.metrics.gap) {
            HStack(alignment: .top, spacing: 10) {
                if variant == .ember {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(palette.accent)
                        .frame(width: 2, height: 31)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.tertiary)
                        .lineLimit(2)
                }
                Spacer()
                if variant == .ledger {
                    Rectangle().fill(palette.accent).frame(width: 36, height: 2)
                }
            }
            content
        }
        .padding(variant.metrics.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: variant.metrics.radius))
        .overlay {
            RoundedRectangle(cornerRadius: variant.metrics.radius)
                .strokeBorder(
                    contrast == .increased ? palette.borderStrong : palette.border,
                    lineWidth: contrast == .increased ? 2 : variant.metrics.border
                )
        }
    }
}

private struct NavigationRow: View {
    let title: String
    let symbol: String
    let active: Bool
    let palette: Palette
    let variant: GrammarVariant
    let emphasizedCues: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .frame(width: 17)
                .foregroundStyle(active ? palette.accent : palette.tertiary)
            Text(title)
                .font(.system(size: 11.5, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? palette.text : palette.secondary)
            Spacer()
            if active && emphasizedCues {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.accent)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(active ? palette.raised : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: variant.metrics.controlRadius))
        .overlay(alignment: variant == .ledger ? .top : .leading) {
            if active {
                Rectangle()
                    .fill(palette.accent)
                    .frame(
                        width: variant == .ledger ? nil : 2,
                        height: variant == .ledger ? 2 : 20
                    )
                    .padding(variant == .ledger ? EdgeInsets() : EdgeInsets(top: 7, leading: 0, bottom: 7, trailing: 0))
            }
        }
    }
}

private struct StatusLine: View {
    let symbol: String
    let text: String
    let color: Color
    let palette: Palette
    let underlined: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(text)
                .foregroundStyle(palette.text)
                .underline(underlined)
            Spacer()
        }
        .font(.system(size: 10.5, weight: .medium))
        .padding(.horizontal, 9)
        .frame(minHeight: 29)
        .background(palette.raised)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private struct TypeSample: View {
    let role: String
    let sample: String
    let font: Font
    let color: Color
    var tracking: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(role)
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .foregroundStyle(color.opacity(0.62))
            Text(sample)
                .font(font)
                .tracking(tracking)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

private struct RulePill: View {
    let text: String
    let palette: Palette

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(palette.text)
            .frame(width: 24, height: 20)
            .background(palette.raised, in: RoundedRectangle(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(palette.border, lineWidth: 1)
            }
    }
}

private struct MicroLabel: View {
    let text: String
    let palette: Palette

    init(_ text: String, palette: Palette) {
        self.text = text
        self.palette = palette
    }

    var body: some View {
        Text(text)
            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(palette.tertiary)
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
    @Binding var variant: GrammarVariant
    @Binding var appearance: PrototypeAppearance
    @Binding var contrast: ContrastPreview
    @Binding var cues: CuePreview
    @Binding var motion: MotionPreview

    var body: some View {
        HStack(spacing: 9) {
            Button { cycle(-1) } label: {
                Image(systemName: "chevron.left")
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command])
            .help("Previous calibration (Command–Left Arrow)")

            Text("\(variant.key) — \(variant.title)")
                .font(.system(size: 11.5, weight: .semibold))
                .frame(minWidth: 126)

            Button { cycle(1) } label: {
                Image(systemName: "chevron.right")
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command])
            .help("Next calibration (Command–Right Arrow)")

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

            Picker("Cues", selection: $cues) {
                ForEach(CuePreview.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 112)

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
        let variants = GrammarVariant.allCases
        guard let index = variants.firstIndex(of: variant) else { return }
        variant = variants[(index + offset + variants.count) % variants.count]
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
