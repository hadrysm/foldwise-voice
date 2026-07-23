// THROWAWAY PROTOTYPE — visual decision aid for Wayfinder ticket
// "Prototype the redesigned main-window shell".
//
// Three shell compositions, switchable from the bottom review bar, preserve
// the existing navigation, sidebar/rail, resize, recovery, and status
// contracts while applying the approved Ember Edge visual grammar.

import AppKit
import SwiftUI

private enum ShellVariant: String, CaseIterable, Identifiable {
    case continuous
    case mast
    case workbench

    var id: String {
        rawValue
    }

    var key: String {
        switch self {
        case .continuous: "A"
        case .mast: "B"
        case .workbench: "C"
        }
    }

    var title: String {
        switch self {
        case .continuous: "Continuous Frame"
        case .mast: "Sidebar Mast"
        case .workbench: "Inset Workbench"
        }
    }

    var thesis: String {
        switch self {
        case .continuous:
            "A single native frame; feedback attaches to the content edge."
        case .mast:
            "Navigation reads as the app’s persistent instrument panel."
        case .workbench:
            "Navigation and destination become distinct tools inside one frame."
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

private enum SidebarPreview: String, CaseIterable, Identifiable {
    case expanded = "Expanded"
    case rail = "Rail"

    var id: String {
        rawValue
    }

    var width: CGFloat {
        self == .expanded ? 190 : 52
    }
}

private enum FeedbackPreview: String, CaseIterable, Identifiable {
    case normal = "Normal"
    case recovery = "Recovery"
    case success = "Success"
    case error = "Error"

    var id: String {
        rawValue
    }
}

private enum ContrastPreview: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case increased = "Contrast+"

    var id: String {
        rawValue
    }
}

private struct Palette {
    let canvas: Color
    let sidebar: Color
    let surface: Color
    let raised: Color
    let hover: Color
    let border: Color
    let borderStrong: Color
    let text: Color
    let secondary: Color
    let tertiary: Color
    let accent: Color
    let accentText: Color
    let success: Color
    let warning: Color
    let error: Color

    static func ember(_ appearance: PrototypeAppearance) -> Palette {
        switch appearance {
        case .dark:
            Palette(
                canvas: Color(hex: 0x07090B),
                sidebar: Color(hex: 0x090B0E),
                surface: Color(hex: 0x0D1013),
                raised: Color(hex: 0x13171B),
                hover: Color(hex: 0x1A2026),
                border: Color(hex: 0x262C32),
                borderStrong: Color(hex: 0x5B6570),
                text: Color(hex: 0xF4F5F6),
                secondary: Color(hex: 0xA4AAB0),
                tertiary: Color(hex: 0x747C85),
                accent: Color(hex: 0xFF6A1A),
                accentText: Color(hex: 0x160900),
                success: Color(hex: 0x43D17A),
                warning: Color(hex: 0xF0B44B),
                error: Color(hex: 0xFF6464)
            )
        case .light:
            Palette(
                canvas: Color(hex: 0xF7F3EC),
                sidebar: Color(hex: 0xEEE8DE),
                surface: Color(hex: 0xFFFCF7),
                raised: Color(hex: 0xF4EFE7),
                hover: Color(hex: 0xEAE2D7),
                border: Color(hex: 0xD8CFC1),
                borderStrong: Color(hex: 0x978B7C),
                text: Color(hex: 0x1A1714),
                secondary: Color(hex: 0x625C55),
                tertiary: Color(hex: 0x766E65),
                accent: Color(hex: 0xBF4008),
                accentText: .white,
                success: Color(hex: 0x147A42),
                warning: Color(hex: 0x865B00),
                error: Color(hex: 0xB4232C)
            )
        }
    }
}

private struct SnapshotCase {
    let variant: ShellVariant
    let appearance: PrototypeAppearance
    let sidebar: SidebarPreview
    let feedback: FeedbackPreview
    let contrast: ContrastPreview

    var filename: String {
        [
            variant.key.lowercased(),
            variant.rawValue,
            appearance.rawValue.lowercased(),
            sidebar.rawValue.lowercased(),
            feedback.rawValue.lowercased(),
        ].joined(separator: "-") + ".png"
    }
}

@main
private enum MainWindowShellPrototypeApp {
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
            .appendingPathComponent(".context/main-window-shell-shots", isDirectory: true)
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

        var cases: [SnapshotCase] = []
        for variant in ShellVariant.allCases {
            for appearance in PrototypeAppearance.allCases {
                cases.append(SnapshotCase(
                    variant: variant,
                    appearance: appearance,
                    sidebar: .expanded,
                    feedback: .normal,
                    contrast: .standard
                ))
                cases.append(SnapshotCase(
                    variant: variant,
                    appearance: appearance,
                    sidebar: .rail,
                    feedback: .normal,
                    contrast: .standard
                ))
            }
            cases.append(SnapshotCase(
                variant: variant,
                appearance: .dark,
                sidebar: .expanded,
                feedback: .recovery,
                contrast: .standard
            ))
            cases.append(SnapshotCase(
                variant: variant,
                appearance: .dark,
                sidebar: .rail,
                feedback: .error,
                contrast: .increased
            ))
        }

        let size = CGSize(width: 1180, height: 780)
        for item in cases {
            let root = PrototypeRoot(
                initialVariant: item.variant,
                initialAppearance: item.appearance,
                initialSidebar: item.sidebar,
                initialFeedback: item.feedback,
                initialContrast: item.contrast
            )
            .frame(width: size.width, height: size.height)
            let hosting = NSHostingView(rootView: root)
            hosting.frame = NSRect(origin: .zero, size: size)
            hosting.appearance = NSAppearance(
                named: item.appearance == .light ? .aqua : .darkAqua
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
            try? png.write(to: output.appendingPathComponent(item.filename))
            window.orderOut(nil)
        }
    }
}

@MainActor
private final class PrototypeAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hosting = NSHostingController(rootView: PrototypeRoot())
        let window = NSWindow(contentViewController: hosting)
        window.title = "FoldWise main-window shell prototype"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.setContentSize(CGSize(width: 1180, height: 780))
        window.contentMinSize = CGSize(width: 1000, height: 700)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        true
    }
}

private struct PrototypeRoot: View {
    @State private var variant: ShellVariant
    @State private var appearance: PrototypeAppearance
    @State private var sidebar: SidebarPreview
    @State private var feedback: FeedbackPreview
    @State private var contrast: ContrastPreview

    init(
        initialVariant: ShellVariant = .continuous,
        initialAppearance: PrototypeAppearance = .dark,
        initialSidebar: SidebarPreview = .expanded,
        initialFeedback: FeedbackPreview = .normal,
        initialContrast: ContrastPreview = .standard
    ) {
        _variant = State(initialValue: initialVariant)
        _appearance = State(initialValue: initialAppearance)
        _sidebar = State(initialValue: initialSidebar)
        _feedback = State(initialValue: initialFeedback)
        _contrast = State(initialValue: initialContrast)
    }

    var body: some View {
        let palette = Palette.ember(appearance)
        ZStack(alignment: .bottom) {
            palette.canvas.ignoresSafeArea()
            ShellPreview(
                variant: variant,
                sidebar: sidebar,
                feedback: feedback,
                contrast: contrast,
                palette: palette
            )
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 84)

            ReviewBar(
                variant: $variant,
                appearance: $appearance,
                sidebar: $sidebar,
                feedback: $feedback,
                contrast: $contrast
            )
            .padding(.bottom, 16)
        }
        .environment(\.colorScheme, appearance.scheme)
    }
}

private struct ShellPreview: View {
    let variant: ShellVariant
    let sidebar: SidebarPreview
    let feedback: FeedbackPreview
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            switch variant {
            case .continuous:
                ContinuousFrame(
                    sidebar: sidebar,
                    feedback: feedback,
                    contrast: contrast,
                    palette: palette
                )
            case .mast:
                SidebarMast(
                    sidebar: sidebar,
                    feedback: feedback,
                    contrast: contrast,
                    palette: palette
                )
            case .workbench:
                InsetWorkbench(
                    sidebar: sidebar,
                    feedback: feedback,
                    contrast: contrast,
                    palette: palette
                )
            }
        }
        .background(palette.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        }
        .shadow(color: .black.opacity(0.32), radius: 24, y: 12)
    }

    private var borderColor: Color {
        contrast == .increased ? palette.borderStrong : palette.border
    }

    private var borderWidth: CGFloat {
        contrast == .increased ? 2 : 1
    }
}

private struct ContinuousFrame: View {
    let sidebar: SidebarPreview
    let feedback: FeedbackPreview
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            GlobalTitlebar(
                placement: .continuous,
                sidebar: sidebar,
                palette: palette
            )
            Hairline(color: borderColor)
            HStack(spacing: 0) {
                SidebarPanel(
                    mode: sidebar,
                    feedback: feedback,
                    placement: .continuous,
                    contrast: contrast,
                    palette: palette
                )
                Hairline(color: borderColor, vertical: true)
                DestinationCanvas(
                    feedback: feedback,
                    placement: .continuous,
                    contrast: contrast,
                    palette: palette
                )
            }
        }
    }

    private var borderColor: Color {
        contrast == .increased ? palette.borderStrong : palette.border
    }
}

private struct SidebarMast: View {
    let sidebar: SidebarPreview
    let feedback: FeedbackPreview
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            TrafficStrip(
                sidebar: sidebar,
                contrast: contrast,
                palette: palette
            )
            Hairline(color: borderColor)
            HStack(spacing: 0) {
                SidebarPanel(
                    mode: sidebar,
                    feedback: feedback,
                    placement: .mast,
                    contrast: contrast,
                    palette: palette
                )
                Hairline(color: borderColor, vertical: true)
                VStack(spacing: 0) {
                    ContentToolbar(
                        sidebar: sidebar,
                        feedback: feedback,
                        palette: palette
                    )
                    Hairline(color: borderColor)
                    DestinationCanvas(
                        feedback: feedback,
                        placement: .mast,
                        contrast: contrast,
                        palette: palette
                    )
                }
            }
        }
    }

    private var borderColor: Color {
        contrast == .increased ? palette.borderStrong : palette.border
    }
}

private struct InsetWorkbench: View {
    let sidebar: SidebarPreview
    let feedback: FeedbackPreview
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            GlobalTitlebar(
                placement: .workbench,
                sidebar: sidebar,
                palette: palette
            )
            Hairline(color: borderColor)
            HStack(spacing: 12) {
                SidebarPanel(
                    mode: sidebar,
                    feedback: feedback,
                    placement: .workbench,
                    contrast: contrast,
                    palette: palette
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(borderColor, lineWidth: borderWidth)
                }
                DestinationCanvas(
                    feedback: feedback,
                    placement: .workbench,
                    contrast: contrast,
                    palette: palette
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(borderColor, lineWidth: borderWidth)
                }
            }
            .padding(12)
            .background(palette.canvas)
        }
    }

    private var borderColor: Color {
        contrast == .increased ? palette.borderStrong : palette.border
    }

    private var borderWidth: CGFloat {
        contrast == .increased ? 2 : 1
    }
}

private enum ShellPlacement {
    case continuous
    case mast
    case workbench
}

private struct GlobalTitlebar: View {
    let placement: ShellPlacement
    let sidebar: SidebarPreview
    let palette: Palette

    var body: some View {
        HStack(spacing: 12) {
            TrafficLights()
            SidebarToggleGlyph(palette: palette)
            if placement == .continuous {
                BrandLockup(compact: false, palette: palette)
            } else {
                Text("FoldWise Voice")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.tertiary)
            }
            Spacer()
            if placement == .workbench {
                HStack(spacing: 7) {
                    Image(systemName: "waveform")
                        .foregroundStyle(palette.accent)
                    Text("Voice to Text")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(palette.secondary)
                }
            }
            Text(sidebar == .expanded ? "190 PT SIDEBAR" : "52 PT RAIL")
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(palette.tertiary)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(palette.sidebar)
    }
}

private struct TrafficStrip: View {
    let sidebar: SidebarPreview
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        HStack(spacing: 12) {
            TrafficLights()
            Spacer()
            Text("FOLDWISE / MAIN WINDOW")
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(palette.tertiary)
            SidebarToggleGlyph(palette: palette)
        }
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(palette.sidebar)
        .overlay(alignment: .bottomLeading) {
            Rectangle()
                .fill(palette.accent)
                .frame(width: sidebar.width, height: contrast == .increased ? 2 : 1)
        }
    }
}

private struct ContentToolbar: View {
    let sidebar: SidebarPreview
    let feedback: FeedbackPreview
    let palette: Palette

    var body: some View {
        HStack(spacing: 10) {
            Text("Home")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.text)
            Text("Destination canvas")
                .font(.system(size: 10))
                .foregroundStyle(palette.tertiary)
            Spacer()
            if feedback == .recovery {
                Label("Read-only", systemImage: "lock.fill")
                    .foregroundStyle(palette.warning)
            } else {
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(palette.success)
            }
        }
        .font(.system(size: 10.5, weight: .medium))
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(palette.surface)
    }
}

private struct SidebarPanel: View {
    let mode: SidebarPreview
    let feedback: FeedbackPreview
    let placement: ShellPlacement
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if placement == .mast {
                BrandLockup(compact: mode == .rail, palette: palette)
                    .frame(height: 54)
                    .padding(.horizontal, mode == .expanded ? 13 : 0)
                    .frame(maxWidth: .infinity)
                Hairline(color: borderColor)
            }
            NavigationList(
                mode: mode,
                recovery: feedback == .recovery,
                palette: palette
            )
            .padding(.horizontal, 8)
            .padding(.top, 10)
            Spacer()
            SidebarFooter(mode: mode, palette: palette)
                .padding(.horizontal, mode == .expanded ? 11 : 7)
                .padding(.bottom, 12)
        }
        .frame(width: mode.width)
        .background(palette.sidebar)
    }

    private var borderColor: Color {
        contrast == .increased ? palette.borderStrong : palette.border
    }
}

private struct NavigationList: View {
    let mode: SidebarPreview
    let recovery: Bool
    let palette: Palette
    @State private var hoveredPane: Pane?

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 4) {
                ForEach(Pane.allCases) { pane in
                    NavigationRow(
                        pane: pane,
                        mode: mode,
                        recovery: recovery,
                        palette: palette
                    )
                    .onHover { hovering in
                        if mode == .rail {
                            hoveredPane = hovering ? pane : nil
                        }
                    }
                }
            }
            if mode == .rail, let hoveredPane,
               let index = Pane.allCases.firstIndex(of: hoveredPane) {
                Text(hoveredPane.rawValue)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(palette.canvas)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(palette.text, in: RoundedRectangle(cornerRadius: 6))
                    .offset(x: 48, y: CGFloat(index) * 40 + 5)
                    .fixedSize()
                    .zIndex(10)
                    .allowsHitTesting(false)
            }
        }
    }
}

private enum Pane: String, CaseIterable, Identifiable {
    case home = "Home"
    case modes = "Modes"
    case models = "Models"
    case history = "History"
    case stats = "Stats"
    case settings = "Settings"

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .modes: "sparkles"
        case .models: "shippingbox"
        case .history: "clock"
        case .stats: "chart.bar"
        case .settings: "slider.horizontal.3"
        }
    }

    var disabledInRecovery: Bool {
        [.modes, .models, .history, .settings].contains(self)
    }
}

private struct NavigationRow: View {
    let pane: Pane
    let mode: SidebarPreview
    let recovery: Bool
    let palette: Palette

    private var active: Bool {
        pane == .home
    }

    private var disabled: Bool {
        recovery && pane.disabledInRecovery
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: pane.icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 18)
                .foregroundStyle(active ? palette.accent : palette.tertiary)
            if mode == .expanded {
                Text(pane.rawValue)
                    .font(.system(size: 12, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? palette.text : palette.secondary)
                Spacer()
                if disabled {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(palette.tertiary)
                } else if active {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.accent)
                }
            }
        }
        .padding(.horizontal, mode == .expanded ? 9 : 5)
        .frame(width: mode == .expanded ? 174 : 36, height: 36)
        .background(active ? palette.raised : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) {
            if active {
                Rectangle()
                    .fill(palette.accent)
                    .frame(width: 2, height: 22)
            }
        }
        .opacity(disabled ? 0.46 : 1)
        .help(mode == .rail ? pane.rawValue : "")
    }
}

private struct SidebarFooter: View {
    let mode: SidebarPreview
    let palette: Palette

    var body: some View {
        if mode == .expanded {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(palette.success)
                    Text("Up to date")
                        .foregroundStyle(palette.secondary)
                }
                Text("v0.15.0")
                    .foregroundStyle(palette.tertiary)
            }
            .font(.system(size: 10.5))
        } else {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(palette.success)
                .frame(width: 36, height: 30)
                .background(palette.raised, in: RoundedRectangle(cornerRadius: 6))
                .help("v0.15.0 · up to date")
        }
    }
}

private struct DestinationCanvas: View {
    let feedback: FeedbackPreview
    let placement: ShellPlacement
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            if feedback == .recovery {
                RecoveryBanner(contrast: contrast, palette: palette)
                Hairline(color: borderColor)
            }
            DestinationScaffold(
                recovery: feedback == .recovery,
                placement: placement,
                contrast: contrast,
                palette: palette
            )
            if feedback == .success || feedback == .error {
                Hairline(color: borderColor)
                GlobalStatusArea(feedback: feedback, palette: palette)
            }
        }
        .background(palette.canvas)
    }

    private var borderColor: Color {
        contrast == .increased ? palette.borderStrong : palette.border
    }
}

private struct RecoveryBanner: View {
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(palette.warning)
            VStack(alignment: .leading, spacing: 3) {
                Text("Configuration recovery")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text("Voice to Text remains available. Configuration changes are disabled.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.secondary)
            }
            Spacer()
            Button("Quit") {}
                .buttonStyle(.plain)
                .foregroundStyle(palette.secondary)
            Button("Reset Configuration") {}
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(palette.accentText)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(palette.accent, in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(palette.raised)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(palette.warning)
                .frame(width: contrast == .increased ? 3 : 2)
        }
    }
}

private struct DestinationScaffold: View {
    let recovery: Bool
    let placement: ShellPlacement
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Ready when you are.")
                    .font(.system(size: 27, weight: .semibold))
                    .tracking(-0.45)
                    .foregroundStyle(palette.text)
                Text("Destination content context — intentionally not a Home redesign")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(palette.tertiary)
            }
            HStack(spacing: 10) {
                MetricScaffold(value: "5,809", label: "Total words", palette: palette)
                MetricScaffold(value: "125", label: "Words / min", palette: palette)
                MetricScaffold(value: "6", label: "Day streak", palette: palette)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label(
                        recovery ? "Voice to Text available" : "All systems go",
                        systemImage: recovery
                            ? "waveform.circle.fill"
                            : "checkmark.seal.fill"
                    )
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.text)
                    Spacer()
                    Text("SYSTEM STATUS")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(palette.tertiary)
                }
                .padding(12)
                Hairline(color: borderColor)
                ForEach(0 ..< 4, id: \.self) { index in
                    HStack(spacing: 10) {
                        Text(["18:51", "12:54", "12:44", "12:39"][index])
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(palette.tertiary)
                        Rectangle()
                            .fill(palette.accent)
                            .frame(width: 2, height: 15)
                        Text([
                            "A recent Dictation row establishes the content edge.",
                            "Dense surfaces remain legible without elevated cards.",
                            "The shell owns global feedback, not the destination.",
                            "Interior composition continues in later prototypes.",
                        ][index])
                            .font(.system(size: 10.5))
                            .foregroundStyle(palette.secondary)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "ellipsis")
                            .foregroundStyle(palette.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    if index < 3 {
                        Hairline(color: borderColor)
                    }
                }
            }
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            }
            Spacer(minLength: 0)
            HStack {
                Text("880 × 640 MIN")
                Text("•")
                Text("AUTO RAIL BELOW 940")
                Text("•")
                Text("⌘\\ TOGGLE")
            }
            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
            .foregroundStyle(palette.tertiary)
        }
        .padding(placement == .workbench ? 24 : 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.canvas)
    }

    private var borderColor: Color {
        contrast == .increased ? palette.borderStrong : palette.border
    }

    private var borderWidth: CGFloat {
        contrast == .increased ? 2 : 1
    }
}

private struct MetricScaffold: View {
    let value: String
    let label: String
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.text)
            Text(label.uppercased())
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(palette.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct GlobalStatusArea: View {
    let feedback: FeedbackPreview
    let palette: Palette

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: feedback == .error
                ? "exclamationmark.octagon.fill"
                : "checkmark.seal.fill")
                .foregroundStyle(feedback == .error ? palette.error : palette.success)
            Text(feedback == .error
                ? "Couldn’t save changes. Review the highlighted setting and retry."
                : "Changes saved")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(palette.text)
                .underline(feedback == .error)
            Spacer()
            Text(feedback == .error ? "PERSISTS UNTIL SUPERSEDED" : "CLEARS AFTER 2 SEC")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(palette.tertiary)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(palette.raised)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(feedback == .error ? palette.error : palette.success)
                .frame(width: 2)
        }
    }
}

private struct BrandLockup: View {
    let compact: Bool
    let palette: Palette

    var body: some View {
        HStack(spacing: 8) {
            WaveMark(color: palette.accent)
                .frame(width: compact ? 27 : 31, height: 18)
            if !compact {
                HStack(spacing: 3) {
                    Text("FoldWise")
                        .foregroundStyle(palette.accent)
                    Text("Voice")
                        .foregroundStyle(palette.text)
                }
            }
        }
        .font(.system(size: 12, weight: .semibold))
    }
}

private struct WaveMark: View {
    let color: Color
    private let heights: [CGFloat] = [5, 11, 17, 9, 15, 7, 12]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(heights.enumerated()), id: \.offset) { item in
                Capsule()
                    .fill(color)
                    .frame(width: 2, height: item.element)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct TrafficLights: View {
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(Color(hex: 0xFF5F57))
            Circle().fill(Color(hex: 0xFEBC2E))
            Circle().fill(Color(hex: 0x28C840))
        }
        .frame(width: 42, height: 11)
    }
}

private struct SidebarToggleGlyph: View {
    let palette: Palette

    var body: some View {
        RoundedRectangle(cornerRadius: 3.5)
            .strokeBorder(palette.tertiary, lineWidth: 1.2)
            .frame(width: 18, height: 14)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(palette.tertiary)
                    .frame(width: 1)
                    .padding(.vertical, 1.5)
                    .offset(x: 5)
            }
    }
}

private struct Hairline: View {
    let color: Color
    var vertical = false

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

private struct ReviewBar: View {
    @Binding var variant: ShellVariant
    @Binding var appearance: PrototypeAppearance
    @Binding var sidebar: SidebarPreview
    @Binding var feedback: FeedbackPreview
    @Binding var contrast: ContrastPreview

    var body: some View {
        HStack(spacing: 9) {
            Button { cycle(-1) } label: {
                Image(systemName: "chevron.left")
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command])
            .help("Previous shell (Command–Left Arrow)")

            Text("\(variant.key) — \(variant.title)")
                .font(.system(size: 11, weight: .semibold))
                .frame(minWidth: 142)

            Button { cycle(1) } label: {
                Image(systemName: "chevron.right")
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command])
            .help("Next shell (Command–Right Arrow)")

            Divider().frame(height: 18)
            reviewPicker("Sidebar", selection: $sidebar, width: 138)
            reviewPicker("Appearance", selection: $appearance, width: 108)
            reviewPicker("Feedback", selection: $feedback, width: 234)
            reviewPicker("Contrast", selection: $contrast, width: 146)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.white)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.94), in: RoundedRectangle(cornerRadius: 11))
        .shadow(color: .black.opacity(0.28), radius: 16, y: 6)
        .environment(\.colorScheme, .dark)
    }

    private func reviewPicker<T: Hashable & Identifiable & CaseIterable & RawRepresentable>(
        _ label: String,
        selection: Binding<T>,
        width: CGFloat
    ) -> some View where T.AllCases: RandomAccessCollection, T.RawValue == String {
        Picker(label, selection: selection) {
            ForEach(Array(T.allCases)) { item in
                Text(item.rawValue).tag(item)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: width)
    }

    private func cycle(_ offset: Int) {
        let variants = ShellVariant.allCases
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
