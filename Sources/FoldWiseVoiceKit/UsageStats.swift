// Usage stats: a pure projection over the dictation history the app already
// keeps (PRD #97). Four of the five stats are a lens, not a new ledger — they
// retain nothing on disk, inherit the "Save dictation history" switch and the
// retention window for free, and shrink honestly when history is turned off or
// pruned. This aggregator ships total words, speaking speed, and active days;
// the remaining time-saved estimate extends `UsageStats` in a later slice.
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
}

/// Computes `UsageStats` from the history entries already loaded into the
/// Settings model. Pure and order-independent, so its rules are unit-tested
/// apart from the (untested) SwiftUI pane — modeled on `HistoryFilter`.
enum UsageStatsAggregator {
    static func aggregate(_ entries: [HistoryEntry], calendar: Calendar = .current) -> UsageStats {
        let totalWords = entries.reduce(0) { $0 + wordCount($1.rawText) }

        // WPM is an aggregate — Σ words ÷ Σ minutes — over only the entries that
        // carry a positive hold-to-talk duration, not a mean of per-entry rates
        // (which a few very short dictations would skew). `nil` when nothing is
        // timed, so the pane shows "—" rather than dividing by zero or claiming
        // "0 wpm".
        let timed = entries.filter { ($0.durationMs ?? 0) > 0 }
        let timedWords = timed.reduce(0) { $0 + wordCount($1.rawText) }
        let timedMs = timed.reduce(0) { $0 + ($1.durationMs ?? 0) }
        let wordsPerMinute = timedMs > 0 ? Double(timedWords) / (Double(timedMs) / 60000) : nil

        // Distinct days someone dictated on, de-duped by startOfDay through the
        // injected calendar so time zone and DST day arithmetic are correct.
        let activeDays = Set(entries.map { calendar.startOfDay(for: $0.createdAt) }).count

        return UsageStats(totalWords: totalWords, wordsPerMinute: wordsPerMinute, activeDays: activeDays)
    }

    /// Spoken-word count for one transcript, using the same whitespace split the
    /// pipeline uses when it records `wordCount` (`Pipeline.swift`), so leading,
    /// trailing, and repeated whitespace can't inflate the total.
    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }
}
