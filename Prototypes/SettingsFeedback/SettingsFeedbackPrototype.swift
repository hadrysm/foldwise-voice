// THROWAWAY PROTOTYPE — visual decision aid for Wayfinder ticket
// "Prototype Settings and global feedback states".
//
// Three Settings compositions, switchable from the bottom review bar, preserve
// the existing controls and lifecycle states while applying the approved Ember
// Edge grammar inside the approved Continuous Frame shell.

import AppKit
import SwiftUI

private enum SettingsVariant: String, CaseIterable, Identifiable {
    case ledger
    case matrix
    case openForm

    var id: String {
        rawValue
    }

    var key: String {
        switch self {
        case .ledger: "A"
        case .matrix: "B"
        case .openForm: "C"
        }
    }

    var title: String {
        switch self {
        case .ledger: "Signal Ledger"
        case .matrix: "Control Matrix"
        case .openForm: "Open Form"
        }
    }

    var thesis: String {
        switch self {
        case .ledger:
            "One dense scan path; every state reads where its control lives."
        case .matrix:
            "Operational controls lead; personal and maintenance controls stay adjacent."
        case .openForm:
            "Typography and rules carry hierarchy with almost no card chrome."
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

private enum WidthPreview: String, CaseIterable, Identifiable {
    case wide = "Wide"
    case narrow = "Narrow"

    var id: String {
        rawValue
    }

    var width: CGFloat {
        self == .wide ? 1160 : 880
    }

    var sidebarWidth: CGFloat {
        190
    }

    var appearanceIsHorizontal: Bool {
        self == .wide
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

private enum SettingsScenario: String, CaseIterable, Identifiable {
    case baseline = "Baseline"
    case capture = "Capture error"
    case permission = "Permission"
    case fallback = "Input fallback"
    case restored = "Input restored"
    case deferred = "Input deferred"
    case unavailable = "Input unavailable"
    case checking = "Update checking"
    case available = "Update available"
    case failed = "Update failed"
    case development = "Dev build"
    case recovery = "Recovery"

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

private enum InputState {
    case healthy
    case fallback
    case restored
    case deferred
    case unavailable
}

private enum UpdateState {
    case current
    case checking
    case available
    case failed
    case development
}

private struct PreviewState {
    let capturingShortcut: Bool
    let focusedAppOnly: Bool
    let input: InputState
    let update: UpdateState
    let recovery: Bool
    let status: StatusMessage?

    static func make(_ scenario: SettingsScenario) -> PreviewState {
        switch scenario {
        case .baseline:
            PreviewState(
                capturingShortcut: false,
                focusedAppOnly: false,
                input: .healthy,
                update: .current,
                recovery: false,
                status: nil
            )
        case .capture:
            PreviewState(
                capturingShortcut: true,
                focusedAppOnly: false,
                input: .healthy,
                update: .current,
                recovery: false,
                status: StatusMessage(
                    kind: .error,
                    title: "Shortcut not saved",
                    detail: "Toggle Recording already uses ⌃ Space. Choose another key."
                )
            )
        case .permission:
            PreviewState(
                capturingShortcut: false,
                focusedAppOnly: true,
                input: .healthy,
                update: .current,
                recovery: false,
                status: nil
            )
        case .fallback:
            PreviewState(
                capturingShortcut: false,
                focusedAppOnly: false,
                input: .fallback,
                update: .current,
                recovery: false,
                status: nil
            )
        case .restored:
            PreviewState(
                capturingShortcut: false,
                focusedAppOnly: false,
                input: .restored,
                update: .current,
                recovery: false,
                status: StatusMessage(
                    kind: .success,
                    title: "Input restored",
                    detail: "Studio Display Microphone is in use again."
                )
            )
        case .deferred:
            PreviewState(
                capturingShortcut: false,
                focusedAppOnly: false,
                input: .deferred,
                update: .current,
                recovery: false,
                status: nil
            )
        case .unavailable:
            PreviewState(
                capturingShortcut: false,
                focusedAppOnly: false,
                input: .unavailable,
                update: .current,
                recovery: false,
                status: StatusMessage(
                    kind: .error,
                    title: "No input device",
                    detail: "Connect a microphone before starting a Dictation session."
                )
            )
        case .checking:
            PreviewState(
                capturingShortcut: false,
                focusedAppOnly: false,
                input: .healthy,
                update: .checking,
                recovery: false,
                status: nil
            )
        case .available:
            PreviewState(
                capturingShortcut: false,
                focusedAppOnly: false,
                input: .healthy,
                update: .available,
                recovery: false,
                status: nil
            )
        case .failed:
            PreviewState(
                capturingShortcut: false,
                focusedAppOnly: false,
                input: .healthy,
                update: .failed,
                recovery: false,
                status: StatusMessage(
                    kind: .error,
                    title: "Update check failed",
                    detail: "FoldWise couldn’t reach GitHub. Try again later."
                )
            )
        case .development:
            PreviewState(
                capturingShortcut: false,
                focusedAppOnly: false,
                input: .healthy,
                update: .development,
                recovery: false,
                status: nil
            )
        case .recovery:
            PreviewState(
                capturingShortcut: false,
                focusedAppOnly: false,
                input: .healthy,
                update: .current,
                recovery: true,
                status: nil
            )
        }
    }
}

private enum StatusKind {
    case success
    case error
}

private struct StatusMessage {
    let kind: StatusKind
    let title: String
    let detail: String
}

private struct SnapshotCase {
    let variant: SettingsVariant
    let appearance: PrototypeAppearance
    let width: WidthPreview
    let scenario: SettingsScenario
    let contrast: ContrastPreview

    var filename: String {
        [
            variant.key.lowercased(),
            variant.rawValue,
            appearance.rawValue.lowercased(),
            width.rawValue.lowercased(),
            scenario.id.lowercased().replacingOccurrences(of: " ", with: "-"),
        ].joined(separator: "-") + ".png"
    }
}

@main
private enum SettingsFeedbackPrototypeApp {
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
            .appendingPathComponent(".context/settings-feedback-shots", isDirectory: true)
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
        for variant in SettingsVariant.allCases {
            for appearance in PrototypeAppearance.allCases {
                cases.append(SnapshotCase(
                    variant: variant,
                    appearance: appearance,
                    width: .wide,
                    scenario: .baseline,
                    contrast: .standard
                ))
            }
            cases.append(SnapshotCase(
                variant: variant,
                appearance: .dark,
                width: .narrow,
                scenario: .capture,
                contrast: .standard
            ))
            cases.append(SnapshotCase(
                variant: variant,
                appearance: .dark,
                width: .wide,
                scenario: .fallback,
                contrast: .increased
            ))
            cases.append(SnapshotCase(
                variant: variant,
                appearance: .dark,
                width: .wide,
                scenario: .available,
                contrast: .standard
            ))
            cases.append(SnapshotCase(
                variant: variant,
                appearance: .light,
                width: .narrow,
                scenario: .recovery,
                contrast: .increased
            ))
        }

        for item in cases {
            let root = PrototypeRoot(
                initialVariant: item.variant,
                initialAppearance: item.appearance,
                initialWidth: item.width,
                initialScenario: item.scenario,
                initialContrast: item.contrast,
                showsReviewBar: false
            )
            .frame(width: item.width.width, height: 820)
            let hosting = NSHostingView(rootView: root)
            hosting.frame = NSRect(x: 0, y: 0, width: item.width.width, height: 820)
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
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
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
        window.title = "FoldWise Settings and feedback prototype"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.setContentSize(CGSize(width: 1220, height: 900))
        window.contentMinSize = CGSize(width: 960, height: 760)
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
    @State private var variant: SettingsVariant
    @State private var appearance: PrototypeAppearance
    @State private var width: WidthPreview
    @State private var scenario: SettingsScenario
    @State private var contrast: ContrastPreview
    @State private var motion: MotionPreview
    let showsReviewBar: Bool

    init(
        initialVariant: SettingsVariant = .ledger,
        initialAppearance: PrototypeAppearance = .dark,
        initialWidth: WidthPreview = .wide,
        initialScenario: SettingsScenario = .baseline,
        initialContrast: ContrastPreview = .standard,
        initialMotion: MotionPreview = .standard,
        showsReviewBar: Bool = true
    ) {
        _variant = State(initialValue: initialVariant)
        _appearance = State(initialValue: initialAppearance)
        _width = State(initialValue: initialWidth)
        _scenario = State(initialValue: initialScenario)
        _contrast = State(initialValue: initialContrast)
        _motion = State(initialValue: initialMotion)
        self.showsReviewBar = showsReviewBar
    }

    var body: some View {
        let palette = Palette.ember(appearance)
        ZStack(alignment: .bottom) {
            palette.canvas.ignoresSafeArea()
            ContinuousFrame(
                variant: variant,
                width: width,
                state: PreviewState.make(scenario),
                contrast: contrast,
                palette: palette
            )
            .frame(width: width.width)
            .padding(.horizontal, showsReviewBar ? 24 : 0)
            .padding(.top, showsReviewBar ? 22 : 0)
            .padding(.bottom, showsReviewBar ? 88 : 0)

            if showsReviewBar {
                ReviewBar(
                    variant: $variant,
                    appearance: $appearance,
                    width: $width,
                    scenario: $scenario,
                    contrast: $contrast,
                    motion: $motion
                )
                .padding(.bottom, 16)
            }
        }
        .environment(\.colorScheme, appearance.scheme)
        .animation(
            motion == .reduced ? nil : .easeOut(duration: 0.16),
            value: scenario
        )
    }
}

private struct ContinuousFrame: View {
    let variant: SettingsVariant
    let width: WidthPreview
    let state: PreviewState
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            titlebar
            Hairline(color: borderColor)
            HStack(spacing: 0) {
                Sidebar(width: width, recovery: state.recovery, palette: palette)
                Hairline(color: borderColor, vertical: true)
                VStack(spacing: 0) {
                    if state.recovery {
                        RecoveryBanner(palette: palette)
                        Hairline(color: borderColor)
                    }
                    SettingsCanvas(
                        variant: variant,
                        width: width,
                        state: state,
                        contrast: contrast,
                        palette: palette
                    )
                    .opacity(state.recovery ? 0.54 : 1)
                    .allowsHitTesting(!state.recovery)
                    if let status = state.status {
                        Hairline(color: borderColor)
                        GlobalStatus(message: status, palette: palette)
                    }
                }
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

    private var titlebar: some View {
        HStack(spacing: 12) {
            TrafficLights()
            SidebarToggleGlyph(palette: palette)
            HStack(spacing: 7) {
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.accent)
                Text("FoldWise Voice")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.text)
            }
            Spacer()
            Text("\(variant.key) — \(variant.title)")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(palette.tertiary)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(palette.sidebar)
    }

    private var borderColor: Color {
        contrast == .increased ? palette.borderStrong : palette.border
    }

    private var borderWidth: CGFloat {
        contrast == .increased ? 2 : 1
    }
}

private struct Sidebar: View {
    let width: WidthPreview
    let recovery: Bool
    let palette: Palette

    private let destinations: [(String, String)] = [
        ("Home", "house"),
        ("Modes", "sparkles"),
        ("Models", "shippingbox"),
        ("History", "clock"),
        ("Stats", "chart.bar"),
        ("Settings", "slider.horizontal.3"),
    ]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(destinations, id: \.0) { item in
                let active = item.0 == "Settings"
                let disabled = recovery && ["Modes", "Models", "History", "Settings"]
                    .contains(item.0)
                HStack(spacing: 9) {
                    Image(systemName: item.1)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 18)
                    if width.sidebarWidth > 100 {
                        Text(item.0)
                            .font(.system(size: 12.5, weight: active ? .semibold : .regular))
                        Spacer()
                    }
                }
                .foregroundStyle(active ? palette.accent : palette.secondary)
                .opacity(disabled ? 0.36 : 1)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .padding(.horizontal, 9)
                .background(
                    active ? palette.raised : .clear,
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .overlay(alignment: .leading) {
                    if active {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(palette.accent)
                            .frame(width: 2, height: 18)
                    }
                }
            }
            Spacer()
            if width.sidebarWidth > 100 {
                VStack(alignment: .leading, spacing: 4) {
                    Label("All systems go", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(palette.success)
                    Text("v0.15.0 · up to date")
                        .foregroundStyle(palette.tertiary)
                }
                .font(.system(size: 10.5, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(palette.border, lineWidth: 1)
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(palette.success)
                    .frame(width: 34, height: 34)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .frame(width: width.sidebarWidth)
        .background(palette.sidebar)
    }
}

private struct SettingsCanvas: View {
    let variant: SettingsVariant
    let width: WidthPreview
    let state: PreviewState
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Settings")
                            .font(.system(size: 30, weight: .semibold))
                            .tracking(-0.5)
                            .foregroundStyle(palette.text)
                        Text(variant.thesis)
                            .font(.system(size: 12.5))
                            .foregroundStyle(palette.secondary)
                    }
                    Spacer()
                    Text(width == .wide ? "FULL WIDTH" : "COMPACT WIDTH")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(palette.tertiary)
                }

                switch variant {
                case .ledger:
                    SignalLedger(
                        width: width,
                        state: state,
                        contrast: contrast,
                        palette: palette
                    )
                case .matrix:
                    ControlMatrix(
                        width: width,
                        state: state,
                        contrast: contrast,
                        palette: palette
                    )
                case .openForm:
                    OpenForm(
                        width: width,
                        state: state,
                        contrast: contrast,
                        palette: palette
                    )
                }
            }
            .padding(.horizontal, width == .wide ? 28 : 22)
            .padding(.top, 24)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(palette.canvas)
    }
}

private struct SignalLedger: View {
    let width: WidthPreview
    let state: PreviewState
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LedgerSection(
                title: "Keyboard shortcuts",
                symbol: "command",
                contrast: contrast,
                palette: palette
            ) {
                ShortcutRows(
                    capturing: state.capturingShortcut,
                    permissionWarning: state.focusedAppOnly,
                    style: .ledger,
                    palette: palette
                )
            }
            LedgerSection(
                title: "Input",
                symbol: "mic",
                contrast: contrast,
                palette: palette
            ) {
                InputRows(state: state.input, style: .ledger, palette: palette)
            }
            LedgerSection(
                title: "Sound",
                symbol: "speaker.wave.2",
                contrast: contrast,
                palette: palette
            ) {
                SoundRow(style: .ledger, palette: palette)
            }
            LedgerSection(
                title: "Appearance",
                symbol: "circle.lefthalf.filled",
                contrast: contrast,
                palette: palette
            ) {
                AppearanceChoices(
                    horizontal: width.appearanceIsHorizontal,
                    style: .cards,
                    palette: palette
                )
                .padding(12)
            }
            LedgerSection(
                title: "Updates",
                symbol: "arrow.triangle.2.circlepath",
                contrast: contrast,
                palette: palette
            ) {
                UpdateRow(state: state.update, style: .ledger, palette: palette)
            }
        }
    }
}

private struct ControlMatrix: View {
    let width: WidthPreview
    let state: PreviewState
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        if width == .wide {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 12) {
                    MatrixModule(
                        eyebrow: "CONTROL",
                        title: "Shortcuts",
                        symbol: "command",
                        contrast: contrast,
                        palette: palette
                    ) {
                        ShortcutRows(
                            capturing: state.capturingShortcut,
                            permissionWarning: state.focusedAppOnly,
                            style: .matrix,
                            palette: palette
                        )
                    }
                    MatrixModule(
                        eyebrow: "ROUTING",
                        title: "Input",
                        symbol: "mic",
                        contrast: contrast,
                        palette: palette
                    ) {
                        InputRows(state: state.input, style: .matrix, palette: palette)
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    MatrixModule(
                        eyebrow: "PERSONAL",
                        title: "Appearance",
                        symbol: "circle.lefthalf.filled",
                        contrast: contrast,
                        palette: palette
                    ) {
                        AppearanceChoices(
                            horizontal: false,
                            style: .compact,
                            palette: palette
                        )
                        .padding(12)
                    }
                    MatrixModule(
                        eyebrow: "AUDIO",
                        title: "Sound",
                        symbol: "speaker.wave.2",
                        contrast: contrast,
                        palette: palette
                    ) {
                        SoundRow(style: .matrix, palette: palette)
                    }
                    MatrixModule(
                        eyebrow: "MAINTENANCE",
                        title: "Updates",
                        symbol: "arrow.triangle.2.circlepath",
                        contrast: contrast,
                        palette: palette
                    ) {
                        UpdateRow(state: state.update, style: .matrix, palette: palette)
                    }
                }
                .frame(width: 340)
            }
        } else {
            VStack(spacing: 12) {
                MatrixModule(
                    eyebrow: "CONTROL",
                    title: "Shortcuts",
                    symbol: "command",
                    contrast: contrast,
                    palette: palette
                ) {
                    ShortcutRows(
                        capturing: state.capturingShortcut,
                        permissionWarning: state.focusedAppOnly,
                        style: .matrix,
                        palette: palette
                    )
                }
                MatrixModule(
                    eyebrow: "ROUTING",
                    title: "Input",
                    symbol: "mic",
                    contrast: contrast,
                    palette: palette
                ) {
                    InputRows(state: state.input, style: .matrix, palette: palette)
                }
                MatrixModule(
                    eyebrow: "AUDIO",
                    title: "Sound",
                    symbol: "speaker.wave.2",
                    contrast: contrast,
                    palette: palette
                ) {
                    SoundRow(style: .matrix, palette: palette)
                }
                MatrixModule(
                    eyebrow: "PERSONAL",
                    title: "Appearance",
                    symbol: "circle.lefthalf.filled",
                    contrast: contrast,
                    palette: palette
                ) {
                    AppearanceChoices(horizontal: false, style: .compact, palette: palette)
                        .padding(12)
                }
                MatrixModule(
                    eyebrow: "MAINTENANCE",
                    title: "Updates",
                    symbol: "arrow.triangle.2.circlepath",
                    contrast: contrast,
                    palette: palette
                ) {
                    UpdateRow(state: state.update, style: .matrix, palette: palette)
                }
            }
        }
    }
}

private struct OpenForm: View {
    let width: WidthPreview
    let state: PreviewState
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            OpenSection(
                title: "Keyboard shortcuts",
                detail: "Global commands",
                symbol: "command",
                border: borderColor,
                palette: palette
            ) {
                ShortcutRows(
                    capturing: state.capturingShortcut,
                    permissionWarning: state.focusedAppOnly,
                    style: .open,
                    palette: palette
                )
            }
            OpenSection(
                title: "Input",
                detail: "Record stage",
                symbol: "mic",
                border: borderColor,
                palette: palette
            ) {
                InputRows(state: state.input, style: .open, palette: palette)
            }
            OpenSection(
                title: "Sound",
                detail: "During dictation",
                symbol: "speaker.wave.2",
                border: borderColor,
                palette: palette
            ) {
                SoundRow(style: .open, palette: palette)
            }
            OpenSection(
                title: "Appearance",
                detail: "Main window and Badge",
                symbol: "circle.lefthalf.filled",
                border: borderColor,
                palette: palette
            ) {
                AppearanceChoices(
                    horizontal: width.appearanceIsHorizontal,
                    style: .lines,
                    palette: palette
                )
            }
            OpenSection(
                title: "Updates",
                detail: "FoldWise Voice",
                symbol: "arrow.triangle.2.circlepath",
                border: borderColor,
                palette: palette
            ) {
                UpdateRow(state: state.update, style: .open, palette: palette)
            }
        }
        .frame(maxWidth: 880)
    }

    private var borderColor: Color {
        contrast == .increased ? palette.borderStrong : palette.border
    }
}

private enum ModuleStyle {
    case ledger
    case matrix
    case open
}

private enum AppearanceStyle {
    case cards
    case compact
    case lines
}

private struct LedgerSection<Content: View>: View {
    let title: String
    let symbol: String
    let contrast: ContrastPreview
    let palette: Palette
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title.uppercased(), systemImage: symbol)
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(palette.tertiary)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                content
            }
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        contrast == .increased ? palette.borderStrong : palette.border,
                        lineWidth: contrast == .increased ? 2 : 1
                    )
            }
        }
    }
}

private struct MatrixModule<Content: View>: View {
    let eyebrow: String
    let title: String
    let symbol: String
    let contrast: ContrastPreview
    let palette: Palette
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .foregroundStyle(palette.accent)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(eyebrow)
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(palette.tertiary)
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.text)
                }
                Spacer()
            }
            .padding(12)
            Hairline(color: contrast == .increased ? palette.borderStrong : palette.border)
            content
        }
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 8))
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

private struct OpenSection<Content: View>: View {
    let title: String
    let detail: String
    let symbol: String
    let border: Color
    let palette: Palette
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Hairline(color: border)
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Image(systemName: symbol)
                            .foregroundStyle(palette.accent)
                            .frame(width: 18)
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.text)
                    }
                    Text(detail.uppercased())
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(palette.tertiary)
                        .padding(.leading, 25)
                }
                .frame(width: 170, alignment: .leading)
                content
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 14)
        }
    }
}

private struct ShortcutRows: View {
    let capturing: Bool
    let permissionWarning: Bool
    let style: ModuleStyle
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            PreferenceRow(
                title: "Push to Talk",
                subtitle: "Hold to record, release when done",
                style: style,
                palette: palette
            ) {
                HStack(spacing: 8) {
                    IconButton(symbol: "arrow.counterclockwise", palette: palette)
                    ShortcutChip(
                        label: capturing ? "Press a key…" : "right ⌥",
                        capturing: capturing,
                        palette: palette
                    )
                }
            }
            RowDivider(style: style, palette: palette)
            PreferenceRow(
                title: "Toggle Recording",
                subtitle: "Starts and stops Dictation sessions",
                style: style,
                palette: palette
            ) {
                HStack(spacing: 8) {
                    IconButton(symbol: "xmark", palette: palette)
                    ShortcutChip(label: "⌃ Space", capturing: false, palette: palette)
                }
            }
            RowDivider(style: style, palette: palette)
            PreferenceRow(
                title: "Cycle Modes",
                subtitle: "Selects the next Mode for the next Dictation session",
                style: style,
                palette: palette
            ) {
                ShortcutChip(label: "Click to set", capturing: false, empty: true, palette: palette)
            }
            Text("Click a shortcut, then press a modifier, function key, or single character.")
                .font(.system(size: 10.5))
                .foregroundStyle(palette.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, style == .open ? 0 : 12)
                .padding(.vertical, 9)
            if permissionWarning {
                InlineNotice(
                    kind: .warning,
                    title: "Global shortcuts need permission",
                    detail: "They currently work only while FoldWise is focused.",
                    action: "Open System Settings…",
                    palette: palette
                )
                .padding(style == .open ? .top : [.horizontal, .bottom], 10)
            }
        }
    }
}

private struct InputRows: View {
    let state: InputState
    let style: ModuleStyle
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            InputDeviceRow(
                title: "System Default",
                detail: "MacBook Pro Microphone",
                badge: state == .healthy ? "IN USE" : nil,
                selected: state == .healthy,
                disabled: false,
                style: style,
                palette: palette
            )
            RowDivider(style: style, palette: palette)
            InputDeviceRow(
                title: "Studio Display Microphone",
                detail: preferredDetail,
                badge: preferredBadge,
                selected: [.restored, .deferred].contains(state),
                disabled: state == .fallback,
                style: style,
                palette: palette
            )
            RowDivider(style: style, palette: palette)
            InputDeviceRow(
                title: "AirPods Pro",
                detail: "Connected",
                badge: nil,
                selected: false,
                disabled: false,
                style: style,
                palette: palette
            )
            if let notice {
                InlineNotice(
                    kind: notice.kind,
                    title: notice.title,
                    detail: notice.detail,
                    action: nil,
                    palette: palette
                )
                .padding(style == .open ? .top : [.horizontal, .bottom], 10)
            }
        }
    }

    private var preferredDetail: String {
        switch state {
        case .fallback: "Not connected · Preferred"
        case .deferred: "Preferred · Next Dictation session"
        case .healthy, .restored, .unavailable: "Connected · Preferred"
        }
    }

    private var preferredBadge: String? {
        switch state {
        case .restored: "IN USE"
        case .deferred: "NEXT"
        case .healthy, .fallback, .unavailable: nil
        }
    }

    private var notice: NoticeContent? {
        switch state {
        case .healthy:
            nil
        case .fallback:
            NoticeContent(
                kind: .warning,
                title: "Preferred input is disconnected",
                detail: "Studio Display Microphone is unavailable. Using MacBook Pro Microphone."
            )
        case .restored:
            NoticeContent(
                kind: .success,
                title: "Preferred input restored",
                detail: "Studio Display Microphone is in use again."
            )
        case .deferred:
            NoticeContent(
                kind: .info,
                title: "Input changes after this Dictation session",
                detail: "Using MacBook Pro Microphone now; Studio Display Microphone is next."
            )
        case .unavailable:
            NoticeContent(
                kind: .error,
                title: "No input device is available",
                detail: "Connect a microphone before starting a Dictation session."
            )
        }
    }
}

private struct NoticeContent {
    let kind: NoticeKind
    let title: String
    let detail: String
}

private enum NoticeKind {
    case info
    case success
    case warning
    case error
}

private struct SoundRow: View {
    let style: ModuleStyle
    let palette: Palette

    var body: some View {
        PreferenceRow(
            title: "Pause other audio",
            subtitle: "Pause music and mute system audio while dictating",
            style: style,
            palette: palette
        ) {
            Toggle("", isOn: .constant(true))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .tint(palette.accent)
        }
    }
}

private struct AppearanceChoices: View {
    let horizontal: Bool
    let style: AppearanceStyle
    let palette: Palette

    var body: some View {
        let choices = [
            ("System", "circle.lefthalf.filled", "Follows macOS as it changes"),
            ("Light", "sun.max", "Always uses the light appearance"),
            ("Dark", "moon", "Always uses the dark appearance"),
        ]
        Group {
            if horizontal {
                HStack(spacing: style == .lines ? 18 : 8) {
                    ForEach(choices, id: \.0) { choice in
                        AppearanceChoice(
                            title: choice.0,
                            symbol: choice.1,
                            detail: choice.2,
                            selected: choice.0 == "Dark",
                            style: style,
                            palette: palette
                        )
                    }
                }
            } else {
                VStack(spacing: style == .lines ? 0 : 8) {
                    ForEach(choices, id: \.0) { choice in
                        AppearanceChoice(
                            title: choice.0,
                            symbol: choice.1,
                            detail: choice.2,
                            selected: choice.0 == "Dark",
                            style: style,
                            palette: palette
                        )
                    }
                }
            }
        }
    }
}

private struct AppearanceChoice: View {
    let title: String
    let symbol: String
    let detail: String
    let selected: Bool
    let style: AppearanceStyle
    let palette: Palette

    private var backgroundColor: Color {
        if style == .lines {
            return .clear
        }
        return selected ? palette.raised : palette.canvas
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(selected ? palette.accent : palette.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? palette.accent : palette.tertiary)
        }
        .padding(style == .lines ? .vertical : .all, style == .lines ? 11 : 10)
        .padding(.horizontal, style == .lines ? 2 : 0)
        .frame(maxWidth: .infinity, minHeight: style == .cards ? 78 : 54, alignment: .leading)
        .background(
            backgroundColor,
            in: RoundedRectangle(cornerRadius: 7)
        )
        .overlay {
            if style != .lines {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(selected ? palette.accent : palette.border, lineWidth: 1)
            }
        }
        .overlay(alignment: .bottom) {
            if style == .lines {
                Rectangle().fill(palette.border).frame(height: 1)
            }
        }
    }
}

private struct UpdateRow: View {
    let state: UpdateState
    let style: ModuleStyle
    let palette: Palette

    var body: some View {
        PreferenceRow(
            title: "FoldWise Voice",
            subtitle: subtitle,
            style: style,
            palette: palette
        ) {
            switch state {
            case .current:
                HStack(spacing: 8) {
                    Label("Current", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(palette.success)
                        .lineLimit(1)
                        .fixedSize()
                    SecondaryButton("Check again", palette: palette)
                }
            case .checking:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking…").foregroundStyle(palette.secondary)
                }
            case .available:
                PrimaryButton("Download v0.16.0…", palette: palette)
            case .failed:
                SecondaryButton("Check again", palette: palette)
            case .development:
                Label("Packaged builds only", systemImage: "hammer")
                    .foregroundStyle(palette.tertiary)
            }
        }
    }

    private var subtitle: String {
        switch state {
        case .current: "Version 0.15.0 · You’re up to date"
        case .checking: "Version 0.15.0 · Checking for updates"
        case .available: "Version 0.15.0 · Version 0.16.0 is available"
        case .failed: "Version 0.15.0 · Couldn’t reach GitHub"
        case .development: "Version dev · Update checks need a packaged build"
        }
    }
}

private struct PreferenceRow<Trailing: View>: View {
    let title: String
    let subtitle: String
    let style: ModuleStyle
    let palette: Palette
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            trailing
                .font(.system(size: 10.5, weight: .medium))
        }
        .padding(.horizontal, style == .open ? 0 : 12)
        .padding(.vertical, style == .open ? 9 : 10)
    }
}

private struct InputDeviceRow: View {
    let title: String
    let detail: String
    let badge: String?
    let selected: Bool
    let disabled: Bool
    let style: ModuleStyle
    let palette: Palette

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: selected ? "record.circle.fill" : "circle")
                .foregroundStyle(selected ? palette.accent : palette.tertiary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(palette.secondary)
            }
            Spacer()
            if let badge {
                Text(badge)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(selected ? palette.accent : palette.tertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(palette.raised, in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .opacity(disabled ? 0.46 : 1)
        .padding(.horizontal, style == .open ? 0 : 12)
        .padding(.vertical, 9)
        .overlay(alignment: .leading) {
            if selected {
                RoundedRectangle(cornerRadius: 1)
                    .fill(palette.accent)
                    .frame(width: 2, height: 24)
                    .offset(x: style == .open ? -8 : 0)
            }
        }
    }
}

private struct InlineNotice: View {
    let kind: NoticeKind
    let title: String
    let detail: String
    let action: String?
    let palette: Palette

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(palette.secondary)
            }
            Spacer()
            if let action {
                Text(action)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(palette.accent)
            }
        }
        .padding(9)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 2)
        }
    }

    private var color: Color {
        switch kind {
        case .info: palette.accent
        case .success: palette.success
        case .warning: palette.warning
        case .error: palette.error
        }
    }

    private var symbol: String {
        switch kind {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }
}

private struct RowDivider: View {
    let style: ModuleStyle
    let palette: Palette

    var body: some View {
        if style != .open {
            Rectangle()
                .fill(palette.border)
                .frame(height: 1)
                .padding(.leading, 12)
        }
    }
}

private struct ShortcutChip: View {
    let label: String
    let capturing: Bool
    var empty = false
    let palette: Palette

    private var foregroundColor: Color {
        if capturing {
            return palette.accent
        }
        return empty ? palette.secondary : palette.text
    }

    var body: some View {
        HStack(spacing: 5) {
            if capturing {
                Circle()
                    .fill(palette.accent)
                    .frame(width: 6, height: 6)
            }
            Text(label)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(palette.raised, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(capturing ? palette.accent : palette.border, lineWidth: 1)
        }
        .overlay(alignment: .bottom) {
            if !capturing, !empty {
                Rectangle()
                    .fill(palette.borderStrong.opacity(0.55))
                    .frame(height: 1)
                    .padding(.horizontal, 3)
            }
        }
    }
}

private struct IconButton: View {
    let symbol: String
    let palette: Palette

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(palette.secondary)
            .frame(width: 24, height: 24)
            .background(palette.raised, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(palette.border, lineWidth: 1)
            }
    }
}

private struct SecondaryButton: View {
    let title: String
    let palette: Palette

    init(_ title: String, palette: Palette) {
        self.title = title
        self.palette = palette
    }

    var body: some View {
        Text(title)
            .font(.system(size: 10.5, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(palette.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(palette.raised, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(palette.border, lineWidth: 1)
            }
    }
}

private struct PrimaryButton: View {
    let title: String
    let palette: Palette

    init(_ title: String, palette: Palette) {
        self.title = title
        self.palette = palette
    }

    var body: some View {
        Text(title)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(palette.accentText)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(palette.accent, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct RecoveryBanner: View {
    let palette: Palette

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(palette.warning)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text("Configuration recovery")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(
                    "config.json uses an unsupported schema. Voice to Text remains "
                        + "available; configuration changes are disabled."
                )
                .font(.system(size: 10))
                .foregroundStyle(palette.secondary)
                .lineLimit(2)
            }
            Spacer()
            SecondaryButton("Quit", palette: palette)
            PrimaryButton("Reset Configuration", palette: palette)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(palette.surface)
        .overlay(alignment: .leading) {
            Rectangle().fill(palette.warning).frame(width: 3)
        }
    }
}

private struct GlobalStatus: View {
    let message: StatusMessage
    let palette: Palette

    var body: some View {
        let color = message.kind == .success ? palette.success : palette.error
        HStack(spacing: 9) {
            Image(
                systemName: message.kind == .success
                    ? "checkmark.circle.fill"
                    : "xmark.octagon.fill"
            )
            .foregroundStyle(color)
            Text(message.title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(palette.text)
            Text(message.detail)
                .font(.system(size: 10))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
            Spacer()
            if message.kind == .error {
                Text("PERSISTS UNTIL SUPERSEDED")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(color)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(palette.surface)
        .overlay(alignment: .leading) {
            Rectangle().fill(color).frame(width: 3)
        }
    }
}

private struct ReviewBar: View {
    @Binding var variant: SettingsVariant
    @Binding var appearance: PrototypeAppearance
    @Binding var width: WidthPreview
    @Binding var scenario: SettingsScenario
    @Binding var contrast: ContrastPreview
    @Binding var motion: MotionPreview

    var body: some View {
        HStack(spacing: 8) {
            Button {
                stepVariant(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)

            Text("\(variant.key) — \(variant.title)")
                .font(.system(size: 11, weight: .semibold))
                .frame(minWidth: 126)

            Button {
                stepVariant(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)

            Divider().frame(height: 20)
            Picker("", selection: $appearance) {
                ForEach(PrototypeAppearance.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .frame(width: 80)

            Picker("", selection: $width) {
                ForEach(WidthPreview.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .frame(width: 84)

            Picker("", selection: $scenario) {
                ForEach(SettingsScenario.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .frame(width: 132)

            Picker("", selection: $contrast) {
                ForEach(ContrastPreview.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .frame(width: 100)

            Picker("", selection: $motion) {
                ForEach(MotionPreview.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .frame(width: 86)
        }
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Color(hex: 0x1A1E23), in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.4), radius: 12, y: 5)
    }

    private func stepVariant(_ delta: Int) {
        let all = SettingsVariant.allCases
        guard let index = all.firstIndex(of: variant) else { return }
        variant = all[(index + delta + all.count) % all.count]
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

private struct TrafficLights: View {
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(Color(hex: 0xFF5F57))
            Circle().fill(Color(hex: 0xFEBC2E))
            Circle().fill(Color(hex: 0x28C840))
        }
        .frame(width: 52)
        .padding(.horizontal, 2)
    }
}

private struct SidebarToggleGlyph: View {
    let palette: Palette

    var body: some View {
        RoundedRectangle(cornerRadius: 4.5)
            .strokeBorder(palette.tertiary, lineWidth: 1.4)
            .frame(width: 21, height: 16)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(palette.tertiary)
                    .frame(width: 1.4)
                    .padding(.vertical, 1.5)
                    .offset(x: 6)
            }
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
