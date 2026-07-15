import XCTest
@testable import FoldWiseVoiceKit

final class HistoryProjectionTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    private let now = Date(timeIntervalSince1970: 1_783_512_000)

    func testProjectionSearchesBothTextsFiltersFlagsAndOrdersNewestFirst() {
        let newest = entry(
            text: "Quarterly summary", rawText: "um quarterly summary",
            minutesAgo: 5, flagged: true
        )
        let olderMatch = entry(
            text: "Older result", rawText: "quarterly source",
            minutesAgo: 30, flagged: true
        )
        let unflaggedMatch = entry(
            text: "Quarterly draft", rawText: "quarterly draft",
            minutesAgo: 1, flagged: false
        )

        let projection = HistoryProjection.project(
            .init(
                entries: [olderMatch, unflaggedMatch, newest],
                search: "QUARTERLY",
                flaggedOnly: true
            ),
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(
            projection.sections.flatMap(\.rows).map(\.entry),
            [newest, olderMatch]
        )
    }

    func testProjectionGroupsIntoTodayYesterdayAndAbsoluteDays() {
        let today = entry(
            text: "today", rawText: "today", minutesAgo: 60, flagged: false
        )
        let yesterday = entry(
            text: "yesterday", rawText: "yesterday", minutesAgo: 60 * 24, flagged: false
        )
        let older = entry(
            text: "older", rawText: "older", minutesAgo: 60 * 24 * 3, flagged: false
        )

        let projection = project([older, today, yesterday])

        XCTAssertEqual(projection.sections.map(\.header), ["Today", "Yesterday", "Jul 5, 2026"])
    }

    func testProjectionRetainsSharedPresentationBesideExactSource() {
        let today = entry(
            text: "today", rawText: "today", minutesAgo: 60, flagged: false
        )

        let row = project([today]).sections.first?.rows.first

        XCTAssertEqual(row, HistoryProjection.Row(
            entry: today,
            presentation: DictationRowPresentation(entry: today, calendar: calendar)
        ))
    }

    func testBlankSearchProjectsEveryEntry() {
        let source = entry(
            text: "one", rawText: "one", minutesAgo: 1, flagged: false
        )

        XCTAssertEqual(project([source], search: "   ").sections.first?.rows.map(\.entry), [source])
    }

    func testEmptyInputProjectsEmpty() {
        XCTAssertTrue(project([]).isEmpty)
    }

    func testCacheExecutesOnlyWhenEntriesSearchOrFlaggedOnlyChanges() {
        let source = entry(
            text: "one", rawText: "one", minutesAgo: 1, flagged: false
        )
        let added = entry(
            text: "two", rawText: "two", minutesAgo: 2, flagged: true
        )
        var executionCount = 0
        let cache = HistoryProjectionCache { input in
            executionCount += 1
            return HistoryProjection.project(
                input,
                now: self.now,
                calendar: self.calendar,
                locale: Locale(identifier: "en_US")
            )
        }
        let initial = HistoryProjection.Input(
            entries: [source], search: "", flaggedOnly: false
        )

        _ = cache.resolve(initial)
        _ = cache.resolve(initial)
        _ = cache.resolve(.init(entries: [source, added], search: "", flaggedOnly: false))
        _ = cache.resolve(.init(entries: [source, added], search: "two", flaggedOnly: false))
        _ = cache.resolve(.init(entries: [source, added], search: "two", flaggedOnly: true))

        XCTAssertEqual(executionCount, 4)
    }

    func testCacheInvalidatesWhenTheCalendarDayChanges() throws {
        var currentNow = now
        let source = entry(
            text: "one", rawText: "one", minutesAgo: 60, flagged: false
        )
        let input = HistoryProjection.Input(
            entries: [source], search: "", flaggedOnly: false
        )
        let cache = HistoryProjectionCache(
            now: { currentNow },
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )

        let beforeMidnight = cache.resolve(input)
        currentNow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: currentNow))
        let afterMidnight = cache.resolve(input)

        XCTAssertEqual(beforeMidnight.sections.map(\.header), ["Today"])
        XCTAssertEqual(afterMidnight.sections.map(\.header), ["Yesterday"])
    }

    private func project(
        _ entries: [HistoryEntry],
        search: String = "",
        flaggedOnly: Bool = false
    ) -> HistoryProjection {
        HistoryProjection.project(
            .init(entries: entries, search: search, flaggedOnly: flaggedOnly),
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )
    }

    private func entry(
        text: String,
        rawText: String,
        minutesAgo: Double,
        flagged: Bool
    ) -> HistoryEntry {
        HistoryEntry(
            id: UUID(),
            createdAt: now.addingTimeInterval(-minutesAgo * 60),
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
}
