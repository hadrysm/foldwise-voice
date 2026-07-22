// THROWAWAY PROTOTYPE — interaction decision aid for Wayfinder ticket
// "Prototype resolved calendar states and interactions".
//
// One approved native Stats layout with four representative data states,
// switchable from the bottom review bar. This is intentionally not production
// code: it makes the resolved intensity, detail, compact, accessibility, and
// motion decisions concrete enough to review together.

import AppKit
import SwiftUI

private enum PrototypeScenario: String, CaseIterable, Identifiable {
    case activity
    case noHistory = "no-history"
    case savingOff = "saving-off"
    case savingOffEmpty = "saving-off-empty"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .activity: "Retained activity"
        case .noHistory: "No history"
        case .savingOff: "Saving off"
        case .savingOffEmpty: "Saving off · empty"
        }
    }

    var hasRetainedHistory: Bool {
        self == .activity || self == .savingOff
    }

    var isSavingOff: Bool {
        self == .savingOff || self == .savingOffEmpty
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

private enum PrototypeMotion: String, CaseIterable, Identifiable {
    case normal = "Motion"
    case reduced = "Reduced"

    var id: String {
        rawValue
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

private enum TimingCoverage {
    case complete(dictatingMinutes: Int, savedMinutes: Int)
    case partial
    case unavailable
}

private struct ActivityDay: Identifiable {
    let day: Int
    let words: Int
    let sessions: Int
    let timing: TimingCoverage

    var id: Int {
        day
    }

    var isToday: Bool {
        day == prototypeTodayDay
    }

    var isFuture: Bool {
        day > prototypeTodayDay
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

    var activityLine: String {
        let sessionText = sessions == 1 ? "1 session" : "\(sessions.formatted()) sessions"
        return "\(words.formatted()) spoken words across \(sessionText)"
    }

    var timingLine: String {
        switch timing {
        case let .complete(dictatingMinutes, savedMinutes):
            "\(minuteText(dictatingMinutes)) dictating · about \(minuteText(savedMinutes)) saved"
        case .partial:
            "Timing unavailable for some sessions"
        case .unavailable:
            "Timing unavailable"
        }
    }

    var accessibilityLabel: String {
        isToday ? "\(fullDate), today" : fullDate
    }

    var accessibilityValue: String {
        if !hasActivity {
            return "No dictated words. No saved Dictation sessions"
        }
        return "\(activityLine). \(timingLine)"
    }
}

private let prototypeCalendar: Calendar = {
    var calendar = Calendar.autoupdatingCurrent
    calendar.timeZone = .autoupdatingCurrent
    return calendar
}()

private let prototypeMonthStart: Date = prototypeCalendar
    .date(from: DateComponents(year: 2026, month: 7, day: 1)) ?? Date()

private let prototypeTodayDay = 22

private let sampleActivityWords = [
    0, 540, 1210, 320, 0, 0, 840,
    1560, 980, 0, 440, 1910, 710, 0,
    210, 680, 1310, 1720, 0, 360, 790,
    1100, 0, 0, 0, 0, 0, 0,
    0, 0, 0,
]

private func makeActivityDays(hasRetainedHistory: Bool) -> [ActivityDay] {
    sampleActivityWords.enumerated().map { index, sampleWords in
        let day = index + 1
        let words = hasRetainedHistory && day <= prototypeTodayDay ? sampleWords : 0
        let sessions = words == 0 ? 0 : max(1, min(6, words / 360))
        let timing: TimingCoverage = switch day {
        case 9: .partial
        case 12: .unavailable
        default: .complete(
                dictatingMinutes: max(1, words / 135),
                savedMinutes: max(1, words / 82)
            )
        }
        return ActivityDay(day: day, words: words, sessions: sessions, timing: timing)
    }
}

private func metrics(for scenario: PrototypeScenario) -> [Metric] {
    let hasHistory = scenario.hasRetainedHistory
    return [
        Metric(
            title: "Words dictated", value: hasHistory ? "14,680" : "0",
            detail: "from saved history", symbol: "quote.bubble"
        ),
        Metric(
            title: "Speaking speed", value: hasHistory ? "137 wpm" : "—",
            detail: "pauses included", symbol: "waveform"
        ),
        Metric(
            title: "Current streak", value: hasHistory ? "3 days" : "—",
            detail: "through today", symbol: "flame"
        ),
        Metric(
            title: "Time saved", value: hasHistory ? "~1 hr 04 min" : "—",
            detail: "versus 40 wpm typing", symbol: "clock.arrow.circlepath"
        ),
    ]
}

private func minuteText(_ minutes: Int) -> String {
    minutes == 1 ? "1 min" : "\(minutes.formatted()) min"
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
        if let staleFiles = try? FileManager.default.contentsOfDirectory(
            at: output,
            includingPropertiesForKeys: nil
        ) {
            for file in staleFiles where file.pathExtension == "png" {
                try? FileManager.default.removeItem(at: file)
            }
        }

        for appearance in PrototypeAppearance.allCases {
            for preset in [WindowPreset.compact, .wide] {
                for scenario in PrototypeScenario.allCases {
                    let root = PrototypeRoot(
                        initialScenario: scenario,
                        initialAppearance: appearance,
                        initialPreset: preset,
                        initialMotion: .normal,
                        initialDetailDay: scenario.hasRetainedHistory ? 8 : 9
                    )
                    .frame(width: preset.size.width, height: preset.size.height)
                    let hosting = NSHostingView(rootView: root)
                    hosting.frame = NSRect(origin: .zero, size: preset.size)
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
                    guard let png = bitmap.representation(using: .png, properties: [:]) else {
                        continue
                    }
                    let presetName = preset == .compact ? "compact" : "wide"
                    let name = "\(scenario.rawValue)-\(presetName)-\(appearance.rawValue.lowercased()).png"
                    try? png.write(to: output.appendingPathComponent(name))
                    window.orderOut(nil)
                }
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
        window.title = "FoldWise Stats states prototype"
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
    @State private var scenario: PrototypeScenario
    @State private var appearance: PrototypeAppearance
    @State private var preset: WindowPreset
    @State private var motion: PrototypeMotion
    private let initialDetailDay: Int?

    init(
        initialScenario: PrototypeScenario = .activity,
        initialAppearance: PrototypeAppearance = .light,
        initialPreset: WindowPreset = .standard,
        initialMotion: PrototypeMotion = .normal,
        initialDetailDay: Int? = nil
    ) {
        _scenario = State(initialValue: initialScenario)
        _appearance = State(initialValue: initialAppearance)
        _preset = State(initialValue: initialPreset)
        _motion = State(initialValue: initialMotion)
        self.initialDetailDay = initialDetailDay
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                AppTitlebar()
                Rectangle().fill(Theme.hairline).frame(height: 1)
                HStack(spacing: 0) {
                    Sidebar(compact: geometry.size.width < Theme.homeCompactBreakpoint)
                    Rectangle().fill(Theme.hairline).frame(width: 1)
                    StatsCanvas(
                        scenario: scenario,
                        reduceMotion: motion == .reduced,
                        initialDetailDay: initialDetailDay
                    )
                }
            }
            .background(Theme.windowBackground)
            .overlay(alignment: .bottom) {
                ReviewBar(
                    scenario: $scenario,
                    appearance: $appearance,
                    preset: $preset,
                    motion: $motion
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
                            .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
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
    let scenario: PrototypeScenario
    let reduceMotion: Bool
    let initialDetailDay: Int?

    @State private var showHistoryPrototypeAlert = false

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

                if scenario.isSavingOff {
                    InlineNotice(
                        symbol: "pause.circle",
                        message: "Saving is off — Stats won’t include new dictations. Turn it on in History.",
                        actionTitle: "Open History"
                    ) {
                        showHistoryPrototypeAlert = true
                    }
                } else if !scenario.hasRetainedHistory {
                    InlineNotice(
                        symbol: "sparkles",
                        message: "No stats yet — your activity will appear after your first saved dictation."
                    )
                }

                MetricStrip(metrics: metrics(for: scenario))
                CalendarCard(
                    days: makeActivityDays(hasRetainedHistory: scenario.hasRetainedHistory),
                    reduceMotion: reduceMotion,
                    initialDetailDay: initialDetailDay
                )
            }
            .padding(.horizontal, Theme.contentPadding)
            .padding(.top, Theme.contentPadding)
            .padding(.bottom, 92)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("Prototype navigation", isPresented: $showHistoryPrototypeAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("In production, this action opens History.")
        }
    }
}

private struct InlineNotice: View {
    let symbol: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    init(
        symbol: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.symbol = symbol
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text(message)
                .font(Theme.ui(11.5, .medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderless)
                    .font(Theme.ui(11.5, .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 42)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        }
    }
}

private struct MetricStrip: View {
    let metrics: [Metric]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: metric.symbol)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .accessibilityHidden(true)
                        Spacer()
                    }
                    Text(metric.value)
                        .font(Theme.ui(index == 3 ? 16.5 : 21, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(metric.title)
                        .font(Theme.ui(10.5, .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Text(metric.detail)
                        .font(Theme.ui(9.5))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 91, alignment: .leading)
                .padding(13)
                .background(
                    Theme.cardBackground,
                    in: RoundedRectangle(cornerRadius: Theme.cardRadius)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cardRadius)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct CalendarCard: View {
    let days: [ActivityDay]
    let reduceMotion: Bool

    @State private var hoveredDay: Int?
    @State private var rovingDay = prototypeTodayDay
    @FocusState private var focusedDay: Int?

    init(days: [ActivityDay], reduceMotion: Bool, initialDetailDay: Int? = nil) {
        self.days = days
        self.reduceMotion = reduceMotion
        _hoveredDay = State(initialValue: initialDetailDay)
    }

    private var activeDays: Int {
        days.filter(\.hasActivity).count
    }

    private var totalWords: Int {
        days.reduce(0) { $0 + $1.words }
    }

    private var detailDay: ActivityDay? {
        let dayNumber = focusedDay ?? hoveredDay
        return days.first { $0.day == dayNumber && !$0.isFuture }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("This month")
                        .font(Theme.ui(16, .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(prototypeMonthStart.formatted(.dateTime.month(.wide).year()))
                        .font(Theme.ui(11.5))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(totalWords.formatted()) words")
                        .font(Theme.ui(13, .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(activeDays.formatted()) active days")
                        .font(Theme.ui(10.5))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .accessibilityHidden(true)

            calendarGrid

            DayDetailShelf(day: detailDay, reduceMotion: reduceMotion)
                .accessibilityHidden(true)

            IntensityLegend()
        }
        .padding(18)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        }
        .onChange(of: days.map(\.words)) { _, _ in
            hoveredDay = nil
            focusedDay = nil
            rovingDay = prototypeTodayDay
        }
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: calendarColumns, spacing: 8) {
            weekdayHeader
            ForEach((0 ..< leadingSpacerCount).map { "leading-\($0)" }, id: \.self) { _ in
                Color.clear
                    .frame(height: 49)
                    .accessibilityHidden(true)
            }
            ForEach(days) { day in
                CalendarDayCell(
                    day: day,
                    canFocus: !day.isFuture && day.day == rovingDay,
                    isFocused: focusedDay == day.day,
                    reduceMotion: reduceMotion,
                    onHover: { hovering in
                        guard !day.isFuture else { return }
                        hoveredDay = hovering ? day.day : (hoveredDay == day.day ? nil : hoveredDay)
                    },
                    onMove: moveFocus
                )
                .focused($focusedDay, equals: day.day)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(prototypeMonthStart.formatted(.dateTime.month(.wide).year())) activity calendar"
        )
        .accessibilityValue("\(totalWords.formatted()) words, \(activeDays.formatted()) active days")
    }

    private func moveFocus(_ offset: Int) {
        let next = max(1, min(prototypeTodayDay, rovingDay + offset))
        guard next != rovingDay else { return }
        rovingDay = next
        focusedDay = next
    }
}

private let calendarColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

private let leadingSpacerCount: Int = {
    let weekday = prototypeCalendar.component(.weekday, from: prototypeMonthStart)
    return (weekday - prototypeCalendar.firstWeekday + 7) % 7
}()

private let localizedWeekdays: [String] = {
    let symbols = prototypeCalendar.shortStandaloneWeekdaySymbols
    let start = max(0, prototypeCalendar.firstWeekday - 1)
    let ordered = Array(symbols[start...] + symbols[..<start])
    return ordered.map { $0.capitalized(with: .autoupdatingCurrent) }
}()

private var weekdayHeader: some View {
    ForEach(localizedWeekdays, id: \.self) { weekday in
        Text(weekday)
            .font(Theme.ui(9.5, .semibold))
            .foregroundStyle(Theme.textFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
    }
}

private struct CalendarDayCell: View {
    let day: ActivityDay
    let canFocus: Bool
    let isFocused: Bool
    let reduceMotion: Bool
    let onHover: (Bool) -> Void
    let onMove: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(day.day.formatted())
                .font(Theme.mono(10, .semibold))
            Spacer(minLength: 1)
            if day.hasActivity {
                Text(day.words.formatted(.number.notation(.compactName)))
                    .font(Theme.mono(9, .medium))
                    .monospacedDigit()
            } else if !day.isFuture {
                Text("—")
                    .font(Theme.mono(9))
            }
        }
        .foregroundStyle(foregroundColor)
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 49, alignment: .topLeading)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(outlineColor, lineWidth: isFocused ? 2.5 : 1)
        }
        .shadow(
            color: isFocused ? Theme.accent.opacity(0.24) : .clear,
            radius: isFocused ? 3 : 0
        )
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
            reduceMotion ? nil : .easeOut(duration: 0.14),
            value: isFocused
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.accessibilityLabel)
        .accessibilityValue(day.accessibilityValue)
        .accessibilityHidden(day.isFuture)
    }

    private var foregroundColor: Color {
        if day.isFuture {
            return Theme.textFaint.opacity(0.42)
        }
        return day.level >= 4 ? .white : Theme.textSecondary
    }

    private var backgroundColor: Color {
        if day.isFuture {
            return Theme.windowBackground.opacity(0.28)
        }
        if day.level == 0 {
            return Theme.windowBackground.opacity(0.72)
        }
        return activityColor(day.level)
    }

    private var outlineColor: Color {
        if isFocused {
            return Theme.accent
        }
        if day.isToday {
            return Theme.textTertiary.opacity(0.72)
        }
        return .clear
    }
}

private struct DayDetailShelf: View {
    let day: ActivityDay?
    let reduceMotion: Bool

    var body: some View {
        Group {
            if let day {
                VStack(alignment: .leading, spacing: 3) {
                    Text(day.fullDate)
                        .font(Theme.ui(11.5, .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if day.hasActivity {
                        Text(day.activityLine)
                            .font(Theme.ui(10.5))
                            .foregroundStyle(Theme.textSecondary)
                        Text(day.timingLine)
                            .font(Theme.ui(10.5))
                            .foregroundStyle(Theme.textTertiary)
                    } else {
                        Text("No saved Dictation sessions")
                            .font(Theme.ui(10.5))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "cursorarrow.motionlines")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textFaint)
                    Text("Hover a past day, or Tab into the calendar and use the arrow keys.")
                        .font(Theme.ui(10.5))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .id(day?.day ?? 0)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Theme.windowBackground.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.14),
            value: day?.day
        )
    }
}

private struct IntensityLegend: View {
    private let items: [(String, Int)] = [
        ("None", 0),
        ("1–249", 1),
        ("250–599", 2),
        ("600–999", 3),
        ("1,000–1,599", 4),
        ("1,600+", 5),
    ]

    var body: some View {
        HStack(spacing: 12) {
            Text("Daily spoken words")
                .font(Theme.ui(10, .semibold))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 6)
            ForEach(items, id: \.0) { item in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(item.1 == 0 ? Theme.windowBackground : activityColor(item.1))
                        .frame(width: 13, height: 13)
                        .overlay {
                            RoundedRectangle(cornerRadius: 2.5)
                                .strokeBorder(Theme.hairline, lineWidth: item.1 == 0 ? 1 : 0)
                        }
                        .accessibilityHidden(true)
                    Text(item.0)
                        .font(Theme.mono(8.7, .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
        }
    }
}

private func activityColor(_ level: Int) -> Color {
    guard level > 0 else { return Theme.hairline }
    return Theme.accent.opacity([0, 0.20, 0.36, 0.54, 0.76, 0.96][level])
}

private struct ReviewBar: View {
    @Binding var scenario: PrototypeScenario
    @Binding var appearance: PrototypeAppearance
    @Binding var preset: WindowPreset
    @Binding var motion: PrototypeMotion

    var body: some View {
        HStack(spacing: 10) {
            Button { cycle(-1) } label: {
                Image(systemName: "chevron.left")
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command])
            .help("Previous state (Command–Left Arrow)")

            Text(scenario.title)
                .font(Theme.ui(11.5, .semibold))
                .frame(minWidth: 126)

            Button { cycle(1) } label: {
                Image(systemName: "chevron.right")
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command])
            .help("Next state (Command–Right Arrow)")

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

            Picker("Motion", selection: $motion) {
                ForEach(PrototypeMotion.allCases) { item in
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
        .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 11))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
        .environment(\.colorScheme, .dark)
    }

    private func cycle(_ offset: Int) {
        let scenarios = PrototypeScenario.allCases
        guard let index = scenarios.firstIndex(of: scenario) else { return }
        scenario = scenarios[(index + offset + scenarios.count) % scenarios.count]
    }

    private func resize(to preset: WindowPreset) {
        guard let window = NSApp.keyWindow else { return }
        let oldFrame = window.frame
        let nextFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: preset.size))
        let origin = NSPoint(
            x: oldFrame.midX - nextFrame.width / 2,
            y: oldFrame.midY - nextFrame.height / 2
        )
        window.setFrame(
            NSRect(origin: origin, size: nextFrame.size),
            display: true,
            animate: motion == .normal
        )
    }
}
