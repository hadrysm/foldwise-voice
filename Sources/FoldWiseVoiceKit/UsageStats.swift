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
}

/// Computes `UsageStats` from the history entries already loaded into the
/// Settings model. Pure and order-independent, so its rules are unit-tested
/// apart from the (untested) SwiftUI pane — modeled on `HistoryFilter`.
enum UsageStatsAggregator {
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
        // One pass over the history, splitting each `rawText` exactly once. Every
        // accumulator is order-independent, so the single loop is identical to the
        // separate reductions it replaces — it just stops re-splitting timed
        // entries a second time. WPM is an aggregate (Σ words ÷ Σ minutes) over
        // only the entries that carry a positive hold-to-talk duration, not a mean
        // of per-entry rates (which a few very short dictations would skew); a
        // positively-timed entry contributes its already-counted words to
        // `timedWords` and its ms to `timedMs`. Active days are de-duped by
        // `startOfDay` through the injected calendar so time zone and DST day
        // arithmetic are correct.
        var totalWords = 0
        var timedWords = 0
        var timedMs = 0
        var activeDaySet: Set<Date> = []
        for entry in entries {
            let words = wordCount(entry.rawText)
            totalWords += words
            let durationMs = entry.durationMs ?? 0
            if durationMs > 0 {
                timedWords += words
                timedMs += durationMs
            }
            activeDaySet.insert(calendar.startOfDay(for: entry.createdAt))
        }

        // `nil` when nothing is timed, so the pane shows "—" rather than dividing
        // by zero or claiming "0 wpm".
        let wordsPerMinute = timedMs > 0 ? Double(timedWords) / (Double(timedMs) / 60000) : nil
        let activeDays = activeDaySet.count

        // Time saved vs typing, over the same timed entries as WPM: the minutes
        // those spoken words would have taken at the typing baseline, minus the
        // real (pause-inclusive) dictation minutes. Clamped so a baseline that
        // would out-type the dictation collapses to `nil` rather than a negative
        // claim, and `nil` when nothing is timed — the estimate can only
        // under-promise.
        let timeSavedMinutes = timeSaved(
            timedWords: timedWords,
            timedMs: timedMs,
            typingWordsPerMinute: typingWordsPerMinute
        )

        return UsageStats(
            totalWords: totalWords,
            wordsPerMinute: wordsPerMinute,
            activeDays: activeDays,
            timeSavedMinutes: timeSavedMinutes
        )
    }

    /// The clamped time-saved estimate in minutes, or `nil` when there is nothing
    /// honest to show — no timed dictation, or a baseline fast enough to have
    /// out-typed it.
    private static func timeSaved(timedWords: Int, timedMs: Int, typingWordsPerMinute: Double) -> Double? {
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
