import XCTest
@testable import FoldWiseVoiceKit

@MainActor
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
            projection.sections.flatMap(\.rows).map { projection.entry(for: $0) },
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

    func testProjectionCarriesExactSourceEntry() throws {
        let today = entry(
            text: "today", rawText: "today", minutesAgo: 60, flagged: false
        )
        let projection = project([today])
        let row = try XCTUnwrap(projection.sections.first?.rows.first)

        XCTAssertEqual(projection.entry(for: row), today)
    }

    func testProjectionBuildsPresentationWhenRowIsRequested() throws {
        let today = entry(
            text: "today", rawText: "today", minutesAgo: 60, flagged: false
        )
        let projection = project([today])
        let row = try XCTUnwrap(projection.sections.first?.rows.first)

        XCTAssertEqual(projection.presentation(for: row).text, "today")
    }

    func testProjectionCancelsWithinDenseDayGroup() {
        let indices: Range<Int> = 0 ..< 10000
        let entries = indices.map { index in
            entry(
                text: "entry \(index)",
                rawText: "entry \(index)",
                minutesAgo: Double(index) / 1000,
                flagged: false
            )
        }
        var index = HistoryIndex()
        index.setEntries(entries)
        let snapshot = index.snapshot(calendar: calendar)
        var cancellationChecks = 0

        let projection = HistoryProjection.project(
            snapshot,
            search: "absent",
            flaggedOnly: false,
            now: now,
            locale: Locale(identifier: "en_US"),
            shouldCancel: {
                cancellationChecks += 1
                return cancellationChecks == 4
            }
        )

        XCTAssertNil(projection)
    }

    func testProjectionResolvesModeAttributionFromCurrentLibrary() {
        let modeID = ModeID.random()
        var source = entry(
            text: "today", rawText: "today", minutesAgo: 60, flagged: false
        )
        source.modeID = modeID
        source.modeName = "Recorded Name"
        let current = Mode(
            id: modeID,
            name: "Current Name",
            icon: "envelope",
            asrModel: ASRModelCatalog.defaultID,
            llmModel: "qwen2.5:3b",
            transformation: .expanding,
            systemPrompt: "Prompt",
            vocabulary: []
        )

        let projection = project([source], modes: [current])
        let row = projection.sections.first?.rows.first
        let presentation = row.map { projection.presentation(for: $0) }

        XCTAssertEqual(
            [presentation?.fullModeName, presentation?.modeIcon],
            ["Current Name", "envelope"]
        )
    }

    func testBlankSearchProjectsEveryEntry() {
        let source = entry(
            text: "one", rawText: "one", minutesAgo: 1, flagged: false
        )

        let projection = project([source], search: "   ")

        XCTAssertEqual(
            projection.sections.first?.rows.map { projection.entry(for: $0) },
            [source]
        )
    }

    func testEmptyInputProjectsEmpty() {
        XCTAssertTrue(project([]).isEmpty)
    }

    func testStoreExecutesOnlyWhenEntriesFiltersOrModesChange() {
        let source = entry(
            text: "one", rawText: "one", minutesAgo: 1, flagged: false
        )
        let added = entry(
            text: "two", rawText: "two", minutesAgo: 2, flagged: true
        )
        let store = PaneProjectionStore()
        let locale = Locale(identifier: "en_US")
        let environment = PaneProjectionStore.Environment(
            now: now,
            calendar: calendar,
            locale: locale
        )

        store.setHistoryEntries([source])
        let initial = store.history(search: "", flaggedOnly: false, in: environment)
        let unchanged = store.history(search: "", flaggedOnly: false, in: environment)
        store.setHistoryEntries([source, added])
        let entriesChanged = store.history(search: "", flaggedOnly: false, in: environment)
        let searchChanged = store.history(search: "two", flaggedOnly: false, in: environment)
        let filterChanged = store.history(search: "two", flaggedOnly: true, in: environment)
        store.setModes([Mode(
            id: .random(), name: "Current", icon: "pencil",
            asrModel: ASRModelCatalog.defaultID, llmModel: "qwen2.5:3b",
            transformation: .inPlace, systemPrompt: "Prompt", vocabulary: []
        )])
        let modesChanged = store.history(search: "two", flaggedOnly: true, in: environment)

        XCTAssertEqual(initial.generation, unchanged.generation)
        XCTAssertEqual(
            Set([
                initial.generation,
                entriesChanged.generation,
                searchChanged.generation,
                filterChanged.generation,
                modesChanged.generation,
            ]).count,
            5
        )
    }

    func testStoreInvalidatesWhenTheCalendarDayChanges() throws {
        var currentNow = now
        let source = entry(
            text: "one", rawText: "one", minutesAgo: 60, flagged: false
        )
        let store = PaneProjectionStore()
        store.setHistoryEntries([source])
        let locale = Locale(identifier: "en_US")

        let beforeMidnight = store.history(
            search: "",
            flaggedOnly: false,
            in: .init(now: currentNow, calendar: calendar, locale: locale)
        )
        currentNow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: currentNow))
        let afterMidnight = store.history(
            search: "",
            flaggedOnly: false,
            in: .init(now: currentNow, calendar: calendar, locale: locale)
        )

        XCTAssertEqual(beforeMidnight.value.sections.map(\.header), ["Today"])
        XCTAssertEqual(afterMidnight.value.sections.map(\.header), ["Yesterday"])
    }

    private func project(
        _ entries: [HistoryEntry],
        search: String = "",
        flaggedOnly: Bool = false,
        modes: [Mode] = []
    ) -> HistoryProjection {
        HistoryProjection.project(
            .init(entries: entries, search: search, flaggedOnly: flaggedOnly, modes: modes),
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
