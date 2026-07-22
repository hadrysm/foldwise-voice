import AppKit
import Combine
import SwiftUI

struct StatsPane: View {
    @ObservedObject var model: SettingsModel
    @Environment(\.locale) private var environmentLocale
    @State private var projection: StatsProjection?
    @State private var projectionCache: StatsProjectionCache

    private let calendar: () -> Calendar
    private let locale: Locale?
    private let notificationCenter: NotificationCenter

    init(
        model: SettingsModel,
        projectionCache: StatsProjectionCache = StatsProjectionCache(),
        calendar: @escaping () -> Calendar = { .autoupdatingCurrent },
        locale: Locale? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        self.model = model
        _projectionCache = State(initialValue: projectionCache)
        self.calendar = calendar
        self.locale = locale
        self.notificationCenter = notificationCenter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("A look at how you dictate, drawn from the history you already keep.")
                .font(Theme.ui(12))
                .foregroundStyle(Theme.textSecondary)

            if let projection {
                notice(projection.notice)
                StatsMetricStrip(metrics: projection.metrics)
                MonthlyActivityCalendar(month: projection.month)
            }
        }
        .onChange(of: input, initial: true) { _, input in
            refresh(input)
        }
        .onChange(of: environmentLocale) { _, _ in
            refresh(input)
        }
        .onReceive(notificationCenter.publisher(for: .NSCalendarDayChanged)) { _ in
            refresh(input)
        }
        .onReceive(notificationCenter.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            refresh(input)
        }
    }

    private var input: StatsProjection.Input {
        StatsProjection.Input(
            entries: model.historyEntries,
            currentStreak: model.currentStreak,
            savingEnabled: model.saveHistory
        )
    }

    private func refresh(_ input: StatsProjection.Input) {
        projection = projectionCache.resolve(
            input,
            calendar: calendar(),
            locale: locale ?? environmentLocale
        )
    }

    @ViewBuilder
    private func notice(_ notice: StatsProjection.Notice) -> some View {
        switch notice {
        case .none:
            EmptyView()
        case let .noHistory(message):
            StatsNotice(
                symbol: "sparkles",
                message: message,
                accessibilityIdentifier: "stats.notice.noHistory"
            )
        case let .savingOff(message, actionTitle):
            StatsNotice(
                symbol: "pause.circle",
                message: message,
                actionTitle: actionTitle,
                accessibilityIdentifier: "stats.notice.savingOff"
            ) {
                openHistory()
            }
        }
    }

    private func openHistory() {
        model.pane = .history
    }
}

private struct StatsNotice: View {
    let symbol: String
    let message: String
    var actionTitle: String?
    let accessibilityIdentifier: String
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
                .accessibilityIdentifier("stats.decoration.notice")
            Text(message)
                .font(Theme.ui(11.5, .medium))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityIdentifier(accessibilityIdentifier)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                StatsHistoryButton(title: actionTitle, action: action)
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

struct StatsHistoryButton: NSViewRepresentable {
    let title: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            title: title,
            target: context.coordinator,
            action: #selector(Coordinator.performAction)
        )
        button.isBordered = false
        button.font = .systemFont(ofSize: 11.5, weight: .semibold)
        button.contentTintColor = NSColor(Theme.accent)
        button.setAccessibilityLabel(title)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        button.title = title
        button.contentTintColor = NSColor(Theme.accent)
        button.setAccessibilityLabel(title)
        context.coordinator.action = action
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func performAction() {
            action()
        }
    }
}

private struct StatsMetricStrip: View {
    let metrics: [StatsProjection.Metric]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(metrics) { metric in
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: metric.symbol)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    Text(metric.value)
                        .font(Theme.ui(metric.kind == .timeSaved ? 16.5 : 21, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
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
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cardRadius)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("stats.metric.\(metric.kind.rawValue)")
            }
        }
    }
}

private struct MonthlyActivityCalendar: View {
    let month: StatsProjection.Month

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredDate: Date?
    @State private var rovingDate: Date?
    @FocusState private var focusedDate: Date?

    init(month: StatsProjection.Month) {
        self.month = month
        _rovingDate = State(initialValue: month.days.last { $0.state != .future }?.date)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
    }

    private var eligibleDates: [Date] {
        month.days.filter { $0.state != .future }.map(\.date)
    }

    private var detailDay: StatsProjection.Day? {
        let date = CalendarFocusNavigator.detailDate(
            hovered: hoveredDate,
            focused: focusedDate
        )
        return month.days.first { $0.date == date && $0.state != .future }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            grid
            StatsDayDetail(day: detailDay)
                .accessibilityHidden(true)
            StatsIntensityLegend(labels: month.legendLabels)
        }
        .padding(18)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        }
        .transaction { transaction in
            StatsTransitionPolicy.clearInheritedAnimation(in: &transaction)
        }
        .onChange(of: month.days) { _, _ in
            repairFocus()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("This month")
                    .font(Theme.ui(16, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(month.title)
                    .font(Theme.ui(11.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(month.spokenWordSummary)
                    .font(Theme.ui(13, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(month.activeDaySummary)
                    .font(Theme.ui(10.5))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .accessibilityHidden(true)
        .accessibilityIdentifier("stats.duplicate.header")
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(month.weekdays, id: \.self) { weekday in
                Text(weekday)
                    .font(Theme.ui(9.5, .semibold))
                    .foregroundStyle(Theme.textFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("stats.weekday.\(weekday)")
            }
            ForEach(0 ..< month.leadingColumnOffset, id: \.self) { index in
                Color.clear
                    .frame(height: 49)
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("stats.spacer.leading.\(index)")
            }
            ForEach(month.days) { day in
                StatsDayCell(
                    day: day,
                    canFocus: day.date == rovingDate && day.state != .future,
                    isFocused: day.date == focusedDate,
                    reduceMotion: reduceMotion
                ) { hovering in
                    guard day.state != .future else { return }
                    if hovering {
                        hoveredDate = day.date
                    } else if hoveredDate == day.date {
                        hoveredDate = nil
                    }
                } onMove: { direction in
                    moveFocus(direction)
                }
                .focused($focusedDate, equals: day.date)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(month.accessibilityLabel)
        .accessibilityValue(month.accessibilityValue)
        .accessibilityIdentifier("stats.calendar")
    }

    private func moveFocus(_ direction: CalendarFocusNavigator.Direction) {
        guard let focusedDate else { return }
        let navigator = CalendarFocusNavigator(eligibleDates: eligibleDates)
        guard let next = navigator.move(from: focusedDate, direction: direction) else { return }
        rovingDate = next
        self.focusedDate = next
    }

    private func repairFocus() {
        hoveredDate = nil
        let navigator = CalendarFocusNavigator(eligibleDates: eligibleDates)
        let repaired = navigator.repair(focusedDate ?? rovingDate)
        rovingDate = repaired
        guard focusedDate != nil else { return }
        focusedDate = nil
        DispatchQueue.main.async {
            focusedDate = repaired
        }
    }
}

private struct StatsDayCell: View {
    let day: StatsProjection.Day
    let canFocus: Bool
    let isFocused: Bool
    let reduceMotion: Bool
    let onHover: (Bool) -> Void
    let onMove: (CalendarFocusNavigator.Direction) -> Void

    private var style: StatsActivityStyle {
        StatsActivityStyle(day: day, focused: isFocused)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(day.dayNumber)
                .font(Theme.mono(10, .semibold))
            Spacer(minLength: 1)
            if let compactWords = day.compactSpokenWords {
                Text(compactWords)
                    .font(Theme.mono(9, .medium))
                    .monospacedDigit()
            } else if day.state != .future {
                Text("—")
                    .font(Theme.mono(9))
            }
        }
        .foregroundStyle(style.foreground)
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 49, alignment: .topLeading)
        .background(style.background, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(style.outline, lineWidth: isFocused ? 3 : 1)
                if isFocused {
                    RoundedRectangle(cornerRadius: 6)
                        .inset(by: 2)
                        .strokeBorder(Theme.accent, lineWidth: 1)
                }
            }
        }
        .shadow(color: style.shadow, radius: 3)
        .contentShape(Rectangle())
        .focusable(canFocus)
        .focusEffectDisabled()
        .onHover(perform: onHover)
        .onMoveCommand { direction in
            guard isFocused else { return }
            switch direction {
            case .left: onMove(.left)
            case .right: onMove(.right)
            case .up: onMove(.up)
            case .down: onMove(.down)
            default: break
            }
        }
        .animation(
            StatsTransitionPolicy.resolve(reduceMotion: reduceMotion).animation,
            value: day.intensity
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.accessibilityLabel)
        .accessibilityValue(day.accessibilityValue)
        .accessibilityHidden(day.state == .future)
        .accessibilityIdentifier("stats.day.\(day.dayNumber)")
    }
}

private struct StatsDayDetail: View {
    let day: StatsProjection.Day?

    var body: some View {
        Group {
            if let day {
                VStack(alignment: .leading, spacing: 3) {
                    Text(day.fullDate)
                        .font(Theme.ui(11.5, .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(day.detailActivity)
                        .font(Theme.ui(10.5))
                        .foregroundStyle(Theme.textSecondary)
                    if let timing = day.detailTiming {
                        Text(timing)
                            .font(Theme.ui(10.5))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "cursorarrow.motionlines")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textFaint)
                        .accessibilityHidden(true)
                    Text("Hover a past day, or Tab into the calendar and use the arrow keys.")
                        .font(Theme.ui(10.5))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.windowBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("stats.duplicate.detail")
    }
}

private struct StatsIntensityLegend: View {
    let labels: [String]

    var body: some View {
        HStack(spacing: 12) {
            Text("Daily spoken words")
                .font(Theme.ui(10, .semibold))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 6)
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(StatsActivityStyle.legendFill(level: index))
                        .frame(width: 13, height: 13)
                        .overlay {
                            RoundedRectangle(cornerRadius: 2.5)
                                .strokeBorder(Theme.hairline, lineWidth: index == 0 ? 1 : 0)
                        }
                        .accessibilityHidden(true)
                        .accessibilityIdentifier("stats.decoration.legend.\(index)")
                    Text(label)
                        .font(Theme.mono(8.7, .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct StatsActivityStyle {
    let background: Color
    let foreground: Color
    let outline: Color
    let shadow: Color

    init(day: StatsProjection.Day, focused: Bool) {
        if day.state == .future {
            background = Theme.windowBackground.opacity(0.28)
            foreground = Theme.textFaint.opacity(0.42)
        } else {
            background = Self.legendFill(level: day.intensity.rawValue)
            foreground = day.intensity == .veryHigh ? .black : Theme.textPrimary
        }
        if focused {
            outline = Theme.textPrimary
            shadow = Theme.textPrimary.opacity(0.22)
        } else if day.state == .today {
            outline = Theme.textTertiary.opacity(0.72)
            shadow = .clear
        } else {
            outline = .clear
            shadow = .clear
        }
    }

    static func legendFill(level: Int) -> Color {
        guard level > 0 else { return Theme.windowBackground.opacity(0.72) }
        let opacities = [0.0, 0.20, 0.36, 0.54, 0.76, 0.96]
        return Theme.accent.opacity(opacities[min(level, opacities.count - 1)])
    }
}

enum StatsTransitionPolicy: Equatable {
    case immediate
    case crossfade

    static func resolve(reduceMotion: Bool) -> StatsTransitionPolicy {
        reduceMotion ? .immediate : .crossfade
    }

    static func clearInheritedAnimation(in transaction: inout Transaction) {
        transaction.animation = nil
    }

    var animation: Animation? {
        switch self {
        case .immediate: nil
        case .crossfade: .easeOut(duration: 0.14)
        }
    }
}
