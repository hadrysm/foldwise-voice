// Keep history grouping and usage calculations outside the SwiftUI render path
// so their behavior can be tested without view inspection.

import AppKit
import Combine
import SwiftUI

struct HomeView: View {
    private struct Metric: Identifiable {
        let identifier: String
        let symbolName: String
        let label: String
        let value: String?
        let unit: String?

        var id: String {
            identifier
        }
    }

    @ObservedObject var model: SettingsModel
    private let now: () -> Date
    private let calendar: Calendar
    private let locale: Locale
    private let notificationCenter: NotificationCenter
    private let project: (HomeProjection.Input, Date, Calendar, Locale) -> HomeProjection

    /// Both projections are memoized off their actual inputs — SettingsModel
    /// has dozens of unrelated @Published fields, and recomputing a whole-
    /// history scan on every publish would put it on the render path.
    @State private var stats = UsageStats.empty
    @State private var projection = HomeProjection(sections: [])
    @State private var projectionIsReady = false

    init(
        model: SettingsModel,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        locale: Locale = .current,
        notificationCenter: NotificationCenter = .default,
        project: @escaping (HomeProjection.Input, Date, Calendar, Locale) -> HomeProjection = {
            HomeProjection.project($0, now: $1, calendar: $2, locale: $3)
        }
    ) {
        self.model = model
        self.now = now
        self.calendar = calendar
        self.locale = locale
        self.notificationCenter = notificationCenter
        self.project = project
    }

    var body: some View {
        main
            .paneFirstMeaningfulFrame(
                .home,
                performance: model.panePerformance,
                isReady: projectionIsReady
            )
            .onChange(of: projectionInput, initial: true) { _, input in
                stats = UsageStatsAggregator.aggregate(input.entries)
                refreshProjection(input)
                projectionIsReady = true
            }
            .onReceive(notificationCenter.publisher(for: .NSCalendarDayChanged)) { _ in
                refreshProjection(projectionInput)
            }
    }

    private var projectionInput: HomeProjection.Input {
        HomeProjection.Input(entries: model.historyEntries, modes: model.modes)
    }

    private var overviewLayout: HomeOverviewLayout {
        HomeOverviewLayout.forWindowWidth(model.windowWidth)
    }

    private func refreshProjection(_ input: HomeProjection.Input) {
        projection = project(input, now(), calendar, locale)
    }

    // MARK: - main column

    private var main: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Ready when you are.")
                    .font(Theme.display)
                    .tracking(Theme.displayTracking)
                    .foregroundStyle(Theme.textPrimary)
                hotkeyHint
                usageOverview
                systemStatusCard
                recentHeader
                if projection.isEmpty {
                    EmberEmptyState(
                        symbolName: "waveform",
                        title: "Your first Dictation session will appear here.",
                        detail: "Hold your Push to Talk shortcut and speak when you’re ready."
                    )
                } else {
                    dictationList
                    Button {
                        model.selectPane(.history)
                    } label: {
                        Text("All history →")
                    }
                    .buttonStyle(EmberButtonStyle(kind: .quiet))
                }
            }
            .padding(.horizontal, overviewLayout.contentPadding)
            .padding(.top, overviewLayout.contentPadding)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.canvas)
    }

    /// "Hold ⟨keycap⟩ and speak…" — the keycap renders the user's actual
    /// configured hotkey, never hardcoded copy.
    private var hotkeyHint: some View {
        HStack(spacing: 6) {
            Text("Hold")
            Keycap(text: keycapLabel(model.pttKey))
            Text("and speak — release to insert at your cursor.")
        }
        .font(Theme.body)
        .foregroundStyle(Theme.textSecondary)
    }

    private var dictationList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(projection.sections.enumerated()), id: \.element.header) { i, section in
                if i > 0 {
                    EmberSectionLabel(section.header)
                        .padding(.top, 14)
                        .padding(.bottom, 6)
                }
                EmberSurface {
                    VStack(spacing: 0) {
                        ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                            DictationRow(
                                presentation: row.presentation,
                                moreCapabilities: nil,
                                onCommand: { command in
                                    model.onHistoryCommand?(row.entry, command)
                                }
                            )
                            if index < section.rows.count - 1 {
                                EmberHairline(axis: .horizontal)
                            }
                        }
                    }
                }
            }
        }
    }

    private var recentHeader: some View {
        HStack {
            EmberSectionLabel(
                projection.sections.first?.header ?? "Recent Dictation sessions",
                symbolName: "list.bullet"
            )
            Spacer()
            Text("NEWEST 10")
                .font(Theme.mono(9, .bold))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - overview

    @ViewBuilder
    private var usageOverview: some View {
        let metrics = overviewMetrics
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 8),
                count: overviewLayout.metricColumnCount
            ),
            spacing: 8
        ) {
            ForEach(metrics) { metric in
                statCell(metric)
            }
        }
    }

    private func statCell(_ metric: Metric) -> some View {
        EmberSurface {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: metric.symbolName)
                        .font(Theme.ui(12, .semibold))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    Text(metric.value ?? "—")
                        .font(Theme.mono(20, .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                    if metric.value != nil, let unit = metric.unit {
                        Text(unit)
                            .font(Theme.mono(10, .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Text(metric.label)
                    .font(Theme.ui(11.5, .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("home.metric.\(metric.identifier)")
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        }
    }

    private var overviewMetrics: [Metric] {
        [
            Metric(
                identifier: "totalWords",
                symbolName: "textformat",
                label: "total words",
                value: stats.totalWords.formatted(),
                unit: nil
            ),
            Metric(
                identifier: "speakingSpeed",
                symbolName: "bolt",
                label: "speaking speed",
                value: wordsPerMinuteText,
                unit: "wpm"
            ),
            Metric(
                identifier: "currentStreak",
                symbolName: "flame",
                label: "current streak",
                value: streakText,
                unit: streakUnit
            ),
            Metric(
                identifier: "timeSaved",
                symbolName: "clock.arrow.circlepath",
                label: "time saved",
                value: timeSavedText,
                unit: "min"
            ),
        ]
    }

    private var wordsPerMinuteText: String? {
        guard let wpm = stats.wordsPerMinute, wpm >= 0.5 else { return nil }
        return "\(Int(wpm.rounded()))"
    }

    private var streakText: String? {
        guard let days = model.currentStreak else { return nil }
        return "\(days)"
    }

    private var streakUnit: String {
        model.currentStreak == 1 ? "day" : "days"
    }

    private var timeSavedText: String? {
        guard let minutes = stats.timeSavedMinutes, minutes >= 0.5 else { return nil }
        return "~\(Int(minutes.rounded()))"
    }

    /// The at-a-glance system summary: active ASR model, Polish model,
    /// permissions, version — plus a link into Stats.
    private var systemStatusCard: some View {
        let fullRecovery = model.permissionRecovery.snapshot.hasFullRecovery
        return EmberSurface(level: .raised) {
            HStack(spacing: 12) {
                EmberIngress(color: Theme.accent)
                Image(systemName: fullRecovery
                    ? "checkmark.circle.fill"
                    : "exclamationmark.triangle.fill")
                    .foregroundStyle(fullRecovery ? Theme.success : Theme.warning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(fullRecovery ? "All systems go" : "Needs attention")
                        .font(Theme.ui(12, .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(summaryLine)
                        .font(Theme.ui(10.5))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    if !fullRecovery {
                        Button("Permissions…") {
                            model.onOpenPermissionRecovery?()
                        }
                        .buttonStyle(EmberButtonStyle(kind: .quiet))
                        .accessibilityIdentifier("home.permission-recovery")
                    }
                    Button("Stats →") {
                        model.selectPane(.stats)
                    }
                    .buttonStyle(EmberButtonStyle(kind: .quiet))
                }
            }
            .padding(.trailing, 14)
            .frame(minHeight: 58)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.readiness")
    }

    private var summaryLine: String {
        [
            model.effectiveASRModelName,
            model.selectedModel.isEmpty ? "no polish model" : model.selectedModel,
            permissionSummary,
            "v\(AppInfo.version)",
        ].joined(separator: " · ")
    }

    private var permissionSummary: String {
        let snapshot = model.permissionRecovery.snapshot
        if snapshot.hasFullRecovery {
            return "permissions granted"
        }
        if snapshot.hasShortcutFallback {
            return "clipboard-only permissions"
        }
        return "permissions missing"
    }
}
