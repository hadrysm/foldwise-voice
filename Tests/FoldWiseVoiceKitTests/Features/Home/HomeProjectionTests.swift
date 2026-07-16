// The Home list projection's rules (PRD #103): newest ten entries, day
// grouping with Today/Yesterday/absolute labels, 24h mono timestamps,
// single-line previews, and lowercased tail-truncated Mode tags.

import XCTest
@testable import FoldWiseVoiceKit

final class HomeProjectionTests: XCTestCase {
    /// A fixed Gregorian/UTC calendar and locale so labels and timestamps
    /// never depend on the machine running the tests.
    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.locale = Locale(identifier: "en_US")
        return cal
    }()

    private let locale = Locale(identifier: "en_US")

    /// 2026-07-08 12:00:00 UTC — a fixed "now" for every test.
    private let now = Date(timeIntervalSince1970: 1_783_512_000)

    private func entry(
        _ text: String, mode: String = "Clean", minutesAgo: Double, flagged: Bool = false
    ) -> HistoryEntry {
        HistoryEntry(
            id: UUID(), createdAt: now.addingTimeInterval(-minutesAgo * 60),
            text: text, rawText: text, isPolished: false, modeName: mode,
            wordCount: nil, sourceApp: nil, durationMs: nil, flagged: flagged,
            flagReason: nil
        )
    }

    private func project(_ entries: [HistoryEntry]) -> HomeProjection {
        HomeProjection.project(
            .init(entries: entries), now: now, calendar: calendar, locale: locale
        )
    }

    func testNoEntriesProjectsEmpty() {
        XCTAssertTrue(project([]).isEmpty)
    }

    func testKeepsOnlyTheNewestTenEntries() {
        let entries = (0 ..< 12).map { entry("entry \($0)", minutesAgo: Double($0)) }
        let rows = project(entries).sections.flatMap(\.rows)
        XCTAssertEqual(rows.count, 10)
        XCTAssertEqual(rows.first?.presentation.text, "entry 0")
        XCTAssertEqual(rows.last?.presentation.text, "entry 9")
    }

    func testGroupsIntoTodayYesterdayAndAbsoluteDays() {
        let entries = [
            entry("today", minutesAgo: 60),
            entry("yesterday", minutesAgo: 60 * 24),
            entry("older", minutesAgo: 60 * 24 * 3), // July 5
        ]
        let headers = project(entries).sections.map(\.header)
        XCTAssertEqual(headers, ["Today", "Yesterday", "Jul 5"])
    }

    func testTimeIsTwentyFourHourMinutes() {
        // 12:00 UTC minus 205 minutes = 08:35.
        let projection = project([entry("morning", minutesAgo: 205)])
        XCTAssertEqual(projection.sections.first?.rows.first?.presentation.time, "08:35")
    }

    func testPreviewCollapsesWhitespaceToASingleLine() {
        let projection = project([entry("first line\nsecond   line", minutesAgo: 1)])
        XCTAssertEqual(
            projection.sections.first?.rows.first?.presentation.text,
            "first line second line"
        )
    }

    func testTagLowercasesTheModeName() {
        let projection = project([entry("hi", mode: "Voice to Text", minutesAgo: 1)])
        XCTAssertEqual(
            projection.sections.first?.rows.first?.presentation.compactModeName,
            "voice to text"
        )
    }

    func testTagTailTruncatesLongModeNames() {
        let projection = project([entry("hi", mode: "My Extremely Long Custom Mode", minutesAgo: 1)])
        XCTAssertEqual(
            projection.sections.first?.rows.first?.presentation.compactModeName,
            "my extremely lon"
        )
    }

    func testRecentHistoryResolvesCurrentModeIdentity() {
        let modeID = ModeID.random()
        var source = entry("hi", mode: "Recorded Name", minutesAgo: 1)
        source.modeID = modeID
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

        let row = HomeProjection.project(
            .init(entries: [source], modes: [current]),
            now: now,
            calendar: calendar,
            locale: locale
        ).sections.first?.rows.first

        XCTAssertEqual(
            [row?.presentation.fullModeName, row?.presentation.modeIcon],
            ["Current Name", "envelope"]
        )
    }

    func testRowsWithinADayAreNewestFirst() {
        let entries = [
            entry("older", minutesAgo: 30),
            entry("newest", minutesAgo: 5),
        ]
        let previews = project(entries).sections.first?.rows.map(\.presentation.text)
        XCTAssertEqual(previews, ["newest", "older"])
    }

    func testRowPreservesExactFlaggedSourceEntry() {
        let source = entry("remember this", minutesAgo: 1, flagged: true)
        let row = project([source]).sections.first?.rows.first
        XCTAssertEqual(row?.entry, source)
    }

    func testRowIdentityMatchesSourceEntry() {
        let source = entry("same identity", minutesAgo: 1)
        let row = project([source]).sections.first?.rows.first
        XCTAssertEqual(row?.id, source.id)
    }
}
