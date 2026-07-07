// The Stats pane's numbers, exercised through the pure UsageStatsAggregator the
// (untested) SwiftUI pane renders over (PRD #97). This spine slice covers total
// words dictated: the count of the words actually spoken — taken from each
// entry's raw transcript (`rawText`), never the stored polished `wordCount` —
// summed over the kept history the Settings model already holds.

import XCTest
@testable import FoldWiseVoiceKit

final class UsageStatsAggregatorTests: XCTestCase {
    private func entry(rawText: String, text: String? = nil, wordCount: Int? = nil) -> HistoryEntry {
        HistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            text: text ?? rawText,
            rawText: rawText,
            isPolished: text != nil && text != rawText,
            modeName: "Clean",
            wordCount: wordCount,
            sourceApp: nil,
            durationMs: nil,
            flagged: false,
            flagReason: nil
        )
    }

    func testTotalWordsCountsSpokenWordsInRawText() {
        let stats = UsageStatsAggregator.aggregate([entry(rawText: "send bob the report")])

        XCTAssertEqual(stats.totalWords, 4)
    }

    func testTotalWordsSumsAcrossEntries() {
        let entries = [
            entry(rawText: "one two three"),
            entry(rawText: "four five"),
            entry(rawText: "six"),
        ]

        XCTAssertEqual(UsageStatsAggregator.aggregate(entries).totalWords, 6)
    }

    /// The spoken-word basis: an Expanding Mode can grow four spoken words into a
    /// thirty-word email, but total words must reflect what was *said*, so it
    /// reads `rawText`, not the stored polished `wordCount`.
    func testTotalWordsUsesRawTextNotStoredWordCount() {
        let expanded = entry(
            rawText: "send bob the report",
            text: "Dear Bob, please find the quarterly report attached for your review.",
            wordCount: 11
        )

        XCTAssertEqual(UsageStatsAggregator.aggregate([expanded]).totalWords, 4)
    }

    /// A nil stored word count must not skip the row or crash — stats ignore that
    /// field entirely and count the row's `rawText`.
    func testTotalWordsCountsEntryWithNilStoredWordCount() {
        let stats = UsageStatsAggregator.aggregate([entry(rawText: "hello there friend", wordCount: nil)])

        XCTAssertEqual(stats.totalWords, 3)
    }

    func testTotalWordsIsZeroForEmptyHistory() {
        XCTAssertEqual(UsageStatsAggregator.aggregate([]).totalWords, 0)
    }

    /// Leading, trailing, and repeated whitespace collapse to nothing — the same
    /// splitting the pipeline uses when it records `wordCount` — so padding can't
    /// inflate the count.
    func testTotalWordsIgnoresSurroundingAndRepeatedWhitespace() {
        let stats = UsageStatsAggregator.aggregate([entry(rawText: "  spaced   out  words \n")])

        XCTAssertEqual(stats.totalWords, 3)
    }
}
