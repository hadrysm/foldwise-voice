import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class StatsProjectionTests: XCTestCase {
    func testProjectionExcludesOutsideAndFutureWordsFromMonthSummary() throws {
        XCTAssertEqual(try currentMonthProjection().month.spokenWordTotal, 3)
    }

    func testProjectionExcludesOutsideAndFutureSessionsFromActiveDays() throws {
        XCTAssertEqual(try currentMonthProjection().month.activeDays, 1)
    }

    func testProjectionKeepsAllSavedHistoryInLifetimeMetrics() throws {
        XCTAssertEqual(try currentMonthProjection().lifetime.totalWords, 6)
    }

    func testProjectionUsesLocalizedWeekdayOrder() throws {
        XCTAssertEqual(
            try currentMonthProjection().month.weekdays,
            ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        )
    }

    func testProjectionUsesInjectedLocaleForLeadingOffset() throws {
        XCTAssertEqual(try mismatchedLocaleProjection().month.leadingColumnOffset, 2)
    }

    func testProjectionUsesInjectedLocaleForWeekdayOrder() throws {
        XCTAssertEqual(try mismatchedLocaleProjection().month.weekdays.first, "Pon.")
    }

    private func mismatchedLocaleProjection() throws -> StatsProjection {
        let calendar = try calendar(locale: "en_US", timeZone: "UTC")

        return StatsProjection.project(
            .init(entries: [], currentStreak: nil, savingEnabled: true),
            now: try date(2026, 7, 22, 12, calendar: calendar),
            calendar: calendar,
            locale: Locale(identifier: "pl_PL")
        )
    }

    func testProjectionClassifiesDatesAfterTodayAsFuture() throws {
        XCTAssertEqual(
            try currentMonthProjection().month.days.map(\.state).suffix(9),
            Array(repeating: .future, count: 9)
        )
    }

    func testProjectionUsesCurrentMonthDayCount() throws {
        XCTAssertEqual(try currentMonthProjection().month.days.count, 31)
    }

    func testProjectionUsesCurrentMonthLeadingOffset() throws {
        XCTAssertEqual(try currentMonthProjection().month.leadingColumnOffset, 3)
    }

    private func currentMonthProjection() throws -> StatsProjection {
        let calendar = try calendar(locale: "en_US", timeZone: "UTC")
        let now = try date(2026, 7, 22, 12, calendar: calendar)
        let entries = [
            entry(rawText: "one two three", createdAt: try date(2026, 7, 1, 8, calendar: calendar)),
            entry(rawText: "future words", createdAt: try date(2026, 7, 23, 8, calendar: calendar)),
            entry(rawText: "older", createdAt: try date(2026, 6, 30, 8, calendar: calendar)),
        ]

        return StatsProjection.project(
            .init(entries: entries, currentStreak: 3, savingEnabled: true),
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )
    }

    func testProjectionKeepsZeroWordSessionSavedSessionCount() throws {
        XCTAssertEqual(try intensityProjection().month.days[0].savedSessionCount, 1)
    }

    func testProjectionKeepsZeroWordSessionAtZeroWords() throws {
        XCTAssertEqual(try intensityProjection().month.days[0].spokenWords, 0)
    }

    func testProjectionKeepsZeroWordSessionAtNeutralIntensity() throws {
        XCTAssertEqual(try intensityProjection().month.days[0].intensity, .neutral)
    }

    func testProjectionCountsZeroWordSessionAsActiveDay() throws {
        XCTAssertEqual(try intensityProjection().month.activeDays, 10)
    }

    func testProjectionUsesFixedIntensityBands() throws {
        let projection = try intensityProjection()

        XCTAssertEqual(
            projection.month.days.prefix(10).map(\.intensity.rawValue),
            [0, 1, 1, 2, 2, 3, 3, 4, 4, 5]
        )
    }

    private func intensityProjection() throws -> StatsProjection {
        let calendar = try calendar(locale: "en_US", timeZone: "UTC")
        let now = try date(2026, 7, 22, 12, calendar: calendar)
        let wordCounts = [0, 1, 249, 250, 599, 600, 999, 1000, 1599, 1600]
        let entries = try wordCounts.enumerated().map { index, count in
            entry(
                rawText: words(count),
                createdAt: try date(2026, 7, index + 1, 8, calendar: calendar)
            )
        }

        return StatsProjection.project(
            .init(entries: entries, currentStreak: nil, savingEnabled: true),
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )
    }

    func testProjectionResolvesCompleteTimingDetails() throws {
        XCTAssertEqual(
            try timingDays()[0].detailTiming,
            "1 min dictating · about 1 min saved"
        )
    }

    func testProjectionResolvesPartialTimingDetails() throws {
        XCTAssertEqual(
            try timingDays()[1].detailTiming,
            "Timing unavailable for some sessions"
        )
    }

    func testProjectionResolvesUnavailableTimingDetails() throws {
        XCTAssertEqual(try timingDays()[2].detailTiming, "Timing unavailable")
    }

    func testProjectionResolvesNoPositiveSavingDetails() throws {
        XCTAssertEqual(
            try timingDays()[3].detailTiming,
            "1 min dictating · no estimated time saved"
        )
    }

    func testProjectionCombinesSameDayActivityDetails() throws {
        XCTAssertEqual(
            try timingDays()[1].detailActivity,
            "2 spoken words across 2 saved sessions"
        )
    }

    private func timingDays() throws -> [StatsProjection.Day] {
        let calendar = try calendar(locale: "en_US", timeZone: "UTC")
        let now = try date(2026, 7, 22, 12, calendar: calendar)
        let entries = [
            entry(rawText: words(104), createdAt: try date(2026, 7, 1, 8, calendar: calendar), durationMs: 60000),
            entry(rawText: "one", createdAt: try date(2026, 7, 2, 8, calendar: calendar), durationMs: 10000),
            entry(rawText: "two", createdAt: try date(2026, 7, 2, 9, calendar: calendar)),
            entry(rawText: "three", createdAt: try date(2026, 7, 3, 8, calendar: calendar)),
            entry(rawText: words(10), createdAt: try date(2026, 7, 4, 8, calendar: calendar), durationMs: 60000),
        ]

        return StatsProjection.project(
            .init(entries: entries, currentStreak: nil, savingEnabled: true),
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        ).month.days
    }

    func testProjectionProvidesMetricOrder() throws {
        XCTAssertEqual(try emptyProjection().metrics.map(\.title), [
            "Words dictated", "Speaking speed", "Current streak", "Time saved",
        ])
    }

    func testProjectionProvidesSemanticMetricKinds() throws {
        XCTAssertEqual(try emptyProjection().metrics.map(\.kind), [
            .wordsDictated, .speakingSpeed, .currentStreak, .timeSaved,
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

    func testProjectionProvidesEmptyMonthTitle() throws {
        XCTAssertEqual(try emptyProjection().month.title, "July 2026")
    }

    func testProjectionProvidesEmptyMonthSpokenWordSummary() throws {
        XCTAssertEqual(try emptyProjection().month.spokenWordSummary, "0 spoken words")
    }

    func testProjectionProvidesEmptyMonthActiveDaySummary() throws {
        XCTAssertEqual(try emptyProjection().month.activeDaySummary, "0 active days")
    }

    func testProjectionProvidesCalendarAccessibilityLabel() throws {
        XCTAssertEqual(try emptyProjection().month.accessibilityLabel, "July 2026 activity calendar")
    }

    func testProjectionProvidesCalendarAccessibilityValue() throws {
        XCTAssertEqual(try emptyProjection().month.accessibilityValue, "0 spoken words, 0 active days")
    }

    func testProjectionProvidesTodayAccessibilityLabel() throws {
        XCTAssertEqual(
            try emptyProjection().month.days[21].accessibilityLabel,
            "Wednesday, July 22, 2026, today"
        )
    }

    func testProjectionProvidesTodayAccessibilityValue() throws {
        XCTAssertEqual(
            try emptyProjection().month.days[21].accessibilityValue,
            "No dictated words. No saved Dictation sessions"
        )
    }

    func testProjectionProvidesExactLegendLabels() throws {
        XCTAssertEqual(try emptyProjection().month.legendLabels, [
            "None", "1–249", "250–599", "600–999", "1,000–1,599", "1,600+",
        ])
    }

    func testProjectionKeepsFullCalendarForQuietCurrentMonth() throws {
        XCTAssertEqual(try quietMonthProjection().month.days.count, 31)
    }

    func testProjectionReportsNoActiveDaysForQuietCurrentMonth() throws {
        XCTAssertEqual(try quietMonthProjection().month.activeDays, 0)
    }

    func testProjectionReportsNoWordsForQuietCurrentMonth() throws {
        XCTAssertEqual(try quietMonthProjection().month.spokenWordTotal, 0)
    }

    func testProjectionKeepsLifetimeWordsForQuietCurrentMonth() throws {
        XCTAssertEqual(try quietMonthProjection().lifetime.totalWords, 2)
    }

    func testProjectionWithRetainedHistoryAndSavingEnabledProvidesNoNotice() throws {
        XCTAssertEqual(try retainedProjection(savingEnabled: true).notice, .none)
    }

    func testProjectionWithRetainedHistoryAndSavingOffKeepsLifetimeWords() throws {
        XCTAssertEqual(try retainedProjection(savingEnabled: false).lifetime.totalWords, 2)
    }

    func testProjectionWithRetainedHistoryAndSavingOffKeepsCalendarWords() throws {
        XCTAssertEqual(try retainedProjection(savingEnabled: false).month.spokenWordTotal, 2)
    }

    func testProjectionWithRetainedHistoryDoesNotRepeatSavingOffCopy() throws {
        let projection = try retainedProjection(savingEnabled: false)
        let repeatedCopy = projection.metrics.flatMap { [$0.title, $0.value, $0.detail] }
            + projection.month.days.flatMap { [$0.detailActivity, $0.detailTiming].compactMap { $0 } }

        XCTAssertFalse(repeatedCopy.contains { $0.contains("Stats won’t include new dictations") })
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

    func testProjectionUsesPolishWeekdayOrder() throws {
        XCTAssertEqual(try localizedEmptyProjection(locale: "pl_PL").month.weekdays.first, "Pon.")
    }

    func testProjectionUsesPolishMonthTitle() throws {
        XCTAssertEqual(try localizedEmptyProjection(locale: "pl_PL").month.title, "lipiec 2026")
    }

    func testProjectionUsesArabicWeekdayOrder() throws {
        XCTAssertEqual(try localizedEmptyProjection(locale: "ar_SA").month.weekdays.first, "أحد")
    }

    func testProjectionUsesArabicDayDigits() throws {
        XCTAssertEqual(try localizedEmptyProjection(locale: "ar_SA").month.days[21].dayNumber, "٢٢")
    }

    func testProjectionUsesPolishSpokenWordPlural() throws {
        XCTAssertEqual(
            try polishGrammarProjection().month.spokenWordSummary,
            "5 wypowiedzianych słów"
        )
    }

    func testProjectionUsesPolishActiveDayPlural() throws {
        XCTAssertEqual(try polishGrammarProjection().month.activeDaySummary, "2 aktywne dni")
    }

    func testProjectionUsesPolishSavedSessionPlural() throws {
        XCTAssertEqual(
            try polishGrammarProjection().month.days[0].detailActivity,
            "2 wypowiedziane słowa · 2 zapisane sesje"
        )
    }

    func testProjectionUsesPolishLocalizedDuration() throws {
        XCTAssertEqual(
            try polishGrammarProjection().month.days[0].detailTiming,
            "1 godz. dyktowania · brak szacowanego zaoszczędzonego czasu"
        )
    }

    private func polishGrammarProjection() throws -> StatsProjection {
        let calendar = try calendar(locale: "pl_PL", timeZone: "Europe/Warsaw")
        let entries = [
            entry(rawText: "jeden", createdAt: try date(2026, 7, 1, 8, calendar: calendar), durationMs: 1_800_000),
            entry(rawText: "dwa", createdAt: try date(2026, 7, 1, 9, calendar: calendar), durationMs: 1_800_000),
            entry(rawText: "trzy", createdAt: try date(2026, 7, 2, 8, calendar: calendar)),
            entry(rawText: "cztery", createdAt: try date(2026, 7, 2, 9, calendar: calendar)),
            entry(rawText: "pięć", createdAt: try date(2026, 7, 2, 10, calendar: calendar)),
        ]

        return StatsProjection.project(
            .init(entries: entries, currentStreak: 2, savingEnabled: true),
            now: try date(2026, 7, 22, 12, calendar: calendar),
            calendar: calendar,
            locale: Locale(identifier: "pl_PL")
        )
    }

    func testProjectionUsesArabicSpokenWordPlural() throws {
        XCTAssertEqual(
            try arabicGrammarProjection().month.spokenWordSummary,
            "٣ كلمات منطوقة"
        )
    }

    func testProjectionUsesArabicActiveDayPlural() throws {
        XCTAssertEqual(try arabicGrammarProjection().month.activeDaySummary, "١ يوم نشط")
    }

    func testProjectionUsesArabicSavedSessionPlural() throws {
        XCTAssertEqual(
            try arabicGrammarProjection().month.days[0].detailActivity,
            "٣ كلمات منطوقة · ٣ جلسات إملاء محفوظة"
        )
    }

    func testProjectionUsesArabicLegendDigits() throws {
        XCTAssertEqual(try arabicGrammarProjection().month.legendLabels, [
            "None", "١–٢٤٩", "٢٥٠–٥٩٩", "٦٠٠–٩٩٩", "١٬٠٠٠–١٬٥٩٩", "١٬٦٠٠+",
        ])
    }

    private func arabicGrammarProjection() throws -> StatsProjection {
        let calendar = try calendar(locale: "ar_SA", timeZone: "Asia/Riyadh")
        let createdAt = try date(2026, 7, 1, 8, calendar: calendar)
        let entries = [
            entry(rawText: "واحد", createdAt: createdAt),
            entry(rawText: "اثنان", createdAt: createdAt),
            entry(rawText: "ثلاثة", createdAt: createdAt),
        ]

        return StatsProjection.project(
            .init(entries: entries, currentStreak: 1, savingEnabled: true),
            now: try date(2026, 7, 22, 12, calendar: calendar),
            calendar: calendar,
            locale: Locale(identifier: "ar_SA")
        )
    }

    func testProjectionUsesEnglishCompactWordTotal() throws {
        let projection = try localizedProjection(
            locale: "en_US",
            timeZone: "UTC",
            rawText: words(1600)
        )

        XCTAssertEqual(projection.month.days[0].compactSpokenWords, "1.6K")
    }

    func testProjectionUsesPolishCompactWordTotal() throws {
        let projection = try localizedProjection(
            locale: "pl_PL",
            timeZone: "Europe/Warsaw",
            rawText: words(1600)
        )

        XCTAssertEqual(projection.month.days[0].compactSpokenWords, "1,6 tys.")
    }

    func testProjectionUsesArabicCompactWordTotal() throws {
        let projection = try localizedProjection(
            locale: "ar_SA",
            timeZone: "Asia/Riyadh",
            rawText: words(1600)
        )

        XCTAssertEqual(projection.month.days[0].compactSpokenWords, "١٫٦ ألف")
    }

    func testProjectionUsesPolishFullDate() throws {
        let projection = try localizedProjection(
            locale: "pl_PL",
            timeZone: "Europe/Warsaw",
            rawText: "słowo"
        )

        XCTAssertEqual(projection.month.days[0].fullDate, "środa, 1 lipca 2026")
    }

    func testProjectionUsesArabicMonthTitle() throws {
        let projection = try localizedProjection(
            locale: "ar_SA",
            timeZone: "Asia/Riyadh",
            rawText: "كلمة"
        )

        XCTAssertEqual(projection.month.title, "يوليو، ٢٠٢٦ م")
    }

    func testProjectionUsesArabicFullDate() throws {
        let projection = try localizedProjection(
            locale: "ar_SA",
            timeZone: "Asia/Riyadh",
            rawText: "كلمة"
        )

        XCTAssertEqual(projection.month.days[0].fullDate, "الأربعاء، ١ يوليو، ٢٠٢٦")
    }

    func testProjectionUsesPolishNumberGrouping() throws {
        let projection = try localizedProjection(
            locale: "pl_PL",
            timeZone: "Europe/Warsaw",
            rawText: words(16000)
        )

        XCTAssertEqual(projection.month.spokenWordSummary, "16 000 wypowiedzianych słów")
    }

    func testProjectionUsesArabicNumberGrouping() throws {
        let projection = try localizedProjection(
            locale: "ar_SA",
            timeZone: "Asia/Riyadh",
            rawText: words(16000)
        )

        XCTAssertEqual(projection.month.spokenWordSummary, "١٦٬٠٠٠ كلمة منطوقة")
    }

    func testProjectionUsesArabicLocalizedDuration() throws {
        let projection = try localizedProjection(
            locale: "ar_SA",
            timeZone: "Asia/Riyadh",
            rawText: words(10),
            durationMs: 60000
        )

        XCTAssertEqual(
            projection.month.days[0].detailTiming,
            "١ د من الإملاء · لا يوجد وقت موفر مقدر"
        )
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

    func testProjectionKeepsMonthAndYearBoundaryWordsInCurrentMonthSummary() throws {
        XCTAssertEqual(try yearBoundaryProjection().month.spokenWordTotal, 2)
    }

    func testProjectionKeepsMonthAndYearBoundarySessionInActiveDays() throws {
        XCTAssertEqual(try yearBoundaryProjection().month.activeDays, 1)
    }

    func testProjectionKeepsMonthAndYearBoundaryActivityInLifetimeMetrics() throws {
        XCTAssertEqual(try yearBoundaryProjection().lifetime.totalWords, 4)
    }

    private func yearBoundaryProjection() throws -> StatsProjection {
        let calendar = try calendar(locale: "en_US", timeZone: "UTC")
        let entries = [
            entry(rawText: "november", createdAt: try date(2025, 11, 30, 23, calendar: calendar)),
            entry(rawText: "december words", createdAt: try date(2025, 12, 31, 23, calendar: calendar)),
            entry(rawText: "january", createdAt: try date(2026, 1, 1, 0, calendar: calendar)),
        ]

        return StatsProjection.project(
            .init(entries: entries, currentStreak: 1, savingEnabled: true),
            now: try date(2025, 12, 31, 23, calendar: calendar),
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )
    }

    func testProjectionBucketsSessionBeforeDaylightSavingBoundary() throws {
        XCTAssertEqual(try daylightSavingProjection().month.days[6].savedSessionCount, 1)
    }

    func testProjectionBucketsSessionsAfterDaylightSavingBoundary() throws {
        XCTAssertEqual(try daylightSavingProjection().month.days[7].savedSessionCount, 2)
    }

    private func daylightSavingProjection() throws -> StatsProjection {
        let calendar = try calendar(locale: "en_US", timeZone: "America/Los_Angeles")
        let entries = [
            entry(rawText: "before", createdAt: try date(2026, 3, 7, 23, calendar: calendar)),
            entry(rawText: "after", createdAt: try date(2026, 3, 8, 1, calendar: calendar)),
            entry(rawText: "later", createdAt: try date(2026, 3, 8, 23, calendar: calendar)),
        ]

        return StatsProjection.project(
            .init(entries: entries, currentStreak: 2, savingEnabled: true),
            now: try date(2026, 3, 9, 12, calendar: calendar),
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )
    }

    func testStoreReusesSemanticInputAndInvalidatesEnvironmentChanges() throws {
        var currentNow = Date(timeIntervalSince1970: 1_783_512_000)
        let utc = try calendar(locale: "en_US", timeZone: "UTC")
        let warsaw = try calendar(locale: "en_US", timeZone: "Europe/Warsaw")
        let store = PaneProjectionStore()
        let englishUTC = PaneProjectionStore.Environment(
            now: currentNow,
            calendar: utc,
            locale: Locale(identifier: "en_US")
        )

        let initial = store.stats(in: englishUTC)
        let unchanged = store.stats(in: englishUTC)
        store.setSavingEnabled(false)
        let saving = store.stats(in: englishUTC)
        store.setSavingEnabled(true)
        let timeZone = store.stats(in: .init(
            now: currentNow,
            calendar: warsaw,
            locale: Locale(identifier: "en_US")
        ))
        let locale = store.stats(in: .init(
            now: currentNow,
            calendar: utc,
            locale: Locale(identifier: "pl_PL")
        ))
        currentNow = try XCTUnwrap(utc.date(byAdding: .day, value: 1, to: currentNow))
        let day = store.stats(in: .init(
            now: currentNow,
            calendar: utc,
            locale: Locale(identifier: "en_US")
        ))

        XCTAssertEqual(
            [
                initial.generation,
                unchanged.generation,
                saving.generation,
                timeZone.generation,
                locale.generation,
                day.generation,
            ],
            [
                initial.generation,
                initial.generation,
                saving.generation,
                timeZone.generation,
                locale.generation,
                day.generation,
            ]
        )
        XCTAssertEqual(
            Set([
                initial.generation,
                saving.generation,
                timeZone.generation,
                locale.generation,
                day.generation,
            ]).count,
            5
        )
    }

    func testStoreReusesProjectionWhenHistoryPresentationMetadataChanges() throws {
        let utc = try calendar(locale: "en_US", timeZone: "UTC")
        let createdAt = try date(2026, 7, 1, 8, calendar: utc)
        let original = entry(rawText: "spoken words", createdAt: createdAt, durationMs: 1000)
        var updated = original
        updated.text = "Rewritten display text"
        updated.isPolished = true
        updated.modeName = "Email"
        updated.wordCount = 42
        updated.sourceApp = "Notes"
        updated.flagged = true
        updated.flagReason = "Review"
        let store = PaneProjectionStore()
        let environment = PaneProjectionStore.Environment(
            now: createdAt,
            calendar: utc,
            locale: Locale(identifier: "en_US")
        )
        store.setCurrentStreak(1)

        store.setHistoryEntries([original])
        let originalProjection = store.stats(in: environment)
        store.setHistoryEntries([updated])
        let updatedProjection = store.stats(in: environment)

        XCTAssertEqual(originalProjection.generation, updatedProjection.generation)
    }

    func testCacheInvalidatesProjectionWhenRawTranscriptChanges() throws {
        let utc = try calendar(locale: "en_US", timeZone: "UTC")
        let createdAt = try date(2026, 7, 1, 8, calendar: utc)
        let original = entry(rawText: "original", createdAt: createdAt, durationMs: 1000)
        let updated = entry(rawText: "updated", createdAt: createdAt, durationMs: 1000)

        XCTAssertEqual(
            cacheExecutionCount(first: [original], second: [updated], now: createdAt, calendar: utc),
            2
        )
    }

    func testCacheInvalidatesProjectionWhenCreationTimeChanges() throws {
        let utc = try calendar(locale: "en_US", timeZone: "UTC")
        let createdAt = try date(2026, 7, 1, 8, calendar: utc)
        let updatedAt = try date(2026, 7, 2, 8, calendar: utc)
        let original = entry(rawText: "words", createdAt: createdAt, durationMs: 1000)
        let updated = entry(rawText: "words", createdAt: updatedAt, durationMs: 1000)

        XCTAssertEqual(
            cacheExecutionCount(first: [original], second: [updated], now: createdAt, calendar: utc),
            2
        )
    }

    func testCacheInvalidatesProjectionWhenDurationChanges() throws {
        let utc = try calendar(locale: "en_US", timeZone: "UTC")
        let createdAt = try date(2026, 7, 1, 8, calendar: utc)
        let original = entry(rawText: "words", createdAt: createdAt, durationMs: 1000)
        let updated = entry(rawText: "words", createdAt: createdAt, durationMs: 2000)

        XCTAssertEqual(
            cacheExecutionCount(first: [original], second: [updated], now: createdAt, calendar: utc),
            2
        )
    }

    func testCacheInvalidatesProjectionWhenMatchingSessionMultiplicityChanges() throws {
        let utc = try calendar(locale: "en_US", timeZone: "UTC")
        let createdAt = try date(2026, 7, 1, 8, calendar: utc)
        let first = entry(rawText: "words", createdAt: createdAt, durationMs: 1000)
        let second = entry(rawText: "words", createdAt: createdAt, durationMs: 1000)

        XCTAssertEqual(
            cacheExecutionCount(first: [first], second: [first, second], now: createdAt, calendar: utc),
            2
        )
    }

    func testCacheInvalidatesProjectionWhenCurrentStreakChanges() throws {
        let utc = try calendar(locale: "en_US", timeZone: "UTC")
        let createdAt = try date(2026, 7, 1, 8, calendar: utc)
        let saved = entry(rawText: "words", createdAt: createdAt, durationMs: 1000)

        XCTAssertEqual(
            cacheExecutionCount(
                first: [saved],
                second: [saved],
                firstStreak: 1,
                secondStreak: 2,
                now: createdAt,
                calendar: utc
            ),
            2
        )
    }

    private func cacheExecutionCount(
        first: [HistoryEntry],
        second: [HistoryEntry],
        firstStreak: Int? = 1,
        secondStreak: Int? = 1,
        now: Date,
        calendar: Calendar
    ) -> Int {
        let store = PaneProjectionStore()
        let locale = Locale(identifier: "en_US")
        let environment = PaneProjectionStore.Environment(
            now: now,
            calendar: calendar,
            locale: locale
        )

        store.setHistoryEntries(first)
        store.setCurrentStreak(firstStreak)
        let firstProjection = store.stats(in: environment)
        store.setHistoryEntries(second)
        store.setCurrentStreak(secondStreak)
        let secondProjection = store.stats(in: environment)

        return Set([firstProjection.generation, secondProjection.generation]).count
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

    private func quietMonthProjection() throws -> StatsProjection {
        let calendar = try calendar(locale: "en_US", timeZone: "UTC")
        return StatsProjection.project(
            .init(
                entries: [entry(
                    rawText: "older words",
                    createdAt: try date(2026, 6, 30, 8, calendar: calendar)
                )],
                currentStreak: nil,
                savingEnabled: true
            ),
            now: try date(2026, 7, 22, 12, calendar: calendar),
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )
    }

    private func retainedProjection(savingEnabled: Bool) throws -> StatsProjection {
        let calendar = try calendar(locale: "en_US", timeZone: "UTC")
        return StatsProjection.project(
            .init(
                entries: [entry(
                    rawText: "saved words",
                    createdAt: try date(2026, 7, 1, 8, calendar: calendar)
                )],
                currentStreak: 1,
                savingEnabled: savingEnabled
            ),
            now: try date(2026, 7, 22, 12, calendar: calendar),
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )
    }

    private func localizedProjection(
        locale identifier: String,
        timeZone: String,
        rawText: String,
        durationMs: Int? = nil
    ) throws -> StatsProjection {
        let calendar = try calendar(locale: identifier, timeZone: timeZone)
        return StatsProjection.project(
            .init(
                entries: [entry(
                    rawText: rawText,
                    createdAt: try date(2026, 7, 1, 8, calendar: calendar),
                    durationMs: durationMs
                )],
                currentStreak: 1,
                savingEnabled: true
            ),
            now: try date(2026, 7, 22, 12, calendar: calendar),
            calendar: calendar,
            locale: Locale(identifier: identifier)
        )
    }

    private func localizedEmptyProjection(locale identifier: String) throws -> StatsProjection {
        let timeZone = switch identifier {
        case "pl_PL": "Europe/Warsaw"
        case "ar_SA": "Asia/Riyadh"
        default: "UTC"
        }
        let calendar = try calendar(locale: identifier, timeZone: timeZone)
        return StatsProjection.project(
            .init(entries: [], currentStreak: nil, savingEnabled: true),
            now: try date(2026, 7, 22, 12, calendar: calendar),
            calendar: calendar,
            locale: Locale(identifier: identifier)
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
