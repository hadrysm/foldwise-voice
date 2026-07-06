// The History pane's search and Flagged-only filter, exercised through the
// pure HistoryFilter helper the (untested) SwiftUI view calls. Search is a
// case-insensitive substring match over both the polished text and the raw
// transcript; Flagged-only narrows to bookmarked rows; the two compose.

import XCTest
@testable import FoldWiseVoiceKit

final class HistoryFilterTests: XCTestCase {
    private func entry(
        text: String, rawText: String, flagged: Bool = false
    ) -> HistoryEntry {
        HistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            text: text,
            rawText: rawText,
            isPolished: text != rawText,
            modeName: "Clean",
            wordCount: nil,
            sourceApp: nil,
            durationMs: nil,
            flagged: flagged,
            flagReason: nil
        )
    }

    func testBlankQueryMatchesEveryEntry() {
        let entries = [entry(text: "one", rawText: "one"), entry(text: "two", rawText: "two")]

        XCTAssertEqual(
            HistoryFilter.apply(to: entries, query: "", flaggedOnly: false), entries
        )
    }

    func testWhitespaceOnlyQueryMatchesEveryEntry() {
        let entries = [entry(text: "one", rawText: "one")]

        XCTAssertEqual(
            HistoryFilter.apply(to: entries, query: "   ", flaggedOnly: false), entries
        )
    }

    func testSearchMatchesPolishedText() {
        let hit = entry(text: "Dear team, please review", rawText: "dear team please review")
        let miss = entry(text: "grocery list", rawText: "grocery list")

        XCTAssertEqual(
            HistoryFilter.apply(to: [hit, miss], query: "review", flaggedOnly: false), [hit]
        )
    }

    func testSearchMatchesRawTextEvenWhenPolishRephrased() {
        // The polished text dropped the word "um"; searching for it still finds
        // the row via the raw transcript.
        let hit = entry(text: "Let us proceed", rawText: "um let us proceed")
        let miss = entry(text: "totally unrelated", rawText: "totally unrelated")

        XCTAssertEqual(
            HistoryFilter.apply(to: [hit, miss], query: "um", flaggedOnly: false), [hit]
        )
    }

    func testSearchIsCaseInsensitive() {
        let hit = entry(text: "Quarterly Report", rawText: "quarterly report")

        XCTAssertEqual(
            HistoryFilter.apply(to: [hit], query: "QUARTERLY", flaggedOnly: false), [hit]
        )
    }

    func testFlaggedOnlyNarrowsToFlaggedEntries() {
        let flagged = entry(text: "keep this", rawText: "keep this", flagged: true)
        let unflagged = entry(text: "ignore this", rawText: "ignore this", flagged: false)

        XCTAssertEqual(
            HistoryFilter.apply(to: [flagged, unflagged], query: "", flaggedOnly: true),
            [flagged]
        )
    }

    func testFlaggedOnlyAndSearchCompose() {
        let match = entry(text: "budget draft", rawText: "budget draft", flagged: true)
        let flaggedButNoMatch = entry(text: "lunch plans", rawText: "lunch plans", flagged: true)
        let matchButUnflagged = entry(text: "budget final", rawText: "budget final", flagged: false)

        XCTAssertEqual(
            HistoryFilter.apply(
                to: [match, flaggedButNoMatch, matchButUnflagged],
                query: "budget",
                flaggedOnly: true
            ),
            [match]
        )
    }

    func testFilterPreservesInputOrder() {
        let first = entry(text: "alpha term", rawText: "alpha term")
        let second = entry(text: "beta term", rawText: "beta term")
        let third = entry(text: "gamma term", rawText: "gamma term")

        XCTAssertEqual(
            HistoryFilter.apply(to: [first, second, third], query: "term", flaggedOnly: false),
            [first, second, third]
        )
    }
}
