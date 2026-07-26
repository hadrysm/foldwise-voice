import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class PaneProjectionStoreTests: XCTestCase {
    func testUnchangedRevisitReusesEveryCompletedProjection() {
        let store = PaneProjectionStore()
        let environment = makeEnvironment()

        let first = resolveEveryPane(store, environment: environment)
        let revisit = resolveEveryPane(store, environment: environment)

        XCTAssertEqual(first.map(\.generation), revisit.map(\.generation))
    }

    func testTenThousandSessionRevisitReusesEveryCompletedProjection() throws {
        let (store, _) = try makeTenThousandStore()
        let environment = makeEnvironment()

        let first = resolveEveryPane(store, environment: environment)
        let revisit = resolveEveryPane(store, environment: environment)

        XCTAssertEqual(first.map(\.generation), revisit.map(\.generation))
    }

    func testTenThousandSessionStorePreservesHomeAndHistoryOrdering() throws {
        let (store, fixture) = try makeTenThousandStore()
        let environment = makeEnvironment()
        let home = store.home(in: environment)
        let history = store.history(search: "", flaggedOnly: false, in: environment)

        XCTAssertEqual(
            [
                home.value.recent.sections.flatMap(\.rows).first?.entry.id,
                history.value.sections.flatMap(\.rows).first?.entry.id,
                history.value.sections.flatMap(\.rows).last?.entry.id,
            ],
            [fixture.entries.first?.id, fixture.entries.first?.id, fixture.entries.last?.id]
        )
    }

    func testTenThousandSessionStoreProjectsRequiredCollectionSizes() throws {
        let (store, _) = try makeTenThousandStore()
        let environment = makeEnvironment()
        let home = store.home(in: environment)
        let history = store.history(search: "", flaggedOnly: false, in: environment)

        XCTAssertEqual(
            [
                home.value.recent.sections.flatMap(\.rows).count,
                history.value.sections.flatMap(\.rows).count,
            ],
            [10, 10000]
        )
    }

    func testTenThousandSessionStorePreservesLifetimeMetrics() throws {
        let (store, _) = try makeTenThousandStore()
        let environment = makeEnvironment()
        let home = store.home(in: environment)
        let stats = store.stats(in: environment)

        XCTAssertEqual(
            [home.value.usage.totalWords, stats.value.lifetime.totalWords],
            [354_984, 354_984]
        )
    }

    func testTenThousandSessionStorePreservesStatsNotice() throws {
        let (store, _) = try makeTenThousandStore()

        let stats = store.stats(in: makeEnvironment())

        XCTAssertEqual(stats.value.notice, .none)
    }

    func testTenThousandSessionStorePreservesModeAccessibilityAttribution() throws {
        let (store, _) = try makeTenThousandStore()

        let history = store.history(
            search: "",
            flaggedOnly: false,
            in: makeEnvironment()
        )

        XCTAssertTrue(
            history.value.sections
                .flatMap(\.rows)[0]
                .presentation.accessibilityDescription
                .contains("Mode Performance Mode")
        )
    }

    func testModeChangeInvalidatesHomeAndHistoryButKeepsStats() {
        let store = PaneProjectionStore()
        let environment = makeEnvironment()
        let before = resolveEveryPane(store, environment: environment)
        let mode = Mode(
            name: "Email",
            asrModel: "",
            llmModel: "local",
            systemPrompt: "Rewrite as email",
            vocab: []
        )

        store.setModes([mode])
        let after = resolveEveryPane(store, environment: environment)

        XCTAssertEqual(
            changed(before, after),
            [true, true, false]
        )
    }

    func testDisplayedTextChangeInvalidatesHomeAndHistoryButKeepsStats() {
        let store = PaneProjectionStore()
        let environment = makeEnvironment()
        var entry = makeEntry(text: "Original", rawText: "spoken words")
        store.setHistoryEntries([entry])
        let before = resolveEveryPane(store, environment: environment)

        entry.text = "Edited"
        store.setHistoryEntries([entry])
        let after = resolveEveryPane(store, environment: environment)

        XCTAssertEqual(changed(before, after), [true, true, false])
    }

    func testCurrentStreakChangeInvalidatesHomeAndStatsButKeepsHistory() {
        let store = PaneProjectionStore()
        let environment = makeEnvironment()
        let before = resolveEveryPane(store, environment: environment)

        store.setCurrentStreak(4)
        let after = resolveEveryPane(store, environment: environment)

        XCTAssertEqual(changed(before, after), [true, false, true])
    }

    func testSavingChangeInvalidatesOnlyStats() {
        let store = PaneProjectionStore()
        let environment = makeEnvironment()
        let before = resolveEveryPane(store, environment: environment)

        store.setSavingEnabled(false)
        let after = resolveEveryPane(store, environment: environment)

        XCTAssertEqual(changed(before, after), [false, false, true])
    }

    func testHistoryKeepsDefaultProjectionAcrossDisposableFilterState() {
        let store = PaneProjectionStore()
        let environment = makeEnvironment()

        let first = store.history(search: "", flaggedOnly: false, in: environment)
        let filtered = store.history(search: "memo", flaggedOnly: false, in: environment)
        let revisit = store.history(search: "", flaggedOnly: false, in: environment)

        XCTAssertEqual(
            [first.generation == revisit.generation, first.generation == filtered.generation],
            [true, false]
        )
    }

    func testEnvironmentKeySelectivelyInvalidatesDayTimeZoneAndLocale() throws {
        let store = PaneProjectionStore()
        let environment = makeEnvironment()
        let initial = resolveEveryPane(store, environment: environment)
        var warsawCalendar = environment.calendar
        warsawCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Warsaw"))

        let timeZone = resolveEveryPane(
            store,
            environment: .init(
                now: environment.now,
                calendar: warsawCalendar,
                locale: environment.locale
            )
        )
        let locale = resolveEveryPane(
            store,
            environment: .init(
                now: environment.now,
                calendar: warsawCalendar,
                locale: Locale(identifier: "pl_PL")
            )
        )
        let nextDay = resolveEveryPane(
            store,
            environment: .init(
                now: environment.now.addingTimeInterval(24 * 60 * 60),
                calendar: warsawCalendar,
                locale: Locale(identifier: "pl_PL")
            )
        )

        XCTAssertEqual(
            [
                changed(initial, timeZone),
                changed(timeZone, locale),
                changed(locale, nextDay),
            ],
            [
                [true, true, true],
                [true, true, true],
                [true, true, true],
            ]
        )
    }

    func testWeekLayoutChangeInvalidatesOnlyStats() {
        let store = PaneProjectionStore()
        let environment = makeEnvironment()
        let initial = resolveEveryPane(store, environment: environment)
        var mondayCalendar = environment.calendar
        mondayCalendar.firstWeekday = 2
        mondayCalendar.minimumDaysInFirstWeek = 4

        let changedWeekLayout = resolveEveryPane(
            store,
            environment: .init(
                now: environment.now,
                calendar: mondayCalendar,
                locale: environment.locale
            )
        )

        XCTAssertEqual(changed(initial, changedWeekLayout), [false, false, true])
    }

    private struct PaneResult {
        let generation: PaneProjectionStore.Generation
    }

    private func makeEnvironment() -> PaneProjectionStore.Environment {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return .init(
            now: Date(timeIntervalSince1970: 1_783_075_200),
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )
    }

    private func makeEntry(text: String, rawText: String) -> HistoryEntry {
        HistoryEntry(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            text: text,
            rawText: rawText,
            isPolished: text != rawText,
            modeName: "Voice to Text",
            modeID: nil,
            wordCount: nil,
            sourceApp: nil,
            durationMs: 2000,
            flagged: false,
            flagReason: nil
        )
    }

    private func makeTenThousandStore() throws -> (
        store: PaneProjectionStore,
        fixture: PanePerformanceFixture
    ) {
        let store = PaneProjectionStore()
        let fixture = PanePerformanceFixture(profile: .tenThousand)
        let performanceModeID = try XCTUnwrap(ModeID(
            rawValue: "11111111-1111-4111-8111-111111111111"
        ))
        store.setModes([Mode(
            id: performanceModeID,
            name: "Performance Mode",
            icon: "waveform",
            asrModel: ASRModelCatalog.defaultID,
            llmModel: "local",
            transformation: .inPlace,
            systemPrompt: "Prompt",
            vocabulary: []
        )])
        store.setHistoryEntries(fixture.entries)
        return (store, fixture)
    }

    private func resolveEveryPane(
        _ store: PaneProjectionStore,
        environment: PaneProjectionStore.Environment
    ) -> [PaneResult] {
        let home = store.home(in: environment)
        let history = store.history(search: "", flaggedOnly: false, in: environment)
        let stats = store.stats(in: environment)
        return results(home: home, history: history, stats: stats)
    }

    private func results(
        home: PaneProjectionStore.Completed<PaneProjectionStore.HomeValue>,
        history: PaneProjectionStore.Completed<HistoryProjection>,
        stats: PaneProjectionStore.Completed<StatsProjection>
    ) -> [PaneResult] {
        [
            PaneResult(generation: home.generation),
            PaneResult(generation: history.generation),
            PaneResult(generation: stats.generation),
        ]
    }

    private func changed(_ before: [PaneResult], _ after: [PaneResult]) -> [Bool] {
        zip(before, after).map { $0.generation != $1.generation }
    }
}
