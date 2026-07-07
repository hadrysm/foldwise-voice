// The Stats pane's numbers, exercised through the pure UsageStatsAggregator the
// (untested) SwiftUI pane renders over (PRD #97). Alongside total words this
// covers speaking speed and active days: WPM is the aggregate Σ spoken words ÷
// Σ dictation minutes over only the timed entries (never a mean of per-entry
// rates, and nil when nothing is timed); active days is the count of distinct
// calendar days a dictation was recorded on, de-duped by startOfDay through an
// injected Calendar so time zone and DST arithmetic are exercised.

import XCTest
@testable import FoldWiseVoiceKit

final class UsageStatsAggregatorTests: XCTestCase {
    /// Ten distinct spoken words, so word-per-minute fixtures read at a glance.
    private let tenWords = "one two three four five six seven eight nine ten"

    private func entry(
        rawText: String = "one",
        text: String? = nil,
        wordCount: Int? = nil,
        durationMs: Int? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> HistoryEntry {
        HistoryEntry(
            id: UUID(),
            createdAt: createdAt,
            text: text ?? rawText,
            rawText: rawText,
            isPolished: text != nil && text != rawText,
            modeName: "Clean",
            wordCount: wordCount,
            sourceApp: nil,
            durationMs: durationMs,
            flagged: false,
            flagReason: nil
        )
    }

    /// A Gregorian calendar pinned to a fixed zone, so day bucketing does not
    /// depend on where the test happens to run.
    private func calendar(_ zone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        return calendar
    }

    private func day(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, _ hour: Int) throws -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return try XCTUnwrap(calendar.date(from: components))
    }

    // MARK: - Total words

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

    /// An untimed entry is excluded from WPM but must still contribute to total
    /// words — a missing duration can't erase what was spoken.
    func testTotalWordsIncludesUntimedEntry() {
        let entries = [
            entry(rawText: "one two three four five six", durationMs: 60000),
            entry(rawText: "seven eight nine ten"),
        ]

        XCTAssertEqual(UsageStatsAggregator.aggregate(entries).totalWords, 10)
    }

    // MARK: - Speaking speed (WPM)

    /// WPM is the aggregate Σ words ÷ Σ minutes, not a mean of per-entry rates:
    /// 10 words in 1 min (10 wpm) plus 10 words in 4 min (2.5 wpm) is 20 ÷ 5 =
    /// 4 wpm, not the 6.25 wpm the two rates would average to.
    func testWordsPerMinuteIsAggregateNotMeanOfPerEntryRates() throws {
        let entries = [
            entry(rawText: tenWords, durationMs: 60000),
            entry(rawText: tenWords, durationMs: 240_000),
        ]

        let wpm = try XCTUnwrap(UsageStatsAggregator.aggregate(entries).wordsPerMinute)
        XCTAssertEqual(wpm, 4.0, accuracy: 0.0001)
    }

    /// A dictation with no recorded duration is left out of the WPM average, so a
    /// missing duration can't divide by zero or silently drag the rate down.
    func testWordsPerMinuteExcludesUntimedEntry() throws {
        let entries = [
            entry(rawText: "one two three four five six", durationMs: 60000),
            entry(rawText: "seven eight nine ten"),
        ]

        let wpm = try XCTUnwrap(UsageStatsAggregator.aggregate(entries).wordsPerMinute)
        XCTAssertEqual(wpm, 6.0, accuracy: 0.0001)
    }

    /// No timed entry → WPM is nil (the pane renders "—"), never 0.
    func testWordsPerMinuteIsNilWhenNoTimedEntry() {
        let entries = [entry(rawText: "one two three"), entry(rawText: "four five")]

        XCTAssertNil(UsageStatsAggregator.aggregate(entries).wordsPerMinute)
    }

    /// A zero duration is treated as no duration — it must not divide by zero or
    /// produce an infinite rate.
    func testWordsPerMinuteIsNilWhenOnlyZeroDurationEntries() {
        XCTAssertNil(UsageStatsAggregator.aggregate([entry(rawText: "one two three", durationMs: 0)]).wordsPerMinute)
    }

    // MARK: - Active days

    /// Distinct calendar days, de-duped by startOfDay: two dictations on the same
    /// day and one the next day count as two active days.
    func testActiveDaysCountsDistinctCalendarDays() throws {
        let calendar = try calendar("UTC")
        let entries = [
            entry(createdAt: try day(calendar, 2026, 1, 1, 8)),
            entry(createdAt: try day(calendar, 2026, 1, 1, 20)),
            entry(createdAt: try day(calendar, 2026, 1, 2, 3)),
        ]

        XCTAssertEqual(UsageStatsAggregator.aggregate(entries, calendar: calendar).activeDays, 2)
    }

    /// Across the spring-forward DST boundary the day is only 23 hours long; two
    /// instants on that shortened local day must still collapse to one active day
    /// (a naive divide-by-86400 would miscount), plus the following day makes two.
    func testActiveDaysHandlesDaylightSavingBoundary() throws {
        let calendar = try calendar("America/New_York")
        let entries = [
            entry(createdAt: try day(calendar, 2026, 3, 8, 1)), // before the 02:00 jump (EST)
            entry(createdAt: try day(calendar, 2026, 3, 8, 10)), // after the jump (EDT), same day
            entry(createdAt: try day(calendar, 2026, 3, 9, 6)), // the next day
        ]

        XCTAssertEqual(UsageStatsAggregator.aggregate(entries, calendar: calendar).activeDays, 2)
    }

    func testActiveDaysIsZeroForEmptyHistory() {
        XCTAssertEqual(UsageStatsAggregator.aggregate([]).activeDays, 0)
    }
}
