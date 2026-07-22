// Usage stats: a pure projection over the dictation history the app already
// keeps (PRD #97). Four of the five stats are a lens, not a new ledger — they
// retain nothing on disk, inherit the "Save dictation history" switch and the
// retention window for free, and shrink honestly when history is turned off or
// pruned. This aggregator ships total words, speaking speed, active days, and a
// conservative time-saved estimate against a typing baseline.
//
// Every word count is taken from an entry's `rawText` — the pre-Polish
// transcript, what was actually spoken — not the stored `wordCount` field, which
// counts the shown/polished text and can diverge wildly for Expanding Modes.
// That keeps the whole card on one honest speaking-word basis.

import Foundation

/// The numbers the Stats pane renders, computed by `UsageStatsAggregator`. A
/// plain value type mirroring the pure, unit-tested helpers this feature follows
/// (`PolishStatus`, `RetentionWindow`), so the SwiftUI pane stays a thin render
/// over it.
struct UsageStats: Equatable {
    /// Total spoken words across the kept history — the sum of each entry's
    /// `rawText` word count.
    let totalWords: Int
    /// Aggregate speaking speed: Σ spoken words ÷ Σ dictation minutes over only
    /// the entries that carry a positive duration. `nil` — rendered "—" — when no
    /// timed entry exists, never 0. Deliberately not a mean of per-entry rates,
    /// and honestly lower than a marketing figure because the stored duration is
    /// hold-to-talk time including pauses.
    let wordsPerMinute: Double?
    /// Distinct calendar days (`startOfDay`) on which a dictation was recorded.
    let activeDays: Int
    /// A conservative estimate of the minutes dictation saved versus typing: the
    /// timed spoken words retyped at the typing baseline, minus the real
    /// pause-inclusive dictation minutes. `nil` — rendered "—" — when there is
    /// nothing to claim (no timed entry, or a baseline that would have out-typed
    /// the dictation), so it can only under-promise and never shows a negative or
    /// fabricated figure. Always an estimate, never a measured fact.
    let timeSavedMinutes: Double?

    /// The zero projection — no kept dictations to draw on: no words, no timed
    /// rate, no active days, nothing to claim as saved. Seeds the pane's memoized
    /// cache before the first aggregate.
    static let empty = UsageStats(totalWords: 0, wordsPerMinute: nil, activeDays: 0, timeSavedMinutes: nil)
}

/// Computes `UsageStats` from the history entries already loaded into the
/// Settings model. Pure and order-independent, so its calculation rules are
/// unit-tested independently of rendering — modeled on `HistoryProjection`.
enum UsageStatsAggregator {
    struct Session: Equatable {
        let localDay: Date
        let spokenWords: Int
        let usableDurationMs: Int?
    }

    struct Accumulator {
        private var totalWords = 0
        private var timedWords = 0
        private var timedMs = 0
        private var activeDays: Set<Date> = []

        mutating func add(_ session: Session) {
            totalWords += session.spokenWords
            if let durationMs = session.usableDurationMs {
                timedWords += session.spokenWords
                timedMs += durationMs
            }
            activeDays.insert(session.localDay)
        }

        func stats(
            typingWordsPerMinute: Double = UsageStatsAggregator.typingBaselineWordsPerMinute
        ) -> UsageStats {
            let wordsPerMinute = timedMs > 0
                ? Double(timedWords) / (Double(timedMs) / 60000)
                : nil
            return UsageStats(
                totalWords: totalWords,
                wordsPerMinute: wordsPerMinute,
                activeDays: activeDays.count,
                timeSavedMinutes: UsageStatsAggregator.timeSaved(
                    timedWords: timedWords,
                    timedMs: timedMs,
                    typingWordsPerMinute: typingWordsPerMinute
                )
            )
        }
    }

    /// The typing speed the time-saved estimate is measured against — Wispr's
    /// in-app "average keyboard typist" figure. Chosen over its 40-wpm marketing
    /// number because a *higher* baseline shrinks the claim, biasing the estimate
    /// conservative. The Stats pane labels the estimate with this same number.
    static let typingBaselineWordsPerMinute: Double = 52

    static func aggregate(
        _ entries: [HistoryEntry],
        calendar: Calendar = .current,
        typingWordsPerMinute: Double = UsageStatsAggregator.typingBaselineWordsPerMinute
    ) -> UsageStats {
        aggregate(
            normalize(entries, calendar: calendar),
            typingWordsPerMinute: typingWordsPerMinute
        )
    }

    static func normalize(_ entries: [HistoryEntry], calendar: Calendar) -> [Session] {
        entries.map { entry in
            let durationMs = entry.durationMs ?? 0
            return Session(
                localDay: calendar.startOfDay(for: entry.createdAt),
                spokenWords: wordCount(entry.rawText),
                usableDurationMs: durationMs > 0 ? durationMs : nil
            )
        }
    }

    static func aggregate(
        _ sessions: [Session],
        typingWordsPerMinute: Double = UsageStatsAggregator.typingBaselineWordsPerMinute
    ) -> UsageStats {
        // One pass over sessions whose local day was resolved during
        // normalization. WPM is an aggregate (Σ words ÷ Σ minutes) over
        // positive hold-to-talk durations.
        var accumulator = Accumulator()
        for session in sessions {
            accumulator.add(session)
        }
        return accumulator.stats(typingWordsPerMinute: typingWordsPerMinute)
    }

    /// The clamped time-saved estimate in minutes, or `nil` when there is nothing
    /// honest to show — no timed dictation, or a baseline fast enough to have
    /// out-typed it.
    static func timeSaved(timedWords: Int, timedMs: Int, typingWordsPerMinute: Double) -> Double? {
        guard timedMs > 0 else { return nil }
        let typingMinutes = Double(timedWords) / typingWordsPerMinute
        let dictationMinutes = Double(timedMs) / 60000
        let saved = typingMinutes - dictationMinutes
        return saved > 0 ? saved : nil
    }

    /// Spoken-word count for one transcript, using the same whitespace split the
    /// pipeline uses when it records `wordCount` (`Pipeline.swift`), so leading,
    /// trailing, and repeated whitespace can't inflate the total.
    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }
}
