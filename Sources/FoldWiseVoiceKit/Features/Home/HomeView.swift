// Keep history grouping and usage calculations outside the SwiftUI render path
// so their behavior can be tested without view inspection.

import AppKit
import SwiftUI

struct HomeView: View {
    private struct Metric: Identifiable {
        let label: String
        let value: String?
        let unit: String?

        var id: String {
            label
        }
    }

    @ObservedObject var model: SettingsModel

    /// Both projections are memoized off `historyEntries` — SettingsModel has
    /// dozens of unrelated @Published fields, and recomputing a whole-history
    /// scan on every publish would put it on the render path (cf. StatsPane).
    @State private var stats = UsageStats.empty
    @State private var projection = HomeProjection(sections: [])

    private static let accessibilitySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )

    var body: some View {
        main
            .onChange(of: model.historyEntries, initial: true) { _, entries in
                stats = UsageStatsAggregator.aggregate(entries)
                projection = HomeProjection.project(entries, now: Date())
            }
    }

    // MARK: - main column

    private var main: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Ready when you are.")
                    .font(Theme.pageTitle)
                    .kerning(-0.56)
                    .foregroundStyle(Theme.textPrimary)
                hotkeyHint
                    .padding(.top, 10)
                usageOverview
                    .padding(.top, 30)
                systemStatusCard
                    .padding(.top, 14)
                if projection.isEmpty {
                    Text("Your dictations will appear here after you speak.")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textFaint)
                        .padding(.top, 34)
                } else {
                    dictationList
                        .padding(.top, 28)
                    Button {
                        model.pane = .history
                    } label: {
                        Text("All history →")
                            .font(Theme.ui(12.5, .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 18)
                }
            }
            .padding(.horizontal, Theme.contentPadding)
            .padding(.top, Theme.contentPadding)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
                sectionLabel(section.header)
                    .padding(.top, i == 0 ? 0 : 22)
                    .padding(.bottom, 4)
                ForEach(section.rows) { row in
                    HomeDictationRow(model: model, row: row)
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Theme.sectionLabel)
            .kerning(1.1)
            .foregroundStyle(Theme.textTertiary)
    }

    // MARK: - overview

    @ViewBuilder
    private var usageOverview: some View {
        let layout = HomeOverviewLayout.forWindowWidth(model.windowWidth)
        let metrics = overviewMetrics
        Group {
            if layout == .wide {
                metricRow(metrics)
            } else {
                VStack(spacing: 0) {
                    metricRow(Array(metrics.prefix(2)))
                    horizontalRule
                    metricRow(Array(metrics.suffix(2)))
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var horizontalRule: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
    }

    private var verticalRule: some View {
        Rectangle().fill(Theme.hairline).frame(width: 1)
    }

    private func metricRow(_ metrics: [Metric]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                statCell(metric)
                if index < metrics.count - 1 {
                    verticalRule
                }
            }
        }
    }

    private func statCell(_ metric: Metric) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(metric.value ?? "—")
                    .font(Theme.statNumber)
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                if metric.value != nil, let unit = metric.unit {
                    Text(unit)
                        .font(Theme.ui(11))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Text(metric.label)
                .font(Theme.ui(12))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
    }

    private var overviewMetrics: [Metric] {
        [
            Metric(label: "total words", value: stats.totalWords.formatted(), unit: nil),
            Metric(label: "speaking speed", value: wordsPerMinuteText, unit: "wpm"),
            Metric(label: "current streak", value: streakText, unit: streakUnit),
            Metric(label: "time saved", value: timeSavedText, unit: "min"),
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
    /// accessibility, version — plus a link into Stats.
    private var systemStatusCard: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Theme.accent)
                .frame(width: 3, height: 36)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.axTrusted ? "All systems go" : "Needs attention")
                    .font(Theme.ui(12.5, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(summaryLine)
                    .font(Theme.ui(11.5))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if !model.axTrusted {
                    Button("Open Accessibility…") {
                        if let url = Self.accessibilitySettingsURL {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
            }
            Spacer(minLength: 12)
            Button {
                model.pane = .stats
            } label: {
                Text("Stats →")
                    .font(Theme.ui(12, .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            Theme.cardBackground,
            in: RoundedRectangle(cornerRadius: Theme.cardRadius)
        )
    }

    private var summaryLine: String {
        [
            asrModelName,
            model.selectedModel.isEmpty ? "no polish model" : model.selectedModel,
            model.axTrusted ? "accessibility granted" : "accessibility missing",
            "v\(AppInfo.version)",
        ].joined(separator: " · ")
    }

    /// The active ASR model, resolved like the transcriber resolves it: an
    /// unknown/fossil id (ADR-0006) reads as the Parakeet default the app
    /// actually transcribes with, so Home never claims a model that isn't
    /// running.
    private var asrModelName: String {
        let entry = ASRModelCatalog.entry(for: model.asrModel)
            ?? ASRModelCatalog.entry(for: ASRModelCatalog.defaultID)
        return entry?.name ?? "Parakeet TDT v3"
    }
}

/// One inert recent-dictation row. Its transient pointer, focus, and copy
/// confirmation state stays local so Home's projection remains a pure view of
/// history and the existing History workflow continues to own side effects.
private struct HomeDictationRow: View {
    private enum FocusTarget: Hashable {
        case row
        case copy
        case flag
    }

    let model: SettingsModel
    let row: HomeProjection.Row

    @State private var hovered = false
    @State private var copied = false
    @State private var copyResetTask: Task<Void, Never>?
    @FocusState private var focusedTarget: FocusTarget?

    private var actionsRevealed: Bool {
        hovered || focusedTarget != nil || copied
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(row.time)
                    .font(Theme.timestamp)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 44, alignment: .leading)
                Text(row.preview)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 16)
                trailingRegion
            }
            .padding(.horizontal, 6)
            .frame(height: 44)
            .background(actionsRevealed && hovered ? Theme.accent.opacity(0.055) : .clear)
            .overlay {
                if focusedTarget != nil {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
            .focusable(interactions: .activate)
            .focused($focusedTarget, equals: .row)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(row.time), \(row.preview), Mode \(row.tag)")
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
        .onHover { hovering in
            hovered = hovering
        }
        .onDisappear {
            copyResetTask?.cancel()
        }
    }

    private var trailingRegion: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 7) {
                Text(row.tag)
                    .font(Theme.modeTag)
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
                if row.entry.flagged {
                    Image(systemName: "flag.fill")
                        .font(Theme.ui(11, .semibold))
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                }
            }
            .opacity(actionsRevealed ? 0 : 1)
            .allowsHitTesting(false)

            HStack(spacing: 4) {
                copyButton
                flagButton
            }
            .allowsHitTesting(actionsRevealed)
        }
        .frame(width: 118, alignment: .trailing)
    }

    private var copyButton: some View {
        Button(action: copyDisplayedText) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(Theme.ui(12, .semibold))
                .foregroundStyle(copied ? AnyShapeStyle(.green) : AnyShapeStyle(Theme.textSecondary))
                .opacity(actionsRevealed ? 1 : 0)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(interactions: .activate)
        .focused($focusedTarget, equals: .copy)
        .accessibilityLabel("Copy text")
        .accessibilityHint("Copies the displayed dictation text.")
        .help("Copy text")
    }

    private var flagButton: some View {
        let flagged = row.entry.flagged
        return Button {
            model.onFlagHistory?(row.entry)
        } label: {
            Image(systemName: flagged ? "flag.fill" : "flag")
                .font(Theme.ui(12, .semibold))
                .foregroundStyle(flagged ? AnyShapeStyle(.orange) : AnyShapeStyle(Theme.textSecondary))
                .opacity(actionsRevealed ? 1 : 0)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(interactions: .activate)
        .focused($focusedTarget, equals: .flag)
        .accessibilityLabel(flagged ? "Remove flag" : "Flag for my review")
        .accessibilityHint(
            flagged
                ? "Removes this dictation from your flagged items."
                : "Flags this dictation for later review."
        )
        .help(flagged ? "Remove flag" : "Flag for my review")
    }

    private func copyDisplayedText() {
        model.onCopyHistory?(row.entry)
        copied = true
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "Copied",
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ]
        )
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}
