// THROWAWAY PROTOTYPE — visual decision aid for Wayfinder ticket
// "Prototype the monthly Stats hierarchy in the FoldWise theme".
//
// Three native variants of the existing Stats pane, switchable from the
// bottom review bar. The production hierarchy is fixed: four headline metrics
// above one full-width Monthly activity calendar. The prototype varies only
// the visual structure used to express that hierarchy.

import AppKit
import SwiftUI

private enum PrototypeVariant: String, CaseIterable, Identifiable {
    case ledger = "A"
    case rhythm = "B"
    case tiles = "C"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .ledger: "Quiet ledger"
        case .rhythm: "Week rhythm"
        case .tiles: "Activity tiles"
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

private enum WindowPreset: String, CaseIterable, Identifiable {
    case compact = "880 × 640"
    case standard = "980 × 720"
    case wide = "1180 × 760"

    var id: String {
        rawValue
    }

    var size: NSSize {
        switch self {
        case .compact: NSSize(width: 880, height: 640)
        case .standard: NSSize(width: 980, height: 720)
        case .wide: NSSize(width: 1180, height: 760)
        }
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

    var id: Int {
        day
    }

    /// Illustrative only. The production thresholds are a later decision.
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
}

private let metrics = [
    Metric(
        title: "Words dictated", value: "18,642", detail: "from saved history",
        symbol: "quote.bubble"
    ),
    Metric(
        title: "Speaking speed", value: "137 wpm", detail: "pauses included",
        symbol: "waveform"
    ),
    Metric(
        title: "Current streak", value: "6 days", detail: "best: 14 days",
        symbol: "flame"
    ),
    Metric(
        title: "Time saved", value: "~1 hr 22 min", detail: "versus 40 wpm typing",
        symbol: "clock.arrow.circlepath"
    ),
]

private let activityWords = [
    0, 540, 1210, 320, 0, 0, 840,
    1560, 980, 0, 440, 1910, 710, 0,
    210, 680, 1310, 1720, 0, 360, 790,
    1100, 1450, 620, 0, 940, 1830, 520,
    760, 1280, 430,
]

private let activityDays = activityWords.enumerated().map {
    ActivityDay(day: $0.offset + 1, words: $0.element)
}

@main
private enum StatsHierarchyPrototypeApp {
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
            .appendingPathComponent(".context/stats-prototype-shots", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: output,
            withIntermediateDirectories: true
        )

        for appearance in PrototypeAppearance.allCases {
            for variant in PrototypeVariant.allCases {
                let root = PrototypeRoot(
                    initialVariant: variant,
                    initialAppearance: appearance,
                    initialPreset: .compact
                )
                .frame(width: 880, height: 640)
                let hosting = NSHostingView(rootView: root)
                hosting.frame = NSRect(origin: .zero, size: WindowPreset.compact.size)
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
                guard
                    let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
                else { continue }
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else {
                    continue
                }
                let name = "\(variant.rawValue.lowercased())-\(appearance.rawValue.lowercased()).png"
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
        let content = PrototypeRoot()
        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hosting)
        window.title = "FoldWise Stats hierarchy prototype"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.setContentSize(WindowPreset.standard.size)
        window.contentMinSize = WindowPreset.compact.size
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
    @State private var variant = PrototypeVariant.ledger
    @State private var appearance = PrototypeAppearance.light
    @State private var preset = WindowPreset.standard

    init(
        initialVariant: PrototypeVariant = .ledger,
        initialAppearance: PrototypeAppearance = .light,
        initialPreset: WindowPreset = .standard
    ) {
        _variant = State(initialValue: initialVariant)
        _appearance = State(initialValue: initialAppearance)
        _preset = State(initialValue: initialPreset)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                AppTitlebar()
                Rectangle().fill(Theme.hairline).frame(height: 1)
                HStack(spacing: 0) {
                    Sidebar(compact: geometry.size.width < 940)
                    Rectangle().fill(Theme.hairline).frame(width: 1)
                    StatsCanvas(variant: variant)
                }
            }
            .background(Theme.windowBackground)
            .overlay(alignment: .bottom) {
                ReviewBar(
                    variant: $variant,
                    appearance: $appearance,
                    preset: $preset
                )
                .padding(.bottom, 12)
            }
        }
        .preferredColorScheme(appearance.scheme)
        .frame(minWidth: 880, minHeight: 640)
    }
}

private struct AppTitlebar: View {
    var body: some View {
        HStack(spacing: 12) {
            Spacer().frame(width: 70)
            RoundedRectangle(cornerRadius: 4.5)
                .strokeBorder(Theme.textFaint, lineWidth: 1.5)
                .frame(width: 21, height: 16)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Theme.textFaint)
                        .frame(width: 1.5)
                        .padding(.vertical, 1.5)
                        .offset(x: 6)
                }
            Text("FoldWise Voice")
                .font(Theme.ui(12.5, .semibold))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
        }
        .frame(height: 38)
        .background(Theme.sidebarBackground)
    }
}

private struct Sidebar: View {
    let compact: Bool

    private let items: [(String, String)] = [
        ("Home", "house"),
        ("Modes", "sparkles"),
        ("Models", "shippingbox"),
        ("History", "clock"),
        ("Stats", "chart.bar"),
        ("Settings", "slider.horizontal.3"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sidebarRowSpacing) {
            ForEach(items, id: \.0) { item in
                let active = item.0 == "Stats"
                HStack(spacing: 10) {
                    Image(systemName: item.1)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(active ? Theme.accent : Theme.textTertiary)
                        .frame(width: compact ? Theme.sidebarRowHeight : 18)
                    if !compact {
                        Text(item.0)
                            .font(active ? Theme.navActive : Theme.nav)
                            .foregroundStyle(
                                active ? Theme.textPrimary : Theme.textSecondary
                            )
                        Spacer()
                    }
                }
                .padding(.horizontal, compact ? 0 : 9)
                .frame(
                    width: compact ? Theme.sidebarRowHeight : nil,
                    height: Theme.sidebarRowHeight
                )
                .background(
                    active ? Theme.activeNavBackground : Color.clear,
                    in: RoundedRectangle(
                        cornerRadius: compact ? Theme.railTileRadius : Theme.navRadius
                    )
                )
                .shadow(color: active ? Theme.activeNavShadow : .clear, radius: 3, y: 1)
            }
            Spacer()
            if !compact {
                Text("v0.1.0")
                    .font(Theme.ui(11))
                    .foregroundStyle(Theme.textFaint)
                    .padding(.horizontal, 11)
                    .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, Theme.sidebarHorizontalInset)
        .padding(.vertical, Theme.sidebarVerticalInset)
        .frame(width: compact ? Theme.railWidth : Theme.sidebarWidth)
        .background(Theme.sidebarBackground)
    }
}

private struct StatsCanvas: View {
    let variant: PrototypeVariant

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Stats")
                        .font(Theme.pageTitle)
                        .kerning(-0.56)
                        .foregroundStyle(Theme.textPrimary)
                    Text("A look at how you dictate, drawn from the history you already keep.")
                        .font(Theme.ui(12))
                        .foregroundStyle(Theme.textSecondary)
                }

                metricStrip
                calendarCard

                Text("Sample activity levels are illustrative for hierarchy review only.")
                    .font(Theme.ui(10.5))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, Theme.contentPadding)
            .padding(.top, Theme.contentPadding)
            .padding(.bottom, 86)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var metricStrip: some View {
        switch variant {
        case .ledger:
            LedgerMetrics()
        case .rhythm:
            RhythmMetrics()
        case .tiles:
            TileMetrics()
        }
    }

    @ViewBuilder
    private var calendarCard: some View {
        switch variant {
        case .ledger:
            CalendarContainer(titleStyle: .quiet) { LedgerCalendar() }
        case .rhythm:
            CalendarContainer(titleStyle: .accent) { RhythmCalendar() }
        case .tiles:
            CalendarContainer(titleStyle: .measured) { TileCalendar() }
        }
    }
}

private struct LedgerMetrics: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                VStack(alignment: .leading, spacing: 6) {
                    Text(metric.title.uppercased())
                        .font(Theme.ui(10, .bold))
                        .tracking(0.7)
                        .foregroundStyle(Theme.textTertiary)
                    Text(metric.value)
                        .font(Theme.ui(index == 3 ? 19 : 23, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    Text(metric.detail)
                        .font(Theme.ui(10.5))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(15)
                if index < metrics.count - 1 {
                    Rectangle().fill(Theme.hairline).frame(width: 1)
                }
            }
        }
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        }
    }
}

private struct RhythmMetrics: View {
    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: metric.symbol)
                            .foregroundStyle(Theme.accent)
                        Text(metric.title)
                            .font(Theme.ui(11, .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text(metric.value)
                        .font(Theme.ui(index == 3 ? 19 : 24, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 13)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

private struct TileMetrics: View {
    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: metric.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text(metric.value)
                        .font(Theme.ui(index == 3 ? 17 : 22, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    Text(metric.title)
                        .font(Theme.ui(10.5, .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
                .padding(13)
                .background(
                    Theme.cardBackground,
                    in: RoundedRectangle(cornerRadius: Theme.cardRadius)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cardRadius)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                }
            }
        }
    }
}

private enum CalendarTitleStyle {
    case quiet
    case accent
    case measured
}

private struct CalendarContainer<Content: View>: View {
    let titleStyle: CalendarTitleStyle
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("This month")
                        .font(Theme.ui(16, .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("July 2026")
                        .font(Theme.ui(11.5))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                monthSummary
            }
            content()
        }
        .padding(18)
        .background(
            titleStyle == .accent ? Theme.sidebarBackground.opacity(0.72) : Theme.cardBackground,
            in: RoundedRectangle(cornerRadius: Theme.cardRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var monthSummary: some View {
        switch titleStyle {
        case .quiet:
            HStack(spacing: 16) {
                summary(label: "Active days", value: "25")
                summary(label: "Words", value: "18,642")
            }
        case .accent:
            HStack(spacing: 8) {
                Text("25 active days")
                Text("·").foregroundStyle(Theme.textFaint)
                Text("18,642 words")
            }
            .font(Theme.ui(11.5, .semibold))
            .foregroundStyle(Theme.accent)
        case .measured:
            VStack(alignment: .trailing, spacing: 2) {
                Text("18,642 words")
                    .font(Theme.ui(13, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("25 active days")
                    .font(Theme.ui(10.5))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func summary(label: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(Theme.ui(13, .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(Theme.ui(10))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

private let weekdayLabels = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
private let calendarColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

private struct LedgerCalendar: View {
    var body: some View {
        LazyVGrid(columns: calendarColumns, spacing: 8) {
            weekdayHeader
            ForEach(0 ..< 2, id: \.self) { _ in Color.clear.frame(height: 50) }
            ForEach(activityDays) { day in
                Button {} label: {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(day.day.formatted())
                            .font(Theme.mono(10.5, .semibold))
                            .foregroundStyle(Theme.textSecondary)
                        Capsule()
                            .fill(activityColor(day.level))
                            .frame(height: 8)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
                    .background(
                        day.level == 0 ? Theme.windowBackground.opacity(0.5) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                }
                .buttonStyle(.plain)
                .help(day.words == 0 ? "No activity" : "\(day.words.formatted()) words")
            }
        }
    }
}

private struct RhythmCalendar: View {
    private let weeks: [[ActivityDay?]] = {
        var cells: [ActivityDay?] = [nil, nil] + activityDays.map(Optional.some)
        while !cells.count.isMultiple(of: 7) {
            cells.append(nil)
        }
        return stride(from: 0, to: cells.count, by: 7).map {
            Array(cells[$0 ..< min($0 + 7, cells.count)])
        }
    }()

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Color.clear.frame(width: 22)
                weekdayHeader
            }
            ForEach(Array(weeks.enumerated()), id: \.offset) { weekIndex, week in
                HStack(spacing: 8) {
                    Text("W\(weekIndex + 1)")
                        .font(Theme.mono(9, .semibold))
                        .foregroundStyle(Theme.textFaint)
                        .frame(width: 22, alignment: .leading)
                    ForEach(0 ..< week.count, id: \.self) { index in
                        if let day = week[index] {
                            Button {} label: {
                                HStack(spacing: 7) {
                                    Text(day.day.formatted())
                                        .font(Theme.mono(10, .semibold))
                                        .foregroundStyle(Theme.textSecondary)
                                    Capsule()
                                        .fill(activityColor(day.level))
                                        .frame(maxWidth: .infinity, maxHeight: 7)
                                }
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, minHeight: 34)
                            }
                            .buttonStyle(.plain)
                            .background(
                                Theme.windowBackground.opacity(0.56),
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                            .help(day.words == 0 ? "No activity" : "\(day.words.formatted()) words")
                        } else {
                            Color.clear.frame(maxWidth: .infinity, minHeight: 34)
                        }
                    }
                }
            }
        }
    }
}

private struct TileCalendar: View {
    var body: some View {
        LazyVGrid(columns: calendarColumns, spacing: 8) {
            weekdayHeader
            ForEach(0 ..< 2, id: \.self) { _ in Color.clear.frame(height: 48) }
            ForEach(activityDays) { day in
                Button {} label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(day.day.formatted())
                            .font(Theme.mono(10, .semibold))
                        Spacer(minLength: 1)
                        if day.words > 0 {
                            Text(compactWords(day.words))
                                .font(Theme.mono(9, .medium))
                                .monospacedDigit()
                        } else {
                            Text("—").font(Theme.mono(9))
                        }
                    }
                    .foregroundStyle(day.level >= 4 ? Color.white : Theme.textSecondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
                    .background(
                        day.level == 0 ? Theme.windowBackground.opacity(0.55) : activityColor(day.level),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                }
                .buttonStyle(.plain)
                .help(day.words == 0 ? "No activity" : "\(day.words.formatted()) words")
            }
        }
    }

    private func compactWords(_ words: Int) -> String {
        words >= 1000
            ? String(format: "%.1fk", Double(words) / 1000)
            : words.formatted()
    }
}

private var weekdayHeader: some View {
    ForEach(weekdayLabels, id: \.self) { weekday in
        Text(weekday)
            .font(Theme.ui(9, .bold))
            .tracking(0.65)
            .foregroundStyle(Theme.textFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func activityColor(_ level: Int) -> Color {
    guard level > 0 else { return Theme.hairline }
    return Theme.accent.opacity([0, 0.20, 0.36, 0.55, 0.76, 0.96][level])
}

private struct ReviewBar: View {
    @Binding var variant: PrototypeVariant
    @Binding var appearance: PrototypeAppearance
    @Binding var preset: WindowPreset

    var body: some View {
        HStack(spacing: 10) {
            Button { cycle(-1) } label: {
                Image(systemName: "chevron.left")
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .help("Previous treatment")

            Text("\(variant.rawValue) — \(variant.title)")
                .font(Theme.ui(11.5, .semibold))
                .frame(minWidth: 118)

            Button { cycle(1) } label: {
                Image(systemName: "chevron.right")
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .help("Next treatment")

            Divider().frame(height: 18)

            Picker("Appearance", selection: $appearance) {
                ForEach(PrototypeAppearance.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 112)

            Picker("Window", selection: $preset) {
                ForEach(WindowPreset.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .labelsHidden()
            .frame(width: 118)
            .onChange(of: preset) { _, next in resize(to: next) }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.tooltipText)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Theme.tooltipBackground,
            in: RoundedRectangle(cornerRadius: 11)
        )
        .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
    }

    private func cycle(_ offset: Int) {
        let variants = PrototypeVariant.allCases
        guard let index = variants.firstIndex(of: variant) else { return }
        variant = variants[(index + offset + variants.count) % variants.count]
    }

    private func resize(to preset: WindowPreset) {
        guard let window = NSApp.keyWindow else { return }
        let oldFrame = window.frame
        let nextFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: preset.size))
        let origin = NSPoint(
            x: oldFrame.midX - nextFrame.width / 2,
            y: oldFrame.midY - nextFrame.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: nextFrame.size), display: true, animate: true)
    }
}
