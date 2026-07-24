// THROWAWAY PROTOTYPE — visual decision aid for Wayfinder ticket
// "Prototype Home, History, and shared Dictation rows".
//
// Three structural translations of Home, History, and their shared 44-point
// Dictation row, switchable from the bottom review bar inside an isolated
// native SwiftUI gallery. This code is intentionally separate from production.

import AppKit
import SwiftUI

private enum SurfacePreview: String, CaseIterable, Identifiable {
    case home = "Home"
    case history = "History"

    var id: String {
        rawValue
    }
}

private enum SurfaceVariant: String, CaseIterable, Identifiable {
    case instrument
    case command
    case spine

    var id: String {
        rawValue
    }

    var key: String {
        switch self {
        case .instrument: "A"
        case .command: "B"
        case .spine: "C"
        }
    }

    var title: String {
        switch self {
        case .instrument: "Instrument Panel"
        case .command: "Command Deck"
        case .spine: "Activity Spine"
        }
    }

    var thesis: String {
        switch self {
        case .instrument:
            "Metrics, readiness, then a dense chronological ledger."
        case .command:
            "The next Dictation session leads; recent work supports it."
        case .spine:
            "Time is the organizing axis across status, activity, and controls."
        }
    }
}

private enum ScenarioPreview: String, CaseIterable, Identifiable {
    case primary = "Primary"
    case alternate = "Alternate"
    case empty = "Empty"
    case attention = "Attention"

    var id: String {
        rawValue
    }

    func label(for surface: SurfacePreview) -> String {
        switch (surface, self) {
        case (.home, .primary): "Ready"
        case (.home, .alternate): "Unavailable metrics"
        case (.home, .empty): "First run"
        case (.home, .attention): "Accessibility"
        case (.history, .primary): "Populated"
        case (.history, .alternate): "Saving off"
        case (.history, .empty): "First run"
        case (.history, .attention): "No results"
        }
    }
}

private enum WidthPreview: String, CaseIterable, Identifiable {
    case wide = "Wide ≥940"
    case compact = "Compact <940"

    var id: String {
        rawValue
    }

    var shellWidth: CGFloat {
        self == .wide ? 1240 : 940
    }

    var sidebarWidth: CGFloat {
        self == .wide ? 178 : 52
    }
}

private enum RowStatePreview: String, CaseIterable, Identifiable {
    case resting = "Resting"
    case hover = "Hover"
    case focus = "Focus"
    case copied = "Copied"
    case menu = "More menu"

    var id: String {
        rawValue
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

    var lineWidth: CGFloat {
        self == .standard ? 1 : 2
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
    let accentHover: Color
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
                accentHover: Color(hex: 0xFF8A4A),
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
                accentHover: Color(hex: 0x9E3305),
                accentText: .white,
                success: Color(hex: 0x147A42),
                warning: Color(hex: 0x865B00),
                error: Color(hex: 0xB4232C)
            )
        }
    }
}

private struct DictationSample: Identifiable {
    let id: Int
    let time: String
    let text: String
    let mode: String
    let icon: String
    let isDeleted: Bool
    let isFlagged: Bool
    let isPolished: Bool
}

private let sampleRows = [
    DictationSample(
        id: 1,
        time: "18:51",
        text: "Send the revised launch notes after the client review.",
        mode: "email",
        icon: "envelope",
        isDeleted: false,
        isFlagged: true,
        isPolished: true
    ),
    DictationSample(
        id: 2,
        time: "12:54",
        text: "The model should stay local and keep the existing fallback.",
        mode: "voice to text",
        icon: "text.bubble",
        isDeleted: false,
        isFlagged: false,
        isPolished: false
    ),
    DictationSample(
        id: 3,
        time: "12:44",
        text: "Break the migration into small reversible checkpoints.",
        mode: "project brief",
        icon: "doc.text",
        isDeleted: true,
        isFlagged: false,
        isPolished: true
    ),
    DictationSample(
        id: 4,
        time: "09:17",
        text: "Book the design review for Thursday afternoon.",
        mode: "casual",
        icon: "quote.bubble",
        isDeleted: false,
        isFlagged: false,
        isPolished: true
    ),
]

private struct SnapshotCase {
    let variant: SurfaceVariant
    let surface: SurfacePreview
    let appearance: PrototypeAppearance
    let scenario: ScenarioPreview
    let width: WidthPreview
    let rowState: RowStatePreview
    let contrast: ContrastPreview

    var filename: String {
        [
            variant.key.lowercased(),
            variant.rawValue,
            surface.rawValue.lowercased(),
            appearance.rawValue.lowercased(),
            scenario.rawValue.lowercased(),
            width == .wide ? "wide" : "compact",
            rowState.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"),
        ].joined(separator: "-") + ".png"
    }
}

@main
private enum HomeHistoryPrototypeApp {
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
            .appendingPathComponent(".context/home-history-shots", isDirectory: true)
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
        for variant in SurfaceVariant.allCases {
            for surface in SurfacePreview.allCases {
                for appearance in PrototypeAppearance.allCases {
                    cases.append(SnapshotCase(
                        variant: variant,
                        surface: surface,
                        appearance: appearance,
                        scenario: .primary,
                        width: .wide,
                        rowState: .resting,
                        contrast: .standard
                    ))
                }
                cases.append(SnapshotCase(
                    variant: variant,
                    surface: surface,
                    appearance: .dark,
                    scenario: .attention,
                    width: .compact,
                    rowState: .focus,
                    contrast: .increased
                ))
            }
            cases.append(SnapshotCase(
                variant: variant,
                surface: .history,
                appearance: .dark,
                scenario: .primary,
                width: .wide,
                rowState: .menu,
                contrast: .standard
            ))
        }

        let size = CGSize(width: 1320, height: 860)
        for item in cases {
            let root = PrototypeRoot(
                initialVariant: item.variant,
                initialSurface: item.surface,
                initialScenario: item.scenario,
                initialWidth: item.width,
                initialRowState: item.rowState,
                initialAppearance: item.appearance,
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
        window.title = "FoldWise Home and History prototype"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.setContentSize(CGSize(width: 1320, height: 860))
        window.contentMinSize = CGSize(width: 1060, height: 760)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        true
    }
}

private struct PrototypeRoot: View {
    @State private var variant: SurfaceVariant
    @State private var surface: SurfacePreview
    @State private var scenario: ScenarioPreview
    @State private var width: WidthPreview
    @State private var rowState: RowStatePreview
    @State private var appearance: PrototypeAppearance
    @State private var contrast: ContrastPreview

    init(
        initialVariant: SurfaceVariant = .instrument,
        initialSurface: SurfacePreview = .home,
        initialScenario: ScenarioPreview = .primary,
        initialWidth: WidthPreview = .wide,
        initialRowState: RowStatePreview = .resting,
        initialAppearance: PrototypeAppearance = .dark,
        initialContrast: ContrastPreview = .standard
    ) {
        _variant = State(initialValue: initialVariant)
        _surface = State(initialValue: initialSurface)
        _scenario = State(initialValue: initialScenario)
        _width = State(initialValue: initialWidth)
        _rowState = State(initialValue: initialRowState)
        _appearance = State(initialValue: initialAppearance)
        _contrast = State(initialValue: initialContrast)
    }

    var body: some View {
        let palette = Palette.ember(appearance)
        ZStack(alignment: .bottom) {
            palette.canvas.ignoresSafeArea()
            ContinuousShell(
                variant: variant,
                surface: surface,
                scenario: scenario,
                width: width,
                rowState: rowState,
                contrast: contrast,
                palette: palette
            )
            .frame(width: width.shellWidth)
            .padding(.top, 20)
            .padding(.bottom, 104)

            ReviewBar(
                variant: $variant,
                surface: $surface,
                scenario: $scenario,
                width: $width,
                rowState: $rowState,
                appearance: $appearance,
                contrast: $contrast
            )
            .padding(.bottom, 16)
        }
        .environment(\.colorScheme, appearance.scheme)
    }
}

private struct ContinuousShell: View {
    let variant: SurfaceVariant
    let surface: SurfacePreview
    let scenario: ScenarioPreview
    let width: WidthPreview
    let rowState: RowStatePreview
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            ShellTitlebar(width: width, palette: palette)
            Hairline(color: borderColor)
            HStack(spacing: 0) {
                Sidebar(
                    active: surface,
                    compact: width == .compact,
                    palette: palette
                )
                .frame(width: width.sidebarWidth)
                Hairline(color: borderColor, vertical: true)
                destination
            }
        }
        .background(palette.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(borderColor, lineWidth: contrast.lineWidth)
        }
        .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
    }

    @ViewBuilder
    private var destination: some View {
        switch surface {
        case .home:
            HomeSurface(
                variant: variant,
                scenario: scenario,
                compact: width == .compact,
                rowState: rowState,
                contrast: contrast,
                palette: palette
            )
        case .history:
            HistorySurface(
                variant: variant,
                scenario: scenario,
                compact: width == .compact,
                rowState: rowState,
                contrast: contrast,
                palette: palette
            )
        }
    }

    private var borderColor: Color {
        contrast == .increased ? palette.borderStrong : palette.border
    }
}

private struct ShellTitlebar: View {
    let width: WidthPreview
    let palette: Palette

    var body: some View {
        HStack(spacing: 12) {
            TrafficLights()
            SidebarToggleGlyph(palette: palette)
            BrandLockup(compact: false, palette: palette)
            Spacer()
            Text(width == .wide ? "WIDE · ≥940 PT" : "COMPACT · <940 PT")
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(palette.tertiary)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(palette.sidebar)
    }
}

private struct Sidebar: View {
    let active: SurfacePreview
    let compact: Bool
    let palette: Palette

    private let destinations: [(String, String)] = [
        ("Home", "house"),
        ("Modes", "wand.and.stars"),
        ("Models", "shippingbox"),
        ("History", "clock"),
        ("Stats", "chart.bar"),
        ("Settings", "slider.horizontal.3"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 5) {
                ForEach(destinations, id: \.0) { item in
                    let selected = item.0 == active.rawValue
                    HStack(spacing: 10) {
                        Image(systemName: selected ? item.1 + ".fill" : item.1)
                            .frame(width: 18)
                            .foregroundStyle(selected ? palette.accent : palette.tertiary)
                        if !compact {
                            Text(item.0)
                                .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? palette.text : palette.secondary)
                            Spacer()
                        }
                    }
                    .padding(.horizontal, compact ? 10 : 12)
                    .frame(height: 36)
                    .background(selected ? palette.raised : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(alignment: .leading) {
                        if selected {
                            Rectangle()
                                .fill(palette.accent)
                                .frame(width: 2)
                        }
                    }
                }
            }
            .padding(.horizontal, compact ? 6 : 10)
            .padding(.top, 14)
            Spacer()
            if !compact {
                VStack(alignment: .leading, spacing: 5) {
                    Label("All systems go", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(palette.success)
                    Text("v0.15.0 · up to date")
                        .foregroundStyle(palette.tertiary)
                }
                .font(.system(size: 9.5))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(palette.border, lineWidth: 1)
                }
                .padding(10)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(palette.success)
                    .padding(.bottom, 16)
            }
        }
        .background(palette.sidebar)
    }
}

private struct HomeSurface: View {
    let variant: SurfaceVariant
    let scenario: ScenarioPreview
    let compact: Bool
    let rowState: RowStatePreview
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        Group {
            if scenario == .empty {
                emptyHome
            } else {
                switch variant {
                case .instrument:
                    InstrumentHome(
                        scenario: scenario,
                        compact: compact,
                        rowState: rowState,
                        contrast: contrast,
                        palette: palette
                    )
                case .command:
                    CommandHome(
                        scenario: scenario,
                        compact: compact,
                        rowState: rowState,
                        contrast: contrast,
                        palette: palette
                    )
                case .spine:
                    SpineHome(
                        scenario: scenario,
                        compact: compact,
                        rowState: rowState,
                        contrast: contrast,
                        palette: palette
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.canvas)
    }

    private var emptyHome: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeading(palette: palette)
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(palette.accent)
                Text("Your Dictation sessions will appear here")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text("Hold ⌘ Right and speak. FoldWise keeps text on this Mac; no audio is saved.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            .frame(maxWidth: .infinity)
            Spacer()
        }
        .padding(28)
    }
}

private struct InstrumentHome: View {
    let scenario: ScenarioPreview
    let compact: Bool
    let rowState: RowStatePreview
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeading(palette: palette)
                MetricsGrid(
                    unavailable: scenario == .alternate,
                    compact: compact,
                    contrast: contrast,
                    palette: palette
                )
                .padding(.top, 24)
                SystemBand(
                    attention: scenario == .attention,
                    contrast: contrast,
                    palette: palette
                )
                .padding(.top, 12)
                HStack {
                    SectionTitle("Today", icon: "list.bullet", palette: palette)
                    Spacer()
                    Text("Newest 10")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.tertiary)
                }
                .padding(.top, 22)
                DictationLedger(
                    variant: .instrument,
                    history: false,
                    rowState: rowState,
                    contrast: contrast,
                    palette: palette
                )
                .padding(.top, 8)
                Text("All history →")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .padding(.top, 12)
            }
            .padding(26)
        }
    }
}

private struct CommandHome: View {
    let scenario: ScenarioPreview
    let compact: Bool
    let rowState: RowStatePreview
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                CommandHeader(
                    attention: scenario == .attention,
                    contrast: contrast,
                    palette: palette
                )
                if compact {
                    MetricsGrid(
                        unavailable: scenario == .alternate,
                        compact: true,
                        contrast: contrast,
                        palette: palette
                    )
                    recent
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        MetricsCluster(
                            unavailable: scenario == .alternate,
                            contrast: contrast,
                            palette: palette
                        )
                        .frame(width: 218)
                        recent
                    }
                }
            }
            .padding(26)
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle("Recent Dictation sessions", icon: "text.alignleft", palette: palette)
                Spacer()
                Text("All history →")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(palette.accent)
            }
            DictationLedger(
                variant: .command,
                history: false,
                rowState: rowState,
                contrast: contrast,
                palette: palette
            )
        }
    }
}

private struct SpineHome: View {
    let scenario: ScenarioPreview
    let compact: Bool
    let rowState: RowStatePreview
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 24) {
                    PageHeading(palette: palette)
                    if !compact {
                        Spacer()
                        MetricSentence(
                            unavailable: scenario == .alternate,
                            palette: palette
                        )
                    }
                }
                if compact {
                    MetricSentence(
                        unavailable: scenario == .alternate,
                        palette: palette
                    )
                }
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        SystemMarker(
                            attention: scenario == .attention,
                            palette: palette
                        )
                        Text("Stats →")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(palette.accent)
                    }
                    .frame(width: compact ? 120 : 150, alignment: .leading)
                    DictationSpine(
                        history: false,
                        rowState: rowState,
                        contrast: contrast,
                        palette: palette
                    )
                }
            }
            .padding(26)
        }
    }
}

private struct HistorySurface: View {
    let variant: SurfaceVariant
    let scenario: ScenarioPreview
    let compact: Bool
    let rowState: RowStatePreview
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        Group {
            switch variant {
            case .instrument:
                InstrumentHistory(
                    scenario: scenario,
                    rowState: rowState,
                    contrast: contrast,
                    palette: palette
                )
            case .command:
                CommandHistory(
                    scenario: scenario,
                    compact: compact,
                    rowState: rowState,
                    contrast: contrast,
                    palette: palette
                )
            case .spine:
                SpineHistory(
                    scenario: scenario,
                    compact: compact,
                    rowState: rowState,
                    contrast: contrast,
                    palette: palette
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.canvas)
    }
}

private struct InstrumentHistory: View {
    let scenario: ScenarioPreview
    let rowState: RowStatePreview
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HistoryHeading(palette: palette)
                HistorySettingsStrip(
                    saving: scenario != .alternate,
                    contrast: contrast,
                    palette: palette
                )
                HistorySearch(palette: palette)
                HistoryCollectionState(
                    variant: .instrument,
                    scenario: scenario,
                    rowState: rowState,
                    contrast: contrast,
                    palette: palette
                )
            }
            .padding(26)
        }
    }
}

private struct CommandHistory: View {
    let scenario: ScenarioPreview
    let compact: Bool
    let rowState: RowStatePreview
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HistoryHeading(palette: palette)
                if compact {
                    HistoryUtilityLane(
                        saving: scenario != .alternate,
                        horizontal: true,
                        contrast: contrast,
                        palette: palette
                    )
                    collection
                } else {
                    HStack(alignment: .top, spacing: 18) {
                        HistoryUtilityLane(
                            saving: scenario != .alternate,
                            horizontal: false,
                            contrast: contrast,
                            palette: palette
                        )
                        .frame(width: 210)
                        collection
                    }
                }
            }
            .padding(26)
        }
    }

    private var collection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HistorySearch(palette: palette)
            HistoryCollectionState(
                variant: .command,
                scenario: scenario,
                rowState: rowState,
                contrast: contrast,
                palette: palette
            )
        }
    }
}

private struct SpineHistory: View {
    let scenario: ScenarioPreview
    let compact: Bool
    let rowState: RowStatePreview
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    HistoryHeading(palette: palette)
                    Spacer()
                    TogglePill(
                        title: scenario == .alternate ? "Saving off" : "Saving on",
                        active: scenario != .alternate,
                        palette: palette
                    )
                }
                HistorySearch(palette: palette)
                if scenario == .empty || scenario == .attention {
                    HistoryCollectionState(
                        variant: .spine,
                        scenario: scenario,
                        rowState: rowState,
                        contrast: contrast,
                        palette: palette
                    )
                } else {
                    HStack(alignment: .top, spacing: compact ? 12 : 22) {
                        VStack(alignment: .leading, spacing: 8) {
                            MicroLabel("RETENTION", palette: palette)
                            Text("30 days")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.text)
                            Text("Clear all…")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(palette.error)
                                .padding(.top, 12)
                        }
                        .frame(width: compact ? 95 : 126, alignment: .leading)
                        DictationSpine(
                            history: true,
                            rowState: rowState,
                            contrast: contrast,
                            palette: palette
                        )
                    }
                }
            }
            .padding(26)
        }
    }
}

private struct PageHeading: View {
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ready when you are.")
                .font(.system(size: 30, weight: .semibold))
                .tracking(-0.5)
                .foregroundStyle(palette.text)
            HStack(spacing: 6) {
                Text("Hold")
                Keycap(text: "right ⌘", palette: palette)
                Text("and speak — release to insert at your cursor.")
            }
            .font(.system(size: 12))
            .foregroundStyle(palette.secondary)
        }
    }
}

private struct HistoryHeading: View {
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("History")
                .font(.system(size: 30, weight: .semibold))
                .tracking(-0.5)
                .foregroundStyle(palette.text)
            Text("Text-only and on this Mac. No audio is saved.")
                .font(.system(size: 11.5))
                .foregroundStyle(palette.secondary)
        }
    }
}

private struct MetricsGrid: View {
    let unavailable: Bool
    let compact: Bool
    let contrast: ContrastPreview
    let palette: Palette

    private var metrics: [(String, String, String, String)] {
        [
            ("textformat", "5,809", "", "Total words"),
            ("bolt", unavailable ? "—" : "125", unavailable ? "" : "wpm", "Speaking speed"),
            ("flame", unavailable ? "—" : "6", unavailable ? "" : "days", "Current streak"),
            ("timer", unavailable ? "—" : "~65", unavailable ? "" : "min", "Time saved"),
        ]
    }

    var body: some View {
        if compact {
            VStack(spacing: 8) {
                metricRow(Array(metrics.prefix(2)))
                metricRow(Array(metrics.suffix(2)))
            }
        } else {
            metricRow(metrics)
        }
    }

    private func metricRow(_ values: [(String, String, String, String)]) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(values.enumerated()), id: \.offset) { item in
                MetricTile(
                    icon: item.element.0,
                    value: item.element.1,
                    unit: item.element.2,
                    label: item.element.3,
                    contrast: contrast,
                    palette: palette
                )
            }
        }
    }
}

private struct MetricsCluster: View {
    let unavailable: Bool
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        VStack(spacing: 8) {
            MetricTile(
                icon: "textformat",
                value: "5,809",
                unit: "",
                label: "Total words",
                contrast: contrast,
                palette: palette
            )
            HStack(spacing: 8) {
                MiniMetric(value: unavailable ? "—" : "125", label: "WPM", palette: palette)
                MiniMetric(value: unavailable ? "—" : "6 d", label: "Streak", palette: palette)
            }
            MiniMetric(
                value: unavailable ? "—" : "~65 min",
                label: "Time saved",
                palette: palette
            )
        }
    }
}

private struct MetricTile: View {
    let icon: String
    let value: String
    let unit: String
    let label: String
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.accent)
                Text(value)
                    .font(.system(size: 19, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(palette.text)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(palette.tertiary)
                }
            }
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(palette.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    contrast == .increased ? palette.borderStrong : palette.border,
                    lineWidth: contrast.lineWidth
                )
        }
    }
}

private struct MiniMetric: View {
    let value: String
    let label: String
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.text)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(palette.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct MetricSentence: View {
    let unavailable: Bool
    let palette: Palette

    var body: some View {
        HStack(spacing: 16) {
            metric("5,809", "words")
            metric(unavailable ? "—" : "125", "wpm")
            metric(unavailable ? "—" : "6", "day streak")
            metric(unavailable ? "—" : "~65", "min saved")
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.border).frame(height: 1)
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.text)
            Text(label.uppercased())
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .tracking(0.35)
                .foregroundStyle(palette.tertiary)
        }
    }
}

private struct SystemBand: View {
    let attention: Bool
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: attention ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(attention ? palette.warning : palette.success)
            VStack(alignment: .leading, spacing: 4) {
                Text(attention ? "Needs attention" : "All systems go")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(
                    attention
                        ? "Parakeet TDT v3 · no polish model · accessibility missing · v0.15.0"
                        : "Parakeet TDT v3 · no polish model · accessibility granted · v0.15.0"
                )
                .font(.system(size: 9.5))
                .foregroundStyle(palette.tertiary)
            }
            Spacer()
            Text(attention ? "Open Accessibility…" : "Stats →")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(palette.accent)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
        .background(palette.raised)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(attention ? palette.warning : palette.accent)
                .frame(width: contrast == .increased ? 3 : 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    contrast == .increased ? palette.borderStrong : palette.border,
                    lineWidth: contrast.lineWidth
                )
        }
    }
}

private struct CommandHeader: View {
    let attention: Bool
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(attention ? palette.warning : palette.success)
                        .frame(width: 8, height: 8)
                    Text(attention ? "ACCESSIBILITY NEEDED" : "READY")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(attention ? palette.warning : palette.success)
                }
                Text("Hold right ⌘ and speak.")
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(palette.text)
                Text("Release to insert at your cursor · Parakeet TDT v3 · no polish model")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 7) {
                Image(systemName: "waveform")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(palette.accent)
                Text(attention ? "Open Accessibility…" : "All systems go")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(attention ? palette.warning : palette.secondary)
            }
        }
        .padding(18)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            Rectangle().fill(palette.accent).frame(width: 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    contrast == .increased ? palette.borderStrong : palette.border,
                    lineWidth: contrast.lineWidth
                )
        }
    }
}

private struct SystemMarker: View {
    let attention: Bool
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Rectangle()
                .fill(attention ? palette.warning : palette.success)
                .frame(width: 30, height: 3)
            Text(attention ? "Needs attention" : "All systems go")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.text)
            Text(attention ? "Accessibility missing" : "Parakeet TDT v3\nAccessibility granted")
                .font(.system(size: 9.5))
                .foregroundStyle(palette.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            if attention {
                Text("Open Accessibility…")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(palette.accent)
            }
        }
    }
}

private struct HistorySettingsStrip: View {
    let saving: Bool
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        HStack(spacing: 8) {
            SettingCell(
                title: "Save dictation history",
                detail: saving ? "On · text-only" : "Off · existing text retained",
                trailing: saving ? "ON" : "OFF",
                accent: saving ? palette.success : palette.warning,
                contrast: contrast,
                palette: palette
            )
            SettingCell(
                title: "Keep history for",
                detail: "Automatically deletes older text",
                trailing: saving ? "30 days⌄" : "Hidden",
                accent: palette.accent,
                contrast: contrast,
                palette: palette
            )
        }
    }
}

private struct SettingCell: View {
    let title: String
    let detail: String
    let trailing: String
    let accent: Color
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(palette.tertiary)
            }
            Spacer()
            Text(trailing)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 62)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    contrast == .increased ? palette.borderStrong : palette.border,
                    lineWidth: contrast.lineWidth
                )
        }
    }
}

private struct HistoryUtilityLane: View {
    let saving: Bool
    let horizontal: Bool
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        Group {
            if horizontal {
                HStack(spacing: 14) { content }
            } else {
                VStack(alignment: .leading, spacing: 16) { content }
            }
        }
        .padding(14)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    contrast == .increased ? palette.borderStrong : palette.border,
                    lineWidth: contrast.lineWidth
                )
        }
    }

    @ViewBuilder
    private var content: some View {
        utility("SAVING", saving ? "On" : "Off", saving ? palette.success : palette.warning)
        utility("RETENTION", saving ? "30 days" : "Hidden", palette.accent)
        utility("FILTER", "All text", palette.secondary)
        if !horizontal {
            Spacer(minLength: 12)
        }
        Text("Clear all history…")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(palette.error)
    }

    private func utility(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MicroLabel(label, palette: palette)
            Text(value)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(color)
        }
    }
}

private struct HistorySearch: View {
    let palette: Palette

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.tertiary)
            Text("Search Dictation sessions")
                .foregroundStyle(palette.tertiary)
            Spacer()
            TogglePill(title: "Flagged only", active: false, palette: palette)
        }
        .font(.system(size: 10.5))
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(palette.raised)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(palette.border, lineWidth: 1)
        }
    }
}

private struct HistoryCollectionState: View {
    let variant: SurfaceVariant
    let scenario: ScenarioPreview
    let rowState: RowStatePreview
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        switch scenario {
        case .empty:
            EmptyPanel(
                icon: "clock.badge.questionmark",
                title: "No Dictation sessions yet",
                detail: "Your text will appear here after you speak. No audio is ever saved.",
                palette: palette
            )
        case .attention:
            EmptyPanel(
                icon: "line.3.horizontal.decrease.circle",
                title: "No matches",
                detail: "No dictation matches “quarterly invoice”. Try different words or clear the filters.",
                palette: palette
            )
        case .primary, .alternate:
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Today", icon: "calendar", palette: palette)
                DictationLedger(
                    variant: variant,
                    history: true,
                    rowState: rowState,
                    contrast: contrast,
                    palette: palette
                )
                if rowState == .menu {
                    MoreMenuPreview(palette: palette)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                SectionTitle("Yesterday", icon: "calendar", palette: palette)
                    .padding(.top, 4)
                DictationRowPreview(
                    variant: variant,
                    sample: sampleRows[3],
                    history: true,
                    state: .resting,
                    contrast: contrast,
                    palette: palette
                )
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                if variant != .command {
                    Text("Clear all history…")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(palette.error)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }
}

private struct DictationLedger: View {
    let variant: SurfaceVariant
    let history: Bool
    let rowState: RowStatePreview
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(sampleRows.prefix(3).enumerated()), id: \.element.id) { item in
                DictationRowPreview(
                    variant: variant,
                    sample: item.element,
                    history: history,
                    state: item.offset == 0 ? rowState : .resting,
                    contrast: contrast,
                    palette: palette
                )
                if item.offset < 2 {
                    Hairline(color: borderColor)
                }
            }
        }
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(borderColor, lineWidth: contrast.lineWidth)
        }
    }

    private var borderColor: Color {
        contrast == .increased ? palette.borderStrong : palette.border
    }
}

private struct DictationSpine: View {
    let history: Bool
    let rowState: RowStatePreview
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(palette.accent).frame(width: 7, height: 7)
                Text("TODAY")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(palette.tertiary)
            }
            ForEach(Array(sampleRows.prefix(3).enumerated()), id: \.element.id) { item in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(item.offset == 0 ? palette.accent : palette.border)
                        .frame(width: 1)
                        .padding(.leading, 3)
                    DictationRowPreview(
                        variant: .spine,
                        sample: item.element,
                        history: history,
                        state: item.offset == 0 ? rowState : .resting,
                        contrast: contrast,
                        palette: palette
                    )
                    .padding(.leading, 12)
                }
            }
            if history, rowState == .menu {
                MoreMenuPreview(palette: palette)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 8)
            } else if !history {
                Text("All history →")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .padding(.top, 10)
                    .padding(.leading, 16)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DictationRowPreview: View {
    let variant: SurfaceVariant
    let sample: DictationSample
    let history: Bool
    let state: RowStatePreview
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        HStack(spacing: variant == .command ? 9 : 11) {
            switch variant {
            case .instrument:
                timestamp
                Rectangle().fill(palette.accent).frame(width: 2, height: 18)
                rowText
            case .command:
                modeGlyph
                rowText
                timestamp
            case .spine:
                timestamp
                    .padding(.horizontal, 6)
                    .frame(height: 22)
                    .background(palette.raised)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                rowText
            }
            Spacer(minLength: 10)
            trailing
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(state == .hover ? palette.hover : .clear)
        .overlay {
            if state == .focus {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(palette.accent, lineWidth: 2)
                    .padding(2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(sample.time), \(sample.text), Mode \(sample.mode), "
                + "\(sample.isPolished ? "Polished" : "Raw"), "
                + "\(sample.isFlagged ? "Flagged" : "Not flagged")"
        )
    }

    private var timestamp: some View {
        Text(sample.time)
            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(palette.tertiary)
            .frame(width: 38, alignment: .leading)
    }

    private var modeGlyph: some View {
        Image(systemName: sample.icon)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(palette.accent)
            .frame(width: 20, height: 20)
            .background(palette.raised)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var rowText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(sample.text)
                .font(.system(size: 10.5))
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .truncationMode(.tail)
            if variant == .command {
                Text(
                    sample.mode
                        + (sample.isDeleted ? " · deleted Mode" : "")
                        + (sample.isPolished ? " · polished" : " · raw")
                )
                .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.tertiary)
                .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if state == .resting {
            HStack(spacing: 5) {
                if variant != .command {
                    Image(systemName: sample.icon)
                        .font(.system(size: 9, weight: .semibold))
                }
                Text(sample.mode.lowercased().prefix(16))
                    .lineLimit(1)
                if sample.isDeleted {
                    Text("deleted").underline()
                }
                if sample.isFlagged {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(palette.accent)
                }
            }
            .font(.system(size: 8.5, weight: .medium))
            .foregroundStyle(palette.tertiary)
        } else {
            HStack(spacing: 4) {
                action(
                    state == .copied ? "checkmark" : "doc.on.doc",
                    color: state == .copied ? palette.success : palette.secondary
                )
                action(
                    sample.isFlagged ? "flag.fill" : "flag",
                    color: sample.isFlagged ? palette.accent : palette.secondary
                )
                if history {
                    action("ellipsis", color: palette.secondary)
                }
            }
        }
    }

    private func action(_ icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 26, height: 26)
            .background(palette.raised)
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private struct EmptyPanel: View {
    let icon: String
    let title: String
    let detail: String
    let palette: Palette

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(palette.accent)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.text)
            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(palette.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, minHeight: 190)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(palette.border, lineWidth: 1)
        }
    }
}

private struct MoreMenuPreview: View {
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuRow("doc.on.doc", "Copy")
            menuRow("doc.on.clipboard", "Copy raw")
            menuRow("flag", "Flag for my review")
            menuRow("arrow.triangle.2.circlepath", "Re-run Polish")
            Hairline(color: palette.border)
                .padding(.vertical, 4)
            menuRow("trash", "Delete", color: palette.error)
        }
        .padding(.vertical, 5)
        .frame(width: 176)
        .background(palette.raised)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(palette.borderStrong, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
    }

    private func menuRow(
        _ icon: String,
        _ title: String,
        color: Color? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 14)
            Text(title)
            Spacer()
            if title == "Re-run Polish" {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(color ?? palette.text)
        .padding(.horizontal, 10)
        .frame(height: 25)
    }
}

private struct SectionTitle: View {
    let title: String
    let icon: String
    let palette: Palette

    init(_ title: String, icon: String, palette: Palette) {
        self.title = title
        self.icon = icon
        self.palette = palette
    }

    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(palette.text)
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
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(palette.tertiary)
    }
}

private struct TogglePill: View {
    let title: String
    let active: Bool
    let palette: Palette

    var body: some View {
        Label(title, systemImage: active ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(active ? palette.text : palette.tertiary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(palette.border, lineWidth: 1)
            }
    }
}

private struct Keycap: View {
    let text: String
    let palette: Palette

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(palette.text)
            .padding(.horizontal, 7)
            .frame(height: 23)
            .background(palette.raised)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(palette.border, lineWidth: 1)
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
                    Text("FoldWise").foregroundStyle(palette.accent)
                    Text("Voice").foregroundStyle(palette.text)
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
    @Binding var variant: SurfaceVariant
    @Binding var surface: SurfacePreview
    @Binding var scenario: ScenarioPreview
    @Binding var width: WidthPreview
    @Binding var rowState: RowStatePreview
    @Binding var appearance: PrototypeAppearance
    @Binding var contrast: ContrastPreview

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 9) {
                Button { cycle(-1) } label: {
                    Image(systemName: "chevron.left")
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                .help("Previous variant (Command–Left Arrow)")

                Text("\(variant.key) — \(variant.title)")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(minWidth: 148)

                Button { cycle(1) } label: {
                    Image(systemName: "chevron.right")
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command])
                .help("Next variant (Command–Right Arrow)")

                Divider().frame(height: 18)
                reviewPicker("Surface", selection: $surface, width: 130)
                Divider().frame(height: 18)
                scenarioPicker
                Divider().frame(height: 18)
                reviewPicker("Width", selection: $width, width: 190)
            }
            HStack(spacing: 9) {
                Text(variant.thesis)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(width: 290, alignment: .leading)
                reviewPicker("Row", selection: $rowState, width: 330)
                reviewPicker("Appearance", selection: $appearance, width: 110)
                reviewPicker("Contrast", selection: $contrast, width: 150)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.white)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.94), in: RoundedRectangle(cornerRadius: 11))
        .shadow(color: .black.opacity(0.28), radius: 16, y: 6)
        .environment(\.colorScheme, .dark)
    }

    private var scenarioPicker: some View {
        Picker("State", selection: $scenario) {
            ForEach(ScenarioPreview.allCases) { item in
                Text(item.label(for: surface)).tag(item)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 310)
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
        let variants = SurfaceVariant.allCases
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
