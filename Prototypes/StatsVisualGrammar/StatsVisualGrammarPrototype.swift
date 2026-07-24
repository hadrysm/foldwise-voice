// THROWAWAY PROTOTYPE — visual decision aid for Wayfinder ticket
// "Prototype Stats within the new visual grammar".
//
// Three visual treatments of the approved Stats hierarchy, switchable from the
// bottom review bar inside the approved Continuous Frame shell. Product data,
// order, calendar behavior, focus behavior, and accessibility contracts stay
// fixed; only rendering changes.

import AppKit
import SwiftUI

private enum StatsVariant: String, CaseIterable, Identifiable {
    case tiles
    case rail
    case pulse

    var id: String {
        rawValue
    }

    var key: String {
        switch self {
        case .tiles: "A"
        case .rail: "B"
        case .pulse: "C"
        }
    }

    var title: String {
        switch self {
        case .tiles: "Ember Tiles"
        case .rail: "Signal Rail"
        case .pulse: "Dictation Pulse"
        }
    }

    var thesis: String {
        switch self {
        case .tiles:
            "Four quiet instruments above one contained month."
        case .rail:
            "Lifetime totals read as one continuous signal; the month stays flat and precise."
        case .pulse:
            "The month leads, with spoken activity carrying a waveform-shaped non-color cue."
        }
    }
}

private enum Scenario: String, CaseIterable, Identifiable {
    case populated = "Populated"
    case empty = "Empty"
    case savingOff = "Saving off"
    case quietMonth = "Quiet month"

    var id: String {
        rawValue
    }

    var hasLifetimeHistory: Bool {
        self != .empty
    }

    var hasCurrentMonthActivity: Bool {
        self == .populated || self == .savingOff
    }
}

private enum PreviewAppearance: String, CaseIterable, Identifiable {
    case light = "Light"
    case dark = "Dark"

    var id: String {
        rawValue
    }

    var scheme: ColorScheme {
        self == .light ? .light : .dark
    }
}

private enum WindowPreset: String, CaseIterable, Identifiable {
    case compact = "880 × 640"
    case wide = "1180 × 760"

    var id: String {
        rawValue
    }

    var size: CGSize {
        switch self {
        case .compact: CGSize(width: 880, height: 640)
        case .wide: CGSize(width: 1180, height: 760)
        }
    }
}

private enum InteractionPreview: String, CaseIterable, Identifiable {
    case neutral = "Neutral"
    case hover = "Hover"
    case focus = "Focus"

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

private enum MotionPreview: String, CaseIterable, Identifiable {
    case standard = "Motion"
    case reduced = "Reduced"

    var id: String {
        rawValue
    }
}

private struct Metric: Identifiable {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    var id: String {
        title
    }
}

private struct ActivityDay: Identifiable {
    let day: Int
    let words: Int
    let sessions: Int

    var id: Int {
        day
    }

    var isToday: Bool {
        day == 22
    }

    var isFuture: Bool {
        day > 22
    }

    var hasActivity: Bool {
        words > 0
    }

    var level: Int {
        switch words {
        case 0: 0
        case 1 ..< 250: 1
        case 250 ..< 600: 2
        case 600 ..< 1000: 3
        case 1000 ..< 1600: 4
        default: 5
        }
    }

    var date: Date {
        prototypeCalendar.date(
            byAdding: .day,
            value: day - 1,
            to: prototypeMonthStart
        ) ?? prototypeMonthStart
    }

    var fullDate: String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var accessibilityValue: String {
        guard hasActivity else {
            return "No dictated words. No saved Dictation sessions"
        }
        let sessionText = sessions == 1 ? "1 saved session" : "\(sessions) saved sessions"
        return "\(words.formatted()) spoken words across \(sessionText). Timing available"
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
    let warning: Color

    static func ember(_ appearance: PreviewAppearance) -> Palette {
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
                warning: Color(hex: 0xF0B44B)
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
                warning: Color(hex: 0x865B00)
            )
        }
    }
}

private let prototypeCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US")
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    calendar.firstWeekday = 1
    return calendar
}()

private let prototypeMonthStart = prototypeCalendar.date(
    from: DateComponents(year: 2026, month: 7, day: 1)
) ?? Date()

private let sampleWords = [
    0, 180, 540, 1210, 0, 0, 840,
    1560, 980, 0, 440, 1910, 710, 0,
    210, 680, 1310, 1720, 0, 360, 790,
    1100, 0, 0, 0, 0, 0, 0, 0, 0, 0,
]

private func days(for scenario: Scenario) -> [ActivityDay] {
    sampleWords.enumerated().map { index, sample in
        let day = index + 1
        let words = scenario.hasCurrentMonthActivity && day <= 22 ? sample : 0
        return ActivityDay(
            day: day,
            words: words,
            sessions: words == 0 ? 0 : max(1, min(6, words / 360))
        )
    }
}

private func metrics(for scenario: Scenario) -> [Metric] {
    let hasHistory = scenario.hasLifetimeHistory
    return [
        Metric(
            title: "Words dictated",
            value: hasHistory ? "14,680" : "0",
            detail: "from saved history",
            symbol: "quote.bubble"
        ),
        Metric(
            title: "Speaking speed",
            value: hasHistory ? "137 wpm" : "—",
            detail: "pauses included",
            symbol: "waveform"
        ),
        Metric(
            title: "Current streak",
            value: hasHistory ? "3 days" : "—",
            detail: "through today",
            symbol: "flame"
        ),
        Metric(
            title: "Time saved",
            value: hasHistory ? "~1 hr 04 min" : "—",
            detail: "versus 40 wpm typing",
            symbol: "clock.arrow.circlepath"
        ),
    ]
}

@main
private enum StatsVisualGrammarPrototypeApp {
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
            .appendingPathComponent(
                ".context/stats-visual-grammar-shots",
                isDirectory: true
            )
        try? FileManager.default.createDirectory(
            at: output,
            withIntermediateDirectories: true
        )
        if let files = try? FileManager.default.contentsOfDirectory(
            at: output,
            includingPropertiesForKeys: nil
        ) {
            for file in files where file.pathExtension == "png" {
                try? FileManager.default.removeItem(at: file)
            }
        }

        var cases: [SnapshotCase] = []
        for appearance in PreviewAppearance.allCases {
            for variant in StatsVariant.allCases {
                cases.append(SnapshotCase(
                    variant: variant,
                    scenario: .populated,
                    appearance: appearance,
                    preset: .wide,
                    interaction: .hover,
                    contrast: .standard,
                    motion: .standard
                ))
            }
        }
        cases += [
            SnapshotCase(
                variant: .tiles, scenario: .empty, appearance: .light,
                preset: .compact, interaction: .neutral,
                contrast: .standard, motion: .standard
            ),
            SnapshotCase(
                variant: .tiles, scenario: .savingOff, appearance: .dark,
                preset: .compact, interaction: .focus,
                contrast: .standard, motion: .standard
            ),
            SnapshotCase(
                variant: .rail, scenario: .quietMonth, appearance: .light,
                preset: .compact, interaction: .neutral,
                contrast: .increased, motion: .standard
            ),
            SnapshotCase(
                variant: .pulse, scenario: .populated, appearance: .dark,
                preset: .compact, interaction: .focus,
                contrast: .increased, motion: .reduced
            ),
        ]

        for item in cases {
            let size = item.preset.size
            let root = PrototypeRoot(
                initialVariant: item.variant,
                initialScenario: item.scenario,
                initialAppearance: item.appearance,
                initialPreset: item.preset,
                initialInteraction: item.interaction,
                initialContrast: item.contrast,
                initialMotion: item.motion
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
            RunLoop.main.run(until: Date().addingTimeInterval(0.12))
            hosting.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            guard let bitmap = hosting.bitmapImageRepForCachingDisplay(
                in: hosting.bounds
            ) else {
                continue
            }
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            guard let png = bitmap.representation(
                using: .png,
                properties: [:]
            ) else {
                continue
            }
            try? png.write(to: output.appendingPathComponent(item.filename))
            window.orderOut(nil)
        }
    }
}

private struct SnapshotCase {
    let variant: StatsVariant
    let scenario: Scenario
    let appearance: PreviewAppearance
    let preset: WindowPreset
    let interaction: InteractionPreview
    let contrast: ContrastPreview
    let motion: MotionPreview

    var filename: String {
        [
            variant.key.lowercased(),
            variant.rawValue,
            scenario.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"),
            appearance.rawValue.lowercased(),
            preset == .compact ? "compact" : "wide",
            interaction.rawValue.lowercased(),
            contrast == .increased ? "contrast" : "standard",
            motion == .reduced ? "reduced" : "motion",
        ].joined(separator: "-") + ".png"
    }
}

@MainActor
private final class PrototypeAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hosting = NSHostingController(rootView: PrototypeRoot())
        let window = NSWindow(contentViewController: hosting)
        window.title = "FoldWise Stats visual-grammar prototype"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.setContentSize(WindowPreset.wide.size)
        window.contentMinSize = WindowPreset.compact.size
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        true
    }
}

private struct PrototypeRoot: View {
    @State private var variant: StatsVariant
    @State private var scenario: Scenario
    @State private var appearance: PreviewAppearance
    @State private var preset: WindowPreset
    @State private var interaction: InteractionPreview
    @State private var contrast: ContrastPreview
    @State private var motion: MotionPreview

    init(
        initialVariant: StatsVariant = .tiles,
        initialScenario: Scenario = .populated,
        initialAppearance: PreviewAppearance = .dark,
        initialPreset: WindowPreset = .wide,
        initialInteraction: InteractionPreview = .hover,
        initialContrast: ContrastPreview = .standard,
        initialMotion: MotionPreview = .standard
    ) {
        _variant = State(initialValue: initialVariant)
        _scenario = State(initialValue: initialScenario)
        _appearance = State(initialValue: initialAppearance)
        _preset = State(initialValue: initialPreset)
        _interaction = State(initialValue: initialInteraction)
        _contrast = State(initialValue: initialContrast)
        _motion = State(initialValue: initialMotion)
    }

    var body: some View {
        let palette = Palette.ember(appearance)
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                palette.canvas.ignoresSafeArea()
                VStack(spacing: 0) {
                    PrototypeTitlebar(palette: palette)
                    Hairline(
                        color: contrast == .increased
                            ? palette.borderStrong
                            : palette.border,
                        width: contrast == .increased ? 2 : 1
                    )
                    HStack(spacing: 0) {
                        PrototypeSidebar(
                            compact: geometry.size.width < 940,
                            palette: palette
                        )
                        Hairline(
                            color: contrast == .increased
                                ? palette.borderStrong
                                : palette.border,
                            width: contrast == .increased ? 2 : 1,
                            vertical: true
                        )
                        StatsCanvas(
                            variant: variant,
                            scenario: scenario,
                            interaction: interaction,
                            contrast: contrast,
                            motion: motion,
                            palette: palette
                        )
                    }
                }

                ReviewBar(
                    variant: $variant,
                    scenario: $scenario,
                    appearance: $appearance,
                    preset: $preset,
                    interaction: $interaction,
                    contrast: $contrast,
                    motion: $motion
                )
                .padding(.bottom, 12)
            }
            .animation(
                motion == .reduced ? nil : .easeOut(duration: 0.16),
                value: variant
            )
        }
        .preferredColorScheme(appearance.scheme)
        .frame(minWidth: 880, minHeight: 640)
    }
}

private struct PrototypeTitlebar: View {
    let palette: Palette

    var body: some View {
        HStack(spacing: 11) {
            Spacer().frame(width: 72)
            Image(systemName: "sidebar.left")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.tertiary)
            Image(systemName: "waveform")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.accent)
            Text("FoldWise Voice")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(palette.secondary)
            Spacer()
        }
        .frame(height: 38)
        .background(palette.sidebar)
    }
}

private struct PrototypeSidebar: View {
    let compact: Bool
    let palette: Palette

    private let panes = [
        ("Home", "house"),
        ("Modes", "sparkles"),
        ("Models", "shippingbox"),
        ("History", "clock"),
        ("Stats", "chart.bar"),
        ("Settings", "slider.horizontal.3"),
    ]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(panes, id: \.0) { pane in
                let selected = pane.0 == "Stats"
                HStack(spacing: 9) {
                    Image(systemName: pane.1)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 18)
                        .foregroundStyle(
                            selected ? palette.accent : palette.tertiary
                        )
                    if !compact {
                        Text(pane.0)
                            .font(.system(
                                size: 12,
                                weight: selected ? .semibold : .regular
                            ))
                            .foregroundStyle(
                                selected ? palette.text : palette.secondary
                            )
                        Spacer()
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(palette.accent)
                        }
                    }
                }
                .padding(.horizontal, compact ? 5 : 9)
                .frame(width: compact ? 36 : 174, height: 36)
                .background(
                    selected ? palette.raised : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .overlay(alignment: .leading) {
                    if selected {
                        Rectangle()
                            .fill(palette.accent)
                            .frame(width: 2, height: 22)
                    }
                }
            }
            Spacer()
            if !compact {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Up to date", systemImage: "checkmark.circle.fill")
                    Text("v0.15.0")
                        .foregroundStyle(palette.tertiary)
                }
                .font(.system(size: 10.5))
                .foregroundStyle(palette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(width: compact ? 52 : 190)
        .background(palette.sidebar)
    }
}

private struct StatsCanvas: View {
    let variant: StatsVariant
    let scenario: Scenario
    let interaction: InteractionPreview
    let contrast: ContrastPreview
    let motion: MotionPreview
    let palette: Palette

    @State private var showHistoryStub = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Stats")
                            .font(.system(size: 30, weight: .semibold))
                            .tracking(-0.5)
                            .foregroundStyle(palette.text)
                        Text("A look at how you dictate, drawn from the history you already keep.")
                            .font(.system(size: 12))
                            .foregroundStyle(palette.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(variant.key) — \(variant.title)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(0.6)
                            .foregroundStyle(palette.accent)
                        Text(variant.thesis)
                            .font(.system(size: 10.5))
                            .foregroundStyle(palette.tertiary)
                            .lineLimit(1)
                    }
                }

                if scenario == .savingOff {
                    StatsNotice(
                        symbol: "pause.circle",
                        message: "Saving is off — Stats won’t include new Dictation sessions.",
                        actionTitle: "Open History",
                        palette: palette,
                        contrast: contrast
                    ) {
                        showHistoryStub = true
                    }
                } else if scenario == .empty {
                    StatsNotice(
                        symbol: "sparkles",
                        message: "No stats yet — activity appears after your first saved Dictation session.",
                        palette: palette,
                        contrast: contrast
                    )
                }

                MetricStrip(
                    variant: variant,
                    metrics: metrics(for: scenario),
                    contrast: contrast,
                    palette: palette
                )
                CalendarPanel(
                    variant: variant,
                    days: days(for: scenario),
                    interaction: interaction,
                    contrast: contrast,
                    motion: motion,
                    palette: palette
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 88)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(palette.canvas)
        .alert("Prototype navigation", isPresented: $showHistoryStub) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("In production, Open History changes the destination in place.")
        }
    }
}

private struct StatsNotice: View {
    let symbol: String
    let message: String
    var actionTitle: String?
    let palette: Palette
    let contrast: ContrastPreview
    var action: (() -> Void)?

    init(
        symbol: String,
        message: String,
        actionTitle: String? = nil,
        palette: Palette,
        contrast: ContrastPreview,
        action: (() -> Void)? = nil
    ) {
        self.symbol = symbol
        self.message = message
        self.actionTitle = actionTitle
        self.palette = palette
        self.contrast = contrast
        self.action = action
    }

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(palette.accent)
                .frame(width: contrast == .increased ? 3 : 2, height: 22)
                .accessibilityHidden(true)
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Text(message)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(palette.secondary)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(palette.raised, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 42)
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

private struct MetricStrip: View {
    let variant: StatsVariant
    let metrics: [Metric]
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        switch variant {
        case .tiles:
            HStack(spacing: 10) {
                ForEach(metrics) { metric in
                    TileMetric(
                        metric: metric,
                        contrast: contrast,
                        palette: palette
                    )
                }
            }
        case .rail:
            HStack(spacing: 0) {
                ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                    RailMetric(metric: metric, palette: palette)
                    if index < metrics.count - 1 {
                        Rectangle()
                            .fill(
                                contrast == .increased
                                    ? palette.borderStrong
                                    : palette.border
                            )
                            .frame(width: contrast == .increased ? 2 : 1)
                            .padding(.vertical, 12)
                    }
                }
            }
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        contrast == .increased ? palette.borderStrong : palette.border,
                        lineWidth: contrast == .increased ? 2 : 1
                    )
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(palette.accent)
                    .frame(height: contrast == .increased ? 3 : 2)
                    .padding(.horizontal, 14)
            }
        case .pulse:
            HStack(spacing: 14) {
                ForEach(metrics) { metric in
                    PulseMetric(metric: metric, palette: palette)
                }
            }
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(
                        contrast == .increased
                            ? palette.borderStrong
                            : palette.border
                    )
                    .frame(height: contrast == .increased ? 2 : 1)
            }
        }
    }
}

private struct TileMetric: View {
    let metric: Metric
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: metric.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.accent)
                Spacer()
                Rectangle()
                    .fill(palette.accent)
                    .frame(width: 18, height: 2)
            }
            Text(metric.value)
                .font(.system(
                    size: metric.title == "Time saved" ? 16.5 : 21,
                    weight: .semibold
                ))
                .monospacedDigit()
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(metric.title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
            Text(metric.detail)
                .font(.system(size: 9.5))
                .foregroundStyle(palette.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 91, alignment: .leading)
        .padding(13)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    contrast == .increased ? palette.borderStrong : palette.border,
                    lineWidth: contrast == .increased ? 2 : 1
                )
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RailMetric: View {
    let metric: Metric
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: metric.symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(palette.accent)
                Text(metric.title.uppercased())
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(palette.tertiary)
                    .lineLimit(1)
            }
            Text(metric.value)
                .font(.system(
                    size: metric.title == "Time saved" ? 17 : 22,
                    weight: .semibold,
                    design: .rounded
                ))
                .monospacedDigit()
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(metric.detail)
                .font(.system(size: 9.5))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}

private struct PulseMetric: View {
    let metric: Metric
    let palette: Palette

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: metric.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 17)
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                Text(metric.value)
                    .font(.system(
                        size: metric.title == "Time saved" ? 13 : 15,
                        weight: .semibold,
                        design: .monospaced
                    ))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct CalendarPanel: View {
    let variant: StatsVariant
    let days: [ActivityDay]
    let interaction: InteractionPreview
    let contrast: ContrastPreview
    let motion: MotionPreview
    let palette: Palette

    @State private var hoveredDay: Int?
    @State private var rovingDay = 22
    @FocusState private var focusedDay: Int?

    private var totalWords: Int {
        days.reduce(0) { $0 + $1.words }
    }

    private var activeDays: Int {
        days.filter { $0.sessions > 0 }.count
    }

    private var forcedDay: Int? {
        switch interaction {
        case .neutral: nil
        case .hover: 12
        case .focus: 16
        }
    }

    private var detailDay: ActivityDay? {
        let selected = focusedDay ?? hoveredDay ?? forcedDay
        return days.first { $0.day == selected && !$0.isFuture }
    }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 15) {
            CalendarHeader(
                totalWords: totalWords,
                activeDays: activeDays,
                variant: variant,
                palette: palette
            )
            calendarGrid
            DayDetailShelf(
                day: detailDay,
                variant: variant,
                motion: motion,
                palette: palette
            )
            IntensityLegend(variant: variant, palette: palette)
        }

        switch variant {
        case .tiles:
            content
                .padding(18)
                .background(
                    palette.surface,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(borderColor, lineWidth: borderWidth)
                }
        case .rail:
            content
                .padding(.vertical, 16)
                .overlay(alignment: .top) {
                    Rectangle().fill(borderColor).frame(height: borderWidth)
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(borderColor).frame(height: borderWidth)
                }
        case .pulse:
            content
                .padding(18)
                .padding(.leading, 4)
                .background(
                    palette.surface,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(borderColor, lineWidth: borderWidth)
                }
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(palette.accent)
                        .frame(width: contrast == .increased ? 3 : 2)
                        .padding(.vertical, 12)
                }
        }
    }

    private var borderColor: Color {
        contrast == .increased ? palette.borderStrong : palette.border
    }

    private var borderWidth: CGFloat {
        contrast == .increased ? 2 : 1
    }

    private var calendarGrid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 8),
                count: 7
            ),
            spacing: 8
        ) {
            ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) {
                Text($0)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(palette.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
            }
            ForEach(0 ..< 3, id: \.self) { _ in
                Color.clear
                    .frame(height: variant == .pulse ? 45 : 49)
                    .accessibilityHidden(true)
            }
            ForEach(days) { day in
                CalendarDayCell(
                    day: day,
                    variant: variant,
                    isForcedHover: interaction == .hover && day.day == 12,
                    isFocused: focusedDay == day.day
                        || (interaction == .focus && day.day == 16),
                    canFocus: !day.isFuture && day.day == rovingDay,
                    contrast: contrast,
                    motion: motion,
                    palette: palette,
                    onHover: { hovering in
                        guard !day.isFuture else { return }
                        if hovering {
                            hoveredDay = day.day
                        } else if hoveredDay == day.day {
                            hoveredDay = nil
                        }
                    },
                    onMove: moveFocus
                )
                .focused($focusedDay, equals: day.day)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("July 2026 activity calendar")
        .accessibilityValue(
            "\(totalWords.formatted()) spoken words, \(activeDays.formatted()) active days"
        )
        .onChange(of: days.map(\.words)) { _, _ in
            hoveredDay = nil
            focusedDay = nil
            rovingDay = 22
        }
    }

    private func moveFocus(_ offset: Int) {
        let next = max(1, min(22, rovingDay + offset))
        guard next != rovingDay else { return }
        rovingDay = next
        focusedDay = next
    }
}

private struct CalendarHeader: View {
    let totalWords: Int
    let activeDays: Int
    let variant: StatsVariant
    let palette: Palette

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                if variant == .rail {
                    Text("CURRENT MONTH")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(palette.accent)
                } else {
                    Text("This month")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.text)
                }
                Text("July 2026")
                    .font(.system(
                        size: variant == .rail ? 16 : 11.5,
                        weight: variant == .rail ? .semibold : .regular
                    ))
                    .foregroundStyle(
                        variant == .rail ? palette.text : palette.tertiary
                    )
            }
            Spacer()
            HStack(spacing: 14) {
                HeaderDatum(
                    value: totalWords.formatted(),
                    label: "spoken words",
                    palette: palette
                )
                HeaderDatum(
                    value: activeDays.formatted(),
                    label: activeDays == 1 ? "active day" : "active days",
                    palette: palette
                )
            }
        }
        .accessibilityHidden(true)
    }
}

private struct HeaderDatum: View {
    let value: String
    let label: String
    let palette: Palette

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.text)
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(palette.tertiary)
        }
    }
}

private struct CalendarDayCell: View {
    let day: ActivityDay
    let variant: StatsVariant
    let isForcedHover: Bool
    let isFocused: Bool
    let canFocus: Bool
    let contrast: ContrastPreview
    let motion: MotionPreview
    let palette: Palette
    let onHover: (Bool) -> Void
    let onMove: (Int) -> Void

    private var activityLabel: String {
        if day.hasActivity {
            return day.words.formatted(.number.notation(.compactName))
        }
        return day.isFuture ? "" : "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(day.day.formatted())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                Spacer(minLength: 2)
                if day.isToday {
                    Circle()
                        .fill(palette.accent)
                        .frame(width: 4, height: 4)
                        .accessibilityHidden(true)
                }
            }
            Spacer(minLength: 1)
            switch variant {
            case .tiles:
                Text(activityLabel)
                    .font(.system(size: 8.8, weight: .medium, design: .monospaced))
            case .rail:
                Text(activityLabel)
                    .font(.system(
                        size: 8.5,
                        weight: .medium,
                        design: .monospaced
                    ))
            case .pulse:
                WaveformCue(level: day.level, palette: palette)
            }
        }
        .foregroundStyle(foregroundColor)
        .padding(variant == .pulse ? 7 : 8)
        .frame(
            maxWidth: .infinity,
            minHeight: variant == .pulse ? 45 : 49,
            alignment: .topLeading
        )
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(outlineColor, lineWidth: outlineWidth)
        }
        .overlay(alignment: .bottom) {
            if variant == .rail, day.hasActivity, !day.isFuture {
                Rectangle()
                    .fill(palette.accent)
                    .frame(height: max(1, CGFloat(day.level) * 0.65))
                    .padding(.horizontal, 4)
            }
        }
        .contentShape(Rectangle())
        .focusable(canFocus)
        .focusEffectDisabled()
        .onHover(perform: onHover)
        .onMoveCommand { direction in
            guard isFocused else { return }
            switch direction {
            case .left: onMove(-1)
            case .right: onMove(1)
            case .up: onMove(-7)
            case .down: onMove(7)
            default: break
            }
        }
        .animation(
            motion == .reduced ? nil : .easeOut(duration: 0.16),
            value: isFocused || isForcedHover
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.isToday ? "\(day.fullDate), today" : day.fullDate)
        .accessibilityValue(day.accessibilityValue)
        .accessibilityHidden(day.isFuture)
    }

    private var foregroundColor: Color {
        if day.isFuture {
            return palette.tertiary.opacity(0.45)
        }
        return palette.secondary
    }

    private var backgroundColor: Color {
        if isFocused || isForcedHover {
            return palette.hover
        }
        if day.isFuture {
            return Color.clear
        }
        switch variant {
        case .tiles:
            return day.level == 0
                ? palette.raised.opacity(0.7)
                : palette.accent.opacity([0, 0.10, 0.16, 0.23, 0.32, 0.42][day.level])
        case .rail:
            return palette.surface
        case .pulse:
            return palette.raised.opacity(day.level == 0 ? 0.48 : 0.88)
        }
    }

    private var outlineColor: Color {
        if isFocused {
            return palette.accent
        }
        if isForcedHover {
            return palette.accentHover
        }
        if day.isToday {
            return contrast == .increased ? palette.borderStrong : palette.tertiary
        }
        if contrast == .increased, !day.isFuture {
            return palette.borderStrong
        }
        return variant == .rail && !day.isFuture ? palette.border : .clear
    }

    private var outlineWidth: CGFloat {
        if isFocused {
            return 2
        }
        if contrast == .increased, !day.isFuture {
            return 2
        }
        return 1
    }
}

private struct WaveformCue: View {
    let level: Int
    let palette: Palette

    var body: some View {
        if level == 0 {
            Text("—")
                .font(.system(size: 8.5, design: .monospaced))
        } else {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0 ..< 5, id: \.self) { index in
                    Capsule()
                        .fill(index < level ? palette.accent : palette.border)
                        .frame(
                            width: 2.5,
                            height: [5, 9, 13, 8, 11][index]
                        )
                }
            }
            .frame(height: 13, alignment: .bottomLeading)
            .accessibilityHidden(true)
        }
    }
}

private struct DayDetailShelf: View {
    let day: ActivityDay?
    let variant: StatsVariant
    let motion: MotionPreview
    let palette: Palette

    var body: some View {
        Group {
            if let day {
                HStack(spacing: 12) {
                    if variant == .pulse {
                        WaveformCue(level: day.level, palette: palette)
                            .frame(width: 22)
                    } else {
                        Image(systemName: day.hasActivity ? "waveform" : "minus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(
                                day.hasActivity ? palette.accent : palette.tertiary
                            )
                            .frame(width: 18)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(day.fullDate)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(palette.text)
                        if day.hasActivity {
                            Text(
                                "\(day.words.formatted()) spoken words across \(day.sessions) saved "
                                    + (day.sessions == 1 ? "session" : "sessions")
                            )
                            .font(.system(size: 10.5))
                            .foregroundStyle(palette.secondary)
                            Text(day.day == 12
                                ? "Timing unavailable"
                                : "About \(max(1, day.words / 82)) min saved")
                                .font(.system(size: 10))
                                .foregroundStyle(palette.tertiary)
                        } else {
                            Text("No saved Dictation sessions")
                                .font(.system(size: 10.5))
                                .foregroundStyle(palette.secondary)
                        }
                    }
                }
            } else {
                Label(
                    "Hover a past day, or Tab into the calendar and use the arrow keys.",
                    systemImage: "cursorarrow.motionlines"
                )
                .font(.system(size: 10.5))
                .foregroundStyle(palette.tertiary)
            }
        }
        .id(day?.day ?? 0)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(palette.raised, in: RoundedRectangle(cornerRadius: 6))
        .animation(
            motion == .reduced ? nil : .easeOut(duration: 0.16),
            value: day?.day
        )
        .accessibilityHidden(true)
    }
}

private struct IntensityLegend: View {
    let variant: StatsVariant
    let palette: Palette

    private let items = [
        ("None", 0),
        ("1–249", 1),
        ("250–599", 2),
        ("600–999", 3),
        ("1,000–1,599", 4),
        ("1,600+", 5),
    ]

    var body: some View {
        HStack(spacing: 10) {
            Text("Daily spoken words")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.secondary)
            Spacer(minLength: 4)
            ForEach(items, id: \.0) { item in
                HStack(spacing: 4) {
                    legendMark(level: item.1)
                    Text(item.0)
                        .font(.system(size: 8.3, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private func legendMark(level: Int) -> some View {
        switch variant {
        case .tiles:
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    level == 0
                        ? palette.raised
                        : palette.accent.opacity([0, 0.28, 0.42, 0.58, 0.76, 1][level])
                )
                .frame(width: 12, height: 12)
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(palette.border, lineWidth: level == 0 ? 1 : 0)
                }
        case .rail:
            VStack {
                Spacer()
                Rectangle()
                    .fill(level == 0 ? palette.border : palette.accent)
                    .frame(height: max(1, CGFloat(level) * 0.7))
            }
            .frame(width: 14, height: 12)
        case .pulse:
            WaveformCue(level: level, palette: palette)
                .frame(width: 16, height: 13)
        }
    }
}

private struct ReviewBar: View {
    @Binding var variant: StatsVariant
    @Binding var scenario: Scenario
    @Binding var appearance: PreviewAppearance
    @Binding var preset: WindowPreset
    @Binding var interaction: InteractionPreview
    @Binding var contrast: ContrastPreview
    @Binding var motion: MotionPreview

    var body: some View {
        HStack(spacing: 8) {
            Button { cycle(-1) } label: {
                Image(systemName: "chevron.left")
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command])
            Text("\(variant.key) — \(variant.title)")
                .font(.system(size: 11, weight: .semibold))
                .frame(minWidth: 118)
            Button { cycle(1) } label: {
                Image(systemName: "chevron.right")
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command])
            Divider().frame(height: 18)
            compactPicker("State", selection: $scenario)
            compactPicker("Appearance", selection: $appearance)
            compactPicker("Window", selection: $preset)
                .onChange(of: preset) { _, next in resize(to: next) }
            compactPicker("Interaction", selection: $interaction)
            compactPicker("Contrast", selection: $contrast)
            compactPicker("Motion", selection: $motion)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 5)
    }

    private func compactPicker<Value: Hashable & CaseIterable & Identifiable>(
        _ label: String,
        selection: Binding<Value>
    ) -> some View where Value.AllCases: RandomAccessCollection, Value.ID == String {
        Picker(label, selection: selection) {
            ForEach(Value.allCases) { item in
                Text(String(describing: item.id)).tag(item)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 96)
    }

    private func cycle(_ offset: Int) {
        let variants = StatsVariant.allCases
        guard let index = variants.firstIndex(of: variant) else { return }
        variant = variants[(index + offset + variants.count) % variants.count]
    }

    private func resize(to preset: WindowPreset) {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
        window.setContentSize(preset.size)
        window.center()
    }
}

private struct Hairline: View {
    let color: Color
    let width: CGFloat
    var vertical = false

    var body: some View {
        color.frame(
            width: vertical ? width : nil,
            height: vertical ? nil : width
        )
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
