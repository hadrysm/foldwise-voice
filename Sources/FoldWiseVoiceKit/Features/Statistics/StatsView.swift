import AppKit
import Combine
import SwiftUI

struct StatsEnvironmentAdaptations: Equatable {
    let reduceMotion: Bool
    let increaseContrast: Bool
}

struct StatsPane: View {
    let interface: StatsPaneInterface
    @Environment(\.locale) private var environmentLocale
    @Environment(\.accessibilityReduceMotion) private var environmentReduceMotion
    @Environment(\.colorSchemeContrast) private var environmentContrast
    @State private var completed: PaneProjectionStore.Completed<StatsProjection>?

    private let now: () -> Date
    private let calendar: () -> Calendar
    private let locale: Locale?
    private let notificationCenter: NotificationCenter
    private let environmentOverride: StatsEnvironmentAdaptations?

    init(
        interface: StatsPaneInterface,
        now: @escaping () -> Date = Date.init,
        calendar: @escaping () -> Calendar = { .autoupdatingCurrent },
        locale: Locale? = nil,
        notificationCenter: NotificationCenter = .default,
        environmentOverride: StatsEnvironmentAdaptations? = nil
    ) {
        self.interface = interface
        self.now = now
        self.calendar = calendar
        self.locale = locale
        self.notificationCenter = notificationCenter
        self.environmentOverride = environmentOverride
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("A look at how you dictate, drawn from the History you already keep.")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)

            if let projection = completed?.value {
                notice(projection.notice)
                StatsMetricStrip(metrics: projection.metrics)
                MonthlyActivityCalendar(
                    month: projection.month,
                    environment: resolvedEnvironment
                )
            }
        }
        .paneFirstMeaningfulFrame(
            .stats,
            performance: interface.performance,
            isReady: completed != nil
        )
        .onChange(of: interface.projectionRevision, initial: true) { _, _ in
            refresh()
        }
        .onChange(of: environmentLocale) { _, _ in
            refresh()
        }
        .onReceive(notificationCenter.publisher(for: .NSCalendarDayChanged)) { _ in
            refresh()
        }
        .onReceive(notificationCenter.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            refresh()
        }
    }

    private var resolvedEnvironment: StatsEnvironmentAdaptations {
        environmentOverride ?? StatsEnvironmentAdaptations(
            reduceMotion: environmentReduceMotion,
            increaseContrast: environmentContrast == .increased
        )
    }

    private func refresh() {
        completed = interface.projection(in: .init(
            now: now(),
            calendar: calendar(),
            locale: locale ?? environmentLocale
        ))
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
                color: Theme.accent,
                accessibilityIdentifier: "stats.notice.noHistory"
            )
        case let .savingOff(message, actionTitle):
            StatsNotice(
                symbol: "pause.circle",
                message: message,
                color: Theme.warning,
                actionTitle: actionTitle,
                accessibilityIdentifier: "stats.notice.savingOff"
            ) {
                openHistory()
            }
        }
    }

    private func openHistory() {
        interface.openHistory()
    }
}

private struct StatsNotice: View {
    let symbol: String
    let message: String
    let color: Color
    var actionTitle: String?
    let accessibilityIdentifier: String
    var action: (() -> Void)?

    var body: some View {
        EmberSurface(level: .raised) {
            HStack(spacing: 10) {
                EmberIngress(color: color)
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
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
            .padding(.trailing, 13)
            .frame(minHeight: 42)
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
        button.focusRingType = .default
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
        HStack(spacing: 12) {
            ForEach(metrics) { metric in
                HStack(spacing: 8) {
                    Image(systemName: metric.symbol)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(metric.title)
                            .font(Theme.ui(9.5, .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                        Text(metric.value)
                            .font(Theme.mono(12.5, .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Text(metric.detail)
                            .font(Theme.ui(9))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("stats.metric.\(metric.kind.rawValue)")
            }
        }
    }
}

private struct MonthlyActivityCalendar: View {
    let month: StatsProjection.Month
    let environment: StatsEnvironmentAdaptations

    @State private var hoveredDate: Date?
    @State private var rovingDate: Date?
    @FocusState private var focusedDate: Date?

    init(
        month: StatsProjection.Month,
        environment: StatsEnvironmentAdaptations
    ) {
        self.month = month
        self.environment = environment
        _rovingDate = State(initialValue: month.days.last { $0.state != .future }?.date)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
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
        EmberSurface {
            HStack(spacing: 0) {
                EmberIngress(color: Theme.accent)
                VStack(alignment: .leading, spacing: 12) {
                    header
                    grid
                    StatsDayDetail(day: detailDay, environment: environment)
                        .id(detailDay?.date)
                        .transition(.opacity)
                        .animation(
                            StatsTransitionPolicy.resolve(
                                reduceMotion: environment.reduceMotion
                            ).animation,
                            value: detailDay?.date
                        )
                        .accessibilityHidden(true)
                    StatsIntensityLegend(
                        labels: month.legendLabels,
                        environment: environment
                    )
                }
                .padding(14)
            }
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
                    .font(Theme.ui(17, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(month.title)
                    .font(Theme.ui(11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(month.spokenWordSummary)
                    .font(Theme.mono(11, .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text(month.activeDaySummary)
                    .font(Theme.mono(9.5, .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .accessibilityHidden(true)
        .accessibilityIdentifier("stats.duplicate.header")
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(month.weekdays, id: \.self) { weekday in
                Text(weekday)
                    .font(Theme.mono(9, .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("stats.weekday.\(weekday)")
            }
            ForEach(0 ..< month.leadingColumnOffset, id: \.self) { index in
                Color.clear
                    .frame(height: 44)
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("stats.spacer.leading.\(index)")
            }
            ForEach(month.days) { day in
                StatsDayCell(
                    day: day,
                    canFocus: day.date == rovingDate && day.state != .future,
                    isFocused: day.date == focusedDate,
                    isHovered: day.date == hoveredDate,
                    environment: environment
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
    let isHovered: Bool
    let environment: StatsEnvironmentAdaptations
    let onHover: (Bool) -> Void
    let onMove: (CalendarFocusNavigator.Direction) -> Void

    private var style: StatsActivityStyle {
        StatsActivityStyle(
            day: day,
            focused: isFocused,
            hovered: isHovered,
            increaseContrast: environment.increaseContrast
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(day.dayNumber)
                    .font(Theme.mono(10, .semibold))
                Spacer(minLength: 2)
                if day.state == .today {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 4, height: 4)
                        .accessibilityHidden(true)
                }
            }
            Spacer(minLength: 1)
            if day.state == .future || day.intensity == .neutral {
                Text("—")
                    .font(Theme.mono(9))
            } else {
                StatsWaveformCue(
                    intensity: day.intensity,
                    increaseContrast: environment.increaseContrast
                )
            }
        }
        .foregroundStyle(style.foreground)
        .padding(7)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
        .background(style.background, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(style.outline, lineWidth: style.boundaryWidth)
        }
        .emberInsetFocusRing(isFocused)
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
            StatsTransitionPolicy.resolve(reduceMotion: environment.reduceMotion).animation,
            value: day.intensity
        )
        .animation(
            StatsTransitionPolicy.resolve(reduceMotion: environment.reduceMotion).animation,
            value: isHovered
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
    let environment: StatsEnvironmentAdaptations

    var body: some View {
        HStack(spacing: 10) {
            if let day {
                if day.intensity == .neutral {
                    Text("—")
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    StatsWaveformCue(
                        intensity: day.intensity,
                        increaseContrast: environment.increaseContrast
                    )
                }
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
                Image(systemName: "cursorarrow.motionlines")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
                Text("Hover a past day, or Tab into the calendar and use the arrow keys.")
                    .font(Theme.ui(10.5))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("stats.duplicate.detail")
    }
}

private struct StatsIntensityLegend: View {
    let labels: [String]
    let environment: StatsEnvironmentAdaptations

    var body: some View {
        HStack(spacing: 12) {
            Text("Daily spoken words")
                .font(Theme.ui(10, .semibold))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 6)
            ForEach(
                Array(zip(StatsProjection.Day.Intensity.allCases, labels)),
                id: \.0.rawValue
            ) { intensity, label in
                HStack(spacing: 5) {
                    if intensity == .neutral {
                        Text("—")
                            .font(Theme.mono(9))
                            .foregroundStyle(Theme.textTertiary)
                    } else {
                        StatsWaveformCue(
                            intensity: intensity,
                            increaseContrast: environment.increaseContrast
                        )
                    }
                    Text(label)
                        .font(Theme.mono(8.7, .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .accessibilityHidden(true)
                .accessibilityIdentifier("stats.decoration.legend.\(intensity.rawValue)")
            }
        }
    }
}

private struct StatsWaveformCue: View {
    let intensity: StatsProjection.Day.Intensity
    let increaseContrast: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(
                Array(zip(
                    StatsActivityStyle.waveformBarHeights.indices,
                    StatsActivityStyle.waveformFillPattern(intensity)
                )),
                id: \.0
            ) { index, isFilled in
                Group {
                    if isFilled {
                        Capsule()
                            .fill(Theme.accent)
                    } else {
                        Capsule()
                            .strokeBorder(
                                Theme.essentialBorderColor(increaseContrast: increaseContrast),
                                lineWidth: Theme.essentialBorderWidth(
                                    increaseContrast: increaseContrast
                                )
                            )
                    }
                }
                .frame(width: 3, height: StatsActivityStyle.waveformBarHeights[index])
            }
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }
}

struct StatsActivityStyle {
    static let waveformBarHeights: [CGFloat] = [6, 10, 15, 11, 8]

    let background: Color
    let foreground: Color
    let outline: Color
    let boundaryWidth: CGFloat

    init(
        day: StatsProjection.Day,
        focused: Bool,
        hovered: Bool,
        increaseContrast: Bool
    ) {
        background = hovered && !focused && day.state != .future
            ? Theme.hover
            : Theme.raised
        foreground = day.state == .future ? Theme.textTertiary : Theme.textSecondary
        outline = increaseContrast || day.state == .today
            ? Theme.borderStrong
            : Theme.border
        boundaryWidth = Theme.essentialBorderWidth(increaseContrast: increaseContrast)
    }

    static func waveformFillPattern(
        _ intensity: StatsProjection.Day.Intensity
    ) -> [Bool] {
        waveformBarHeights.indices.map { $0 < intensity.rawValue }
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
        case .crossfade: .easeOut(duration: 0.16)
        }
    }
}
