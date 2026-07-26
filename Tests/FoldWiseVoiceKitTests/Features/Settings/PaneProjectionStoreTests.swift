import Observation
import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class PaneProjectionStoreTests: XCTestCase {
    func testHomePreparationPublishesCurrentContentAfterLoading() async {
        let scheduling = ProjectionPreparationScheduling()
        let store = PaneProjectionStore(
            beforePreparation: { pane in
                await scheduling.checkpoint(pane)
            }
        )

        store.prepareHome(in: makeEnvironment())
        let loading = store.homeProjection
        await scheduling.waitUntilStarted(.home)
        await scheduling.resume(.home)
        await waitUntil { store.homeProjection.isCurrent }

        XCTAssertEqual(
            [loading.phase, store.homeProjection.phase],
            [.loading, .current]
        )
    }

    func testSemanticChangeKeepsCompletedHomeVisibleWhileUpdating() async {
        let scheduling = ProjectionPreparationScheduling()
        let store = PaneProjectionStore(
            beforePreparation: { pane in
                await scheduling.checkpoint(pane)
            }
        )
        store.prepareHome(in: makeEnvironment())
        await scheduling.waitUntilStarted(.home, count: 1)
        await scheduling.resume(.home)
        await waitUntil { store.homeProjection.isCurrent }
        let initial = store.homeProjection.completed

        store.setHistoryEntries([makeEntry(text: "Current", rawText: "Current")])
        let updating = store.homeProjection
        guard updating.phase == .updating else {
            XCTFail("Expected completed Home content to remain visible while updating")
            return
        }
        await scheduling.waitUntilStarted(.home, count: 2)
        await scheduling.resume(.home)
        await waitUntil {
            store.homeProjection.isCurrent
                && store.homeProjection.completed != initial
        }

        XCTAssertEqual(
            updating,
            PaneProjectionStore.Projection(
                completed: initial,
                phase: .updating
            )
        )
    }

    func testPrepareAllPublishesEveryPaneAsCurrent() async {
        let scheduling = ProjectionPreparationScheduling()
        let store = PaneProjectionStore(
            beforePreparation: { pane in
                await scheduling.checkpoint(pane)
            }
        )

        store.prepareAll(in: makeEnvironment())
        for pane in [
            PaneProjectionStore.Pane.home,
            .history,
            .stats,
        ] {
            await scheduling.waitUntilStarted(pane)
            await scheduling.resume(pane)
        }
        await waitUntil {
            store.homeProjection.isCurrent
                && store.historyProjection.isCurrent
                && store.statsProjection.isCurrent
        }

        XCTAssertEqual(
            [
                store.homeProjection.phase,
                store.historyProjection.phase,
                store.statsProjection.phase,
            ],
            [.current, .current, .current]
        )
    }

    func testRapidHistoryChangesPublishOnlyLatestCurrentProjection() async {
        let scheduling = ProjectionPreparationScheduling()
        let store = PaneProjectionStore(
            beforePreparation: { pane in
                await scheduling.checkpoint(pane)
            }
        )
        let environment = makeEnvironment()
        store.prepareHistory(search: "", flaggedOnly: false, in: environment)
        await scheduling.waitUntilStarted(.history, count: 1)
        await scheduling.resume(.history)
        await waitUntil { store.historyProjection.isCurrent }

        store.setHistoryEntries([makeEntry(text: "Obsolete", rawText: "Obsolete")])
        await scheduling.waitUntilStarted(.history, count: 2)
        store.setHistoryEntries([makeEntry(text: "Latest", rawText: "Latest")])
        await scheduling.waitUntilStarted(.history, count: 3)
        await scheduling.waitUntilCancelled(.history)
        await scheduling.resume(.history)
        await scheduling.resume(.history)
        await waitUntil { store.historyProjection.isCurrent }

        let projection = store.historyProjection.completed?.value
        let firstRow = projection?.sections.flatMap(\.rows).first

        XCTAssertEqual(
            firstRow.map { projection?.entry(for: $0).text },
            "Latest"
        )
    }

    func testReturningToCachedStatsEnvironmentRejectsObsoletePreparation() async {
        let scheduling = ProjectionPreparationScheduling()
        let store = PaneProjectionStore(
            beforePreparation: { pane in
                await scheduling.checkpoint(pane)
            }
        )
        let currentEnvironment = makeEnvironment()
        let current = store.stats(in: currentEnvironment)
        let obsoleteEnvironment = PaneProjectionStore.Environment(
            now: currentEnvironment.now.addingTimeInterval(24 * 60 * 60),
            calendar: currentEnvironment.calendar,
            locale: Locale(identifier: "pl_PL")
        )

        guard let obsoleteTask = store.prepareStats(in: obsoleteEnvironment) else {
            XCTFail("Expected obsolete Stats preparation task")
            return
        }
        await scheduling.waitUntilStarted(.stats)
        store.prepareStats(in: currentEnvironment)
        await scheduling.waitUntilCancelled(.stats)
        await scheduling.resume(.stats)
        await obsoleteTask.value

        XCTAssertEqual(
            [
                store.statsProjection.completed == current,
                store.statsProjection.isCurrent,
            ],
            [true, true]
        )
    }

    func testFilteredHistoryKeepsDefaultNavigationProjectionPrepared() async {
        let store = PaneProjectionStore()
        let environment = makeEnvironment()
        store.prepareHistory(search: "Current", flaggedOnly: false, in: environment)
        await waitUntil { store.historyProjection.isCurrent }

        store.setHistoryEntries([makeEntry(text: "Current", rawText: "Current")])
        await waitUntil {
            store.historyProjection.isCurrent
                && store.completedDefaultHistory != nil
        }
        store.prepareHistory(search: "", flaggedOnly: false, in: environment)

        XCTAssertTrue(store.historyProjection.isCurrent)
    }

    func testPrepareAllPreservesActiveFilteredHistoryRequest() async {
        let store = PaneProjectionStore()
        let environment = makeEnvironment()
        store.setHistoryEntries([
            makeEntry(text: "Current", rawText: "Current"),
        ])
        store.prepareHistory(
            search: "Current",
            flaggedOnly: false,
            in: environment
        )
        await waitUntil { store.historyProjection.isCurrent }
        let filtered = store.historyProjection.completed

        store.prepareAll(in: environment)

        XCTAssertEqual(store.historyProjection.completed, filtered)
    }

    func testHistoryKeepsCompletedSourceStateWhileRefreshing() {
        let store = PaneProjectionStore()
        let environment = makeEnvironment()
        store.setHistoryEntries([
            makeEntry(text: "Current", rawText: "Current"),
        ])
        _ = store.history(
            search: "",
            flaggedOnly: false,
            in: environment
        )
        store.prepareHistory(
            search: "",
            flaggedOnly: false,
            in: environment
        )

        store.setHistoryEntries([])

        XCTAssertEqual(
            [
                store.historyProjection.phase == .updating,
                store.historyProjection.completed?.value.hasSourceEntries == true,
            ],
            [true, true]
        )
    }

    func testAppendingHistoryPreservesNewestFirstOrdering() throws {
        let store = PaneProjectionStore()
        let environment = makeEnvironment()
        let olderID = try XCTUnwrap(UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"))
        let newerID = try XCTUnwrap(UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc"))
        let older = makeEntry(
            id: olderID,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            text: "Older",
            rawText: "Older"
        )
        let newer = makeEntry(
            id: newerID,
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            text: "Newer",
            rawText: "Newer"
        )
        store.setHistoryEntries([older])
        store.setHistoryEntries([older, newer])
        let appended = store.history(
            search: "",
            flaggedOnly: false,
            in: environment
        )

        XCTAssertEqual(
            appended.value.sections.flatMap(\.rows).map(\.id),
            [newerID, olderID]
        )
    }

    func testReplacingHistoryUpdatesProjectedEntry() throws {
        let store = PaneProjectionStore()
        let environment = makeEnvironment()
        let older = makeEntry(
            id: try XCTUnwrap(UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            text: "Older",
            rawText: "Older"
        )
        var newer = makeEntry(
            id: try XCTUnwrap(UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")),
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            text: "Newer",
            rawText: "Newer"
        )
        store.setHistoryEntries([older, newer])
        _ = store.history(search: "", flaggedOnly: false, in: environment)

        newer.text = "Reprocessed"
        store.setHistoryEntries([older, newer])
        let result = store.history(
            search: "",
            flaggedOnly: false,
            in: environment
        )

        XCTAssertEqual(
            result.value.sections.flatMap(\.rows)
                .map { result.value.entry(for: $0).text },
            ["Reprocessed", "Older"]
        )
    }

    func testDeletingHistoryRemovesProjectedEntry() throws {
        let store = PaneProjectionStore()
        let environment = makeEnvironment()
        let deleted = makeEntry(
            id: try XCTUnwrap(UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")),
            text: "Deleted",
            rawText: "Deleted"
        )
        let retained = makeEntry(
            id: try XCTUnwrap(UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")),
            text: "Retained",
            rawText: "Retained"
        )
        store.setHistoryEntries([deleted, retained])
        _ = store.history(search: "", flaggedOnly: false, in: environment)

        store.setHistoryEntries([retained])
        let result = store.history(
            search: "",
            flaggedOnly: false,
            in: environment
        )

        XCTAssertEqual(
            result.value.sections.flatMap(\.rows).map(\.id),
            [retained.id]
        )
    }

    func testClearingHistoryRemovesSourceEntries() {
        let store = PaneProjectionStore()
        let environment = makeEnvironment()
        store.setHistoryEntries([makeEntry(text: "Saved", rawText: "Saved")])
        _ = store.history(search: "", flaggedOnly: false, in: environment)

        store.setHistoryEntries([])
        let result = store.history(
            search: "",
            flaggedOnly: false,
            in: environment
        )

        XCTAssertFalse(result.value.hasSourceEntries)
    }

    func testReprocessingUpdatesSearchAndFlagFiltering() {
        let store = PaneProjectionStore()
        let environment = makeEnvironment()
        var entry = makeEntry(text: "Before", rawText: "Before")
        store.setHistoryEntries([entry])
        _ = store.history(
            search: "After",
            flaggedOnly: true,
            in: environment
        )

        entry.text = "After"
        entry.flagged = true
        store.setHistoryEntries([entry])
        let result = store.history(
            search: "After",
            flaggedOnly: true,
            in: environment
        )

        XCTAssertEqual(
            result.value.sections.flatMap(\.rows)
                .map { result.value.entry(for: $0) },
            [entry]
        )
    }

    func testModeRenameUpdatesHistoryAttribution() {
        let store = PaneProjectionStore()
        let environment = makeEnvironment()
        let modeID = ModeID.random()
        var entry = makeEntry(text: "Saved", rawText: "Saved")
        entry.modeID = modeID
        entry.modeName = "Recorded"
        let original = makeMode(id: modeID, name: "Original", icon: "pencil")
        let renamed = makeMode(id: modeID, name: "Renamed", icon: "envelope")
        store.setModes([original])
        store.setHistoryEntries([entry])
        _ = store.history(search: "", flaggedOnly: false, in: environment)
        store.setModes([renamed])
        let result = store.history(
            search: "",
            flaggedOnly: false,
            in: environment
        ).value

        let row = result.sections.flatMap(\.rows)[0]
        let presentation = result.presentation(for: row)

        XCTAssertEqual(
            [presentation.fullModeName, presentation.modeIcon],
            ["Renamed", "envelope"]
        )
    }

    func testModeDeletionUsesRecordedHistoryAttribution() {
        let store = PaneProjectionStore()
        let environment = makeEnvironment()
        let modeID = ModeID.random()
        var entry = makeEntry(text: "Saved", rawText: "Saved")
        entry.modeID = modeID
        entry.modeName = "Recorded"
        store.setModes([
            makeMode(id: modeID, name: "Current", icon: "envelope"),
        ])
        store.setHistoryEntries([entry])
        _ = store.history(search: "", flaggedOnly: false, in: environment)

        store.setModes([])
        let result = store.history(
            search: "",
            flaggedOnly: false,
            in: environment
        ).value

        let row = result.sections.flatMap(\.rows)[0]
        let presentation = result.presentation(for: row)

        XCTAssertEqual(
            [presentation.fullModeName, String(presentation.isDeletedMode)],
            ["Recorded", "true"]
        )
    }

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
        let historyRows = history.value.sections.flatMap(\.rows)

        XCTAssertEqual(
            [
                home.value.recent.sections.flatMap(\.rows).first?.entry.id,
                historyRows.first.map { history.value.entry(for: $0).id },
                historyRows.last.map { history.value.entry(for: $0).id },
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
            history.value.presentation(
                for: history.value.sections.flatMap(\.rows)[0]
            ).accessibilityDescription
                .contains("Mode Performance Mode")
        )
    }

    func testTenThousandSessionModeRenameUpdatesAttributedRows() throws {
        let (store, fixture) = try makeTenThousandStore()
        let environment = makeEnvironment()
        let performanceModeID = try XCTUnwrap(fixture.entries.first?.modeID)
        store.setModes([
            makeMode(
                id: performanceModeID,
                name: "Renamed Performance",
                icon: "bolt"
            ),
        ])

        let history = store.history(
            search: "",
            flaggedOnly: false,
            in: environment
        ).value
        let row = try XCTUnwrap(history.sections.first?.rows.first)

        XCTAssertEqual(
            [
                history.presentation(for: row).fullModeName,
                history.presentation(for: row).modeIcon,
            ],
            ["Renamed Performance", "bolt"]
        )
    }

    func testTenThousandSessionModeDeletionKeepsRecordedAttribution() throws {
        let (store, _) = try makeTenThousandStore()
        let environment = makeEnvironment()

        store.setModes([])
        let history = store.history(
            search: "",
            flaggedOnly: false,
            in: environment
        ).value
        let row = try XCTUnwrap(history.sections.first?.rows.first)
        let presentation = history.presentation(for: row)

        XCTAssertEqual(
            [
                presentation.fullModeName,
                String(presentation.isDeletedMode),
            ],
            ["Performance Mode", "true"]
        )
    }

    func testTenThousandSessionAppendDeltaUpdatesEveryHistoryBackedPane() throws {
        let (store, fixture) = try makeTenThousandStore()
        let environment = makeEnvironment()
        let initialStats = store.stats(in: environment)
        let appended = makeEntry(
            id: try XCTUnwrap(UUID(
                uuidString: "ffffffff-ffff-4fff-8fff-ffffffffffff"
            )),
            createdAt: try XCTUnwrap(
                fixture.entries.first?.createdAt.addingTimeInterval(60)
            ),
            text: "Newest appended words",
            rawText: "Newest appended words"
        )

        store.applyHistoryMutation(.append(appended))
        let home = store.home(in: environment)
        let history = store.history(
            search: "Newest appended words",
            flaggedOnly: false,
            in: environment
        )
        let stats = store.stats(in: environment)

        XCTAssertEqual(
            [
                home.value.recent.sections.flatMap(\.rows).first?.entry.id,
                history.value.sections.flatMap(\.rows).first?.id,
                stats.value.lifetime.totalWords
                    == initialStats.value.lifetime.totalWords + 3
                    ? appended.id
                    : nil,
            ],
            [appended.id, appended.id, appended.id]
        )
    }

    func testTenThousandSessionUpdateDeltaRefreshesSearchAndFlagFiltering() throws {
        let (store, fixture) = try makeTenThousandStore()
        let environment = makeEnvironment()
        var reprocessed = try XCTUnwrap(fixture.entries.last)
        reprocessed.text = "Unique reprocessed result"
        reprocessed.flagged = true

        store.applyHistoryMutation(.update(reprocessed))
        let result = store.history(
            search: "Unique reprocessed result",
            flaggedOnly: true,
            in: environment
        )

        XCTAssertEqual(
            result.value.sections.flatMap(\.rows)
                .map { result.value.entry(for: $0) },
            [reprocessed]
        )
    }

    func testTenThousandSessionDeleteDeltaRemovesExactSourceIdentity() throws {
        let (store, fixture) = try makeTenThousandStore()
        let environment = makeEnvironment()
        let deleted = try XCTUnwrap(fixture.entries.first)

        store.applyHistoryMutation(.delete(deleted.id))
        let history = store.history(
            search: "",
            flaggedOnly: false,
            in: environment
        )

        XCTAssertEqual(
            [
                history.value.sections.flatMap(\.rows).contains {
                    $0.id == deleted.id
                },
                history.value.sections.flatMap(\.rows).count
                    == fixture.entries.count - 1,
            ],
            [false, true]
        )
    }

    func testTenThousandSessionClearDeltaEmptiesEveryHistoryBackedPane() throws {
        let (store, _) = try makeTenThousandStore()
        let environment = makeEnvironment()

        store.applyHistoryMutation(.clear)
        let home = store.home(in: environment)
        let history = store.history(
            search: "",
            flaggedOnly: false,
            in: environment
        )
        let stats = store.stats(in: environment)

        XCTAssertEqual(
            [
                home.value.recent.sections.isEmpty,
                history.value.hasSourceEntries == false,
                stats.value.lifetime == .empty,
            ],
            [true, true, true]
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

    private func makeEntry(
        id: UUID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        text: String,
        rawText: String
    ) -> HistoryEntry {
        HistoryEntry(
            id: id,
            createdAt: createdAt,
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

    private func makeMode(
        id: ModeID,
        name: String,
        icon: String
    ) -> Mode {
        Mode(
            id: id,
            name: name,
            icon: icon,
            asrModel: ASRModelCatalog.defaultID,
            llmModel: "local",
            transformation: .inPlace,
            systemPrompt: "Prompt",
            vocabulary: []
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

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        while !condition() {
            await withCheckedContinuation { continuation in
                withObservationTracking {
                    _ = condition()
                } onChange: {
                    continuation.resume()
                }
            }
        }
    }
}

private actor ProjectionPreparationScheduling {
    private var started: [PaneProjectionStore.Pane: Int] = [:]
    private var startWaiters:
        [PaneProjectionStore.Pane: [CheckedContinuation<Void, Never>]] = [:]
    private var releases: [PaneProjectionStore.Pane: [CheckedContinuation<Void, Never>]] = [:]
    private var cancellations: [PaneProjectionStore.Pane: Int] = [:]
    private var cancellationWaiters:
        [PaneProjectionStore.Pane: [CheckedContinuation<Void, Never>]] = [:]

    func checkpoint(_ pane: PaneProjectionStore.Pane) async {
        started[pane, default: 0] += 1
        for waiter in startWaiters.removeValue(forKey: pane) ?? [] {
            waiter.resume()
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                releases[pane, default: []].append(continuation)
            }
        } onCancel: {
            Task {
                await self.recordCancellation(of: pane)
            }
        }
    }

    func waitUntilStarted(
        _ pane: PaneProjectionStore.Pane,
        count: Int = 1
    ) async {
        if started[pane, default: 0] >= count {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters[pane, default: []].append(continuation)
        }
    }

    func resume(_ pane: PaneProjectionStore.Pane) {
        releases[pane, default: []].removeFirst().resume()
    }

    func waitUntilCancelled(_ pane: PaneProjectionStore.Pane) async {
        if cancellations[pane, default: 0] > 0 {
            return
        }
        await withCheckedContinuation { continuation in
            cancellationWaiters[pane, default: []].append(continuation)
        }
    }

    private func recordCancellation(of pane: PaneProjectionStore.Pane) {
        cancellations[pane, default: 0] += 1
        for waiter in cancellationWaiters.removeValue(forKey: pane) ?? [] {
            waiter.resume()
        }
    }
}
