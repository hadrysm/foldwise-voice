// Usage stats: a pure projection over the dictation history the app already
// keeps (PRD #97). Four of the five stats are a lens, not a new ledger — they
// retain nothing on disk, inherit the "Save dictation history" switch and the
// retention window for free, and shrink honestly when history is turned off or
// pruned. This spine slice ships the first projection stat, total words; the
// later slices extend `UsageStats` and this aggregator with speaking speed,
// active days, and the time-saved estimate.
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
}

/// Computes `UsageStats` from the history entries already loaded into the
/// Settings model. Pure and order-independent, so its rules are unit-tested
/// apart from the (untested) SwiftUI pane — modeled on `HistoryFilter`.
enum UsageStatsAggregator {
    static func aggregate(_ entries: [HistoryEntry]) -> UsageStats {
        let totalWords = entries.reduce(0) { $0 + wordCount($1.rawText) }
        return UsageStats(totalWords: totalWords)
    }

    /// Spoken-word count for one transcript, using the same whitespace split the
    /// pipeline uses when it records `wordCount` (`Pipeline.swift`), so leading,
    /// trailing, and repeated whitespace can't inflate the total.
    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }
}
