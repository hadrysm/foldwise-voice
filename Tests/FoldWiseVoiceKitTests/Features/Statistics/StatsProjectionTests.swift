import XCTest
@testable import FoldWiseVoiceKit

final class StatsProjectionTests: XCTestCase {
    func testProjectionBuildsCurrentMonthAndExcludesFutureActivityFromMonthSummary() throws {
        let calendar = try calendar(locale: "en_US", timeZone: "UTC")
        let now = try date(2026, 7, 22, 12, calendar: calendar)
        let entries = [
            entry(rawText: "one two three", createdAt: try date(2026, 7, 1, 8, calendar: calendar)),
            entry(rawText: "future words", createdAt: try date(2026, 7, 23, 8, calendar: calendar)),
            entry(rawText: "older", createdAt: try date(2026, 6, 30, 8, calendar: calendar)),
        ]

        let projection = StatsProjection.project(
            .init(entries: entries, currentStreak: 3, savingEnabled: true),
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(
            [
                projection.month.days.count,
                projection.month.leadingColumnOffset,
                projection.month.spokenWordTotal,
                projection.month.activeDays,
                projection.lifetime.totalWords,
            ],
            [31, 3, 3, 1, 6]
        )
        XCTAssertEqual(projection.month.weekdays, ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
        XCTAssertEqual(projection.month.days.map(\.state).suffix(9), Array(repeating: .future, count: 9))
    }

    func testProjectionKeepsZeroWordSessionActiveAndUsesFixedIntensityBands() throws {
        let calendar = try calendar(locale: "en_US", timeZone: "UTC")
        let now = try date(2026, 7, 22, 12, calendar: calendar)
        let wordCounts = [0, 1, 249, 250, 599, 600, 999, 1000, 1599, 1600]
        let entries = try wordCounts.enumerated().map { index, count in
            entry(
                rawText: words(count),
                createdAt: try date(2026, 7, index + 1, 8, calendar: calendar)
            )
        }

        let projection = StatsProjection.project(
            .init(entries: entries, currentStreak: nil, savingEnabled: true),
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(
            projection.month.days.prefix(wordCounts.count).map {
                [$0.savedSessionCount, $0.spokenWords, $0.intensity.rawValue]
            },
            [
                [1, 0, 0], [1, 1, 1], [1, 249, 1], [1, 250, 2], [1, 599, 2],
                [1, 600, 3], [1, 999, 3], [1, 1000, 4], [1, 1599, 4], [1, 1600, 5],
            ]
        )
        XCTAssertEqual(projection.month.activeDays, 10)
    }

    func testProjectionResolvesCompletePartialUnavailableAndNoSavingDetails() throws {
        let calendar = try calendar(locale: "en_US", timeZone: "UTC")
        let now = try date(2026, 7, 22, 12, calendar: calendar)
        let entries = [
            entry(rawText: words(104), createdAt: try date(2026, 7, 1, 8, calendar: calendar), durationMs: 60000),
            entry(rawText: "one", createdAt: try date(2026, 7, 2, 8, calendar: calendar), durationMs: 10000),
            entry(rawText: "two", createdAt: try date(2026, 7, 2, 9, calendar: calendar)),
            entry(rawText: "three", createdAt: try date(2026, 7, 3, 8, calendar: calendar)),
            entry(rawText: words(10), createdAt: try date(2026, 7, 4, 8, calendar: calendar), durationMs: 60000),
        ]

        let days = StatsProjection.project(
            .init(entries: entries, currentStreak: nil, savingEnabled: true),
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        ).month.days

        XCTAssertEqual(
            days.prefix(4).map(\.detailTiming),
            [
                "1 min dictating · about 1 min saved",
                "Timing unavailable for some sessions",
                "Timing unavailable",
                "1 min dictating · no estimated time saved",
            ]
        )
        XCTAssertEqual(days[1].detailActivity, "2 spoken words across 2 saved sessions")
    }

    func testProjectionProvidesMetricOrder() throws {
        XCTAssertEqual(try emptyProjection().metrics.map(\.title), [
            "Words dictated", "Speaking speed", "Current streak", "Time saved",
        ])
    }

    func testProjectionProvidesEmptyMetricValues() throws {
        XCTAssertEqual(try emptyProjection().metrics.map(\.value), ["0", "—", "—", "—"])
    }

    func testProjectionProvidesNoHistoryNotice() throws {
        XCTAssertEqual(
            try emptyProjection().notice,
            .noHistory("No stats yet — your activity will appear after your first saved dictation.")
        )
    }

    func testProjectionProvidesEmptyMonthSummary() throws {
        let projection = try emptyProjection()
        XCTAssertEqual(projection.month.title, "July 2026")
        XCTAssertEqual(projection.month.spokenWordSummary, "0 spoken words")
        XCTAssertEqual(projection.month.activeDaySummary, "0 active days")
    }

    func testProjectionProvidesCalendarAccessibilityContext() throws {
        let projection = try emptyProjection()
        XCTAssertEqual(
            [projection.month.accessibilityLabel, projection.month.accessibilityValue],
            ["July 2026 activity calendar", "0 spoken words, 0 active days"]
        )
    }

    func testProjectionProvidesTodayAccessibilityCopy() throws {
        let today = try emptyProjection().month.days[21]
        XCTAssertEqual(
            [today.accessibilityLabel, today.accessibilityValue],
            ["Wednesday, July 22, 2026, today", "No dictated words. No saved Dictation sessions"]
        )
    }

    func testProjectionProvidesExactLegendLabels() throws {
        XCTAssertEqual(try emptyProjection().month.legendLabels, [
            "None", "1–249", "250–599", "600–999", "1,000–1,599", "1,600+",
        ])
    }

    func testProjectionSavingOffNoticeReplacesNoHistoryNotice() throws {
        let calendar = try calendar(locale: "en_US", timeZone: "UTC")

        let projection = StatsProjection.project(
            .init(entries: [], currentStreak: nil, savingEnabled: false),
            now: try date(2026, 7, 22, 12, calendar: calendar),
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(
            projection.notice,
            .savingOff(
                message: "Saving is off — Stats won’t include new dictations. Turn it on in History.",
                actionTitle: "Open History"
            )
        )
    }

    func testProjectionUsesInjectedLocaleForWeekdayOrderAndFormattedDigits() throws {
        let polishCalendar = try calendar(locale: "pl_PL", timeZone: "Europe/Warsaw")
        let arabicCalendar = try calendar(locale: "ar_SA", timeZone: "Asia/Riyadh")
        let polish = StatsProjection.project(
            .init(entries: [], currentStreak: nil, savingEnabled: true),
            now: try date(2026, 7, 22, 12, calendar: polishCalendar),
            calendar: polishCalendar,
            locale: Locale(identifier: "pl_PL")
        )
        let arabic = StatsProjection.project(
            .init(entries: [], currentStreak: nil, savingEnabled: true),
            now: try date(2026, 7, 22, 12, calendar: arabicCalendar),
            calendar: arabicCalendar,
            locale: Locale(identifier: "ar_SA")
        )

        XCTAssertEqual(
            [
                polish.month.weekdays.first,
                polish.month.title,
                arabic.month.weekdays.first,
                arabic.month.days[21].dayNumber,
            ],
            ["Pon.", "lipiec 2026", "أحد", "٢٢"]
        )
    }

    func testProjectionUsesPolishPluralCategoriesAndLocalizedDuration() throws {
        let calendar = try calendar(locale: "pl_PL", timeZone: "Europe/Warsaw")
        let entries = [
            entry(rawText: "jeden", createdAt: try date(2026, 7, 1, 8, calendar: calendar), durationMs: 1_800_000),
            entry(rawText: "dwa", createdAt: try date(2026, 7, 1, 9, calendar: calendar), durationMs: 1_800_000),
            entry(rawText: "trzy", createdAt: try date(2026, 7, 2, 8, calendar: calendar)),
            entry(rawText: "cztery", createdAt: try date(2026, 7, 2, 9, calendar: calendar)),
            entry(rawText: "pięć", createdAt: try date(2026, 7, 2, 10, calendar: calendar)),
        ]

        let projection = StatsProjection.project(
            .init(entries: entries, currentStreak: 2, savingEnabled: true),
            now: try date(2026, 7, 22, 12, calendar: calendar),
            calendar: calendar,
            locale: Locale(identifier: "pl_PL")
        )

        XCTAssertEqual(projection.month.spokenWordSummary, "5 wypowiedzianych słów")
        XCTAssertEqual(projection.month.activeDaySummary, "2 aktywne dni")
        XCTAssertEqual(projection.month.days[0].detailActivity, "2 wypowiedziane słowa · 2 zapisane sesje")
        XCTAssertEqual(
            projection.month.days[0].detailTiming,
            "1 godz. dyktowania · brak szacowanego zaoszczędzonego czasu"
        )
    }

    func testProjectionUsesArabicPluralCategoriesAndLocalizedLegendDigits() throws {
        let calendar = try calendar(locale: "ar_SA", timeZone: "Asia/Riyadh")
        let createdAt = try date(2026, 7, 1, 8, calendar: calendar)
        let entries = [
            entry(rawText: "واحد", createdAt: createdAt),
            entry(rawText: "اثنان", createdAt: createdAt),
            entry(rawText: "ثلاثة", createdAt: createdAt),
        ]

        let projection = StatsProjection.project(
            .init(entries: entries, currentStreak: 1, savingEnabled: true),
            now: try date(2026, 7, 22, 12, calendar: calendar),
            calendar: calendar,
            locale: Locale(identifier: "ar_SA")
        )

        XCTAssertEqual(projection.month.spokenWordSummary, "٣ كلمات منطوقة")
        XCTAssertEqual(projection.month.activeDaySummary, "١ يوم نشط")
        XCTAssertEqual(projection.month.days[0].detailActivity, "٣ كلمات منطوقة · ٣ جلسات إملاء محفوظة")
        XCTAssertEqual(projection.month.legendLabels, [
            "None", "١–٢٤٩", "٢٥٠–٥٩٩", "٦٠٠–٩٩٩", "١٬٠٠٠–١٬٥٩٩", "١٬٦٠٠+",
        ])
    }

    func testProjectionProducesEveryRealDayAcrossMonthLengthsAndLeapYear() throws {
        let calendar = try calendar(locale: "en_US", timeZone: "UTC")
        let inputs = [(2024, 2), (2025, 2), (2026, 4), (2026, 7)]
        let counts = try inputs.map { year, month in
            StatsProjection.project(
                .init(entries: [], currentStreak: nil, savingEnabled: true),
                now: try date(year, month, 15, 12, calendar: calendar),
                calendar: calendar,
                locale: Locale(identifier: "en_US")
            ).month.days.count
        }

        XCTAssertEqual(counts, [29, 28, 30, 31])
    }

    func testProjectionProducesAllSevenLeadingOffsets() throws {
        let calendar = try calendar(locale: "en_US", timeZone: "UTC")
        let offsets = try (1 ... 12).map { month in
            StatsProjection.project(
                .init(entries: [], currentStreak: nil, savingEnabled: true),
                now: try date(2026, month, 15, 12, calendar: calendar),
                calendar: calendar,
                locale: Locale(identifier: "en_US")
            ).month.leadingColumnOffset
        }

        XCTAssertEqual(Set(offsets), Set(0 ... 6))
    }

    func testProjectionKeepsMonthAndYearBoundaryActivityInItsLocalMonth() throws {
        let calendar = try calendar(locale: "en_US", timeZone: "UTC")
        let entries = [
            entry(rawText: "november", createdAt: try date(2025, 11, 30, 23, calendar: calendar)),
            entry(rawText: "december words", createdAt: try date(2025, 12, 31, 23, calendar: calendar)),
            entry(rawText: "january", createdAt: try date(2026, 1, 1, 0, calendar: calendar)),
        ]

        let projection = StatsProjection.project(
            .init(entries: entries, currentStreak: 1, savingEnabled: true),
            now: try date(2025, 12, 31, 23, calendar: calendar),
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(projection.month.spokenWordTotal, 2)
        XCTAssertEqual(projection.month.activeDays, 1)
        XCTAssertEqual(projection.lifetime.totalWords, 4)
    }

    func testProjectionBucketsSessionsAcrossDaylightSavingBoundary() throws {
        let calendar = try calendar(locale: "en_US", timeZone: "America/Los_Angeles")
        let entries = [
            entry(rawText: "before", createdAt: try date(2026, 3, 7, 23, calendar: calendar)),
            entry(rawText: "after", createdAt: try date(2026, 3, 8, 1, calendar: calendar)),
            entry(rawText: "later", createdAt: try date(2026, 3, 8, 23, calendar: calendar)),
        ]

        let projection = StatsProjection.project(
            .init(entries: entries, currentStreak: 2, savingEnabled: true),
            now: try date(2026, 3, 9, 12, calendar: calendar),
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(projection.month.days[6].savedSessionCount, 1)
        XCTAssertEqual(projection.month.days[7].savedSessionCount, 2)
    }

    func testCacheReusesSemanticInputAndInvalidatesEnvironmentChanges() throws {
        var currentNow = Date(timeIntervalSince1970: 1_783_512_000)
        var executionCount = 0
        let utc = try calendar(locale: "en_US", timeZone: "UTC")
        let warsaw = try calendar(locale: "en_US", timeZone: "Europe/Warsaw")
        let input = StatsProjection.Input(entries: [], currentStreak: nil, savingEnabled: true)
        let cache = StatsProjectionCache(now: { currentNow }, project: { input, now, calendar, locale in
            executionCount += 1
            return StatsProjection.project(input, now: now, calendar: calendar, locale: locale)
        })

        _ = cache.resolve(input, calendar: utc, locale: Locale(identifier: "en_US"))
        _ = cache.resolve(input, calendar: utc, locale: Locale(identifier: "en_US"))
        _ = cache.resolve(
            .init(entries: [], currentStreak: nil, savingEnabled: false),
            calendar: utc,
            locale: .init(identifier: "en_US")
        )
        _ = cache.resolve(input, calendar: warsaw, locale: Locale(identifier: "en_US"))
        _ = cache.resolve(input, calendar: utc, locale: Locale(identifier: "pl_PL"))
        currentNow = try XCTUnwrap(utc.date(byAdding: .day, value: 1, to: currentNow))
        _ = cache.resolve(input, calendar: utc, locale: Locale(identifier: "en_US"))

        XCTAssertEqual(executionCount, 5)
    }

    private func calendar(locale: String, timeZone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: locale)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: timeZone))
        return calendar
    }

    private func emptyProjection() throws -> StatsProjection {
        let calendar = try calendar(locale: "en_US", timeZone: "UTC")
        return StatsProjection.project(
            .init(entries: [], currentStreak: nil, savingEnabled: true),
            now: try date(2026, 7, 22, 12, calendar: calendar),
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        calendar: Calendar
    ) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
        )))
    }

    private func entry(rawText: String, createdAt: Date, durationMs: Int? = nil) -> HistoryEntry {
        HistoryEntry(
            id: UUID(),
            createdAt: createdAt,
            text: rawText,
            rawText: rawText,
            isPolished: false,
            modeName: "Clean",
            wordCount: nil,
            sourceApp: nil,
            durationMs: durationMs,
            flagged: false,
            flagReason: nil
        )
    }

    private func words(_ count: Int) -> String {
        Array(repeating: "word", count: count).joined(separator: " ")
    }
}
