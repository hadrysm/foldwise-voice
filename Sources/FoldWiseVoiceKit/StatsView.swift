// The Stats pane content (PRD #97): an at-a-glance, honestly-labeled reflection
// on your dictation, computed as a pure projection over the history the app
// already keeps — no new data is stored. This spine slice renders the first
// stat, total words dictated, in the app's native card system and owns the
// pane's empty and frozen states; the later slices add speaking speed, active
// days, current streak, and the time-saved estimate to the same card.
//
// The numbers are a lens over the loaded history: they reflect it as of window
// open, update live when a dictation is appended while the window is open (the
// Settings model prepends it), and shrink honestly when saving is off or old
// dictations are pruned. The pane is a thin render over `UsageStatsAggregator`,
// which carries the tested logic; the view itself is not unit-tested (PRD #78).

import SwiftUI

struct StatsPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(
                "A look at how you dictate, drawn from the history you already keep. "
                    + "Nothing new is stored — turn history off or prune it and these shrink."
            )
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

            if model.historyEntries.isEmpty {
                emptyState
            } else {
                populated
            }
        }
    }

    /// The stats card plus, when saving is off, a note that the numbers are no
    /// longer moving — so frozen figures are never mistaken for live ones.
    private var populated: some View {
        let stats = UsageStatsAggregator.aggregate(model.historyEntries)
        return VStack(alignment: .leading, spacing: 16) {
            Card {
                CardRow(
                    title: "Words dictated",
                    subtitle: "The words you actually spoke, across your saved history."
                ) {
                    statValue(stats.totalWords.formatted())
                }
                Divider().padding(.leading, 14)
                CardRow(
                    title: "Speaking speed",
                    subtitle: "Your words per minute over the time you held the key to talk — pauses and all."
                ) {
                    statValue(speakingSpeed(stats.wordsPerMinute))
                }
                Divider().padding(.leading, 14)
                CardRow(
                    title: "Active days",
                    subtitle: "Distinct days you've dictated on."
                ) {
                    statValue(stats.activeDays.formatted())
                }
                Divider().padding(.leading, 14)
                CardRow(
                    title: "Time saved",
                    subtitle: "A conservative estimate versus typing at "
                        + "\(Int(UsageStatsAggregator.typingBaselineWordsPerMinute)) wpm — not a measured figure."
                ) {
                    statValue(timeSaved(stats.timeSavedMinutes))
                }
            }
            if !model.saveHistory {
                Label(
                    "Saving is off — these numbers have stopped updating.",
                    systemImage: "pause.circle"
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
    }

    /// One stat's trailing figure, styled uniformly across the card.
    private func statValue(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .monospacedDigit()
    }

    /// Words-per-minute for display: rounded to a whole number with a unit, or
    /// "—" when no dictation carried a duration to divide by.
    private func speakingSpeed(_ wordsPerMinute: Double?) -> String {
        guard let wordsPerMinute else { return "—" }
        return "\(Int(wordsPerMinute.rounded())) wpm"
    }

    /// Time saved for display: a rounded whole-minute estimate ("~X min"), or "—"
    /// when there's nothing to claim — no timed dictation, dictation the baseline
    /// would have out-typed, or a saving that would round to zero minutes, so it
    /// never shows "~0 min".
    private func timeSaved(_ minutes: Double?) -> String {
        guard let minutes, minutes >= 0.5 else { return "—" }
        return "~\(Int(minutes.rounded())) min"
    }

    /// No kept dictations to project over. Adapts to *why*: when saving is off it
    /// points at the switch that turns it back on; otherwise it invites the user
    /// to dictate.
    private var emptyState: some View {
        Card {
            if model.saveHistory {
                CardRow(
                    title: "No stats yet",
                    subtitle: "Your usage will appear here after you dictate."
                ) {
                    EmptyView()
                }
            } else {
                CardRow(
                    title: "Saving is off",
                    subtitle: "Stats are drawn from your saved dictations, and saving history "
                        + "is turned off. Turn it on in History to start building your usage."
                ) {
                    Button("History…") { model.pane = .history }
                        .controlSize(.small)
                }
            }
        }
    }
}
