// Controller-level regression tests for the PRD #97 load-bearing invariant: a
// DELIBERATE wipe (Clear All / delete-on-turn-off, both funnelled through
// `clearHistory`) resets the lifetime streak, while a per-row delete and the
// retention sweep do NOT. That distinction lives entirely in SettingsController's
// wired closures — `clearHistory` calls `statsStore.reset()`, `deleteHistory`
// does not — and was untested, so a refactor could add `reset()` to the wrong
// path and silently destroy a user's streak while shipping green. These tests
// drive the wired closures through a spy StatsStore that counts resets, pinning
// which paths are (and are not) allowed to reset.
//
// The controller is @MainActor and construction is lightweight (it builds no
// window unless `show()` is called), so we construct it directly and reach its
// wired closures via the now-internal `model`.

import XCTest
@testable import FoldWiseVoiceKit

/// Counts resets and folds advances through the real streak rule, so a test can
/// assert exactly how many times a controller path deliberately wiped the streak.
private final class SpyStatsStore: StatsStore {
    var resetCallCount = 0
    private var record: StreakRecord?

    func load() -> StreakRecord? {
        record
    }

    func advance(on day: Date, calendar: Calendar) {
        record = StreakRules.advance(record, on: day, calendar: calendar)
    }

    func reset() {
        resetCallCount += 1
        record = nil
    }
}

@MainActor
final class SettingsControllerStreakResetTests: XCTestCase {
    /// XCTest instantiates the case once per test method, so each test gets its
    /// own scratch directory (following HistoryStoreRoundTripTests prior art).
    private let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("foldwise-settingscontroller-tests-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    private var historyURL: URL {
        dir.appendingPathComponent("history.jsonl")
    }

    private var configURL: URL {
        dir.appendingPathComponent("modes.json")
    }

    /// A minimal single-mode Config written to a temp path, so `commit()` can
    /// persist without touching the user's real modes.json.
    private func makeConfig() -> Config {
        Config(
            activeMode: "Voice to Text", hotkey: "F5", toggleHotkey: nil, pauseAudio: false,
            badgePosition: nil, modeOrder: ["Voice to Text"],
            modes: ["Voice to Text": Mode(
                name: "Voice to Text", asrModel: "", llmModel: nil, systemPrompt: nil, vocab: []
            )],
            path: configURL
        )
    }

    private func entry(text: String) -> HistoryEntry {
        HistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            text: text,
            rawText: text + " (raw)",
            isPolished: false,
            modeName: "Voice to Text",
            wordCount: text.split(whereSeparator: { $0.isWhitespace }).count,
            sourceApp: "TextEdit",
            durationMs: 1200,
            flagged: false,
            flagReason: nil
        )
    }

    /// Build the controller wired to a real history store and the reset-counting
    /// spy, returning both so a test can fire a closure and read the spy.
    private func makeController() -> (SettingsController, JSONLHistoryStore, SpyStatsStore) {
        let historyStore = JSONLHistoryStore(url: historyURL)
        let spy = SpyStatsStore()
        let controller = SettingsController(
            config: makeConfig(), historyStore: historyStore, statsStore: spy
        )
        return (controller, historyStore, spy)
    }

    /// Clear All / delete-on-turn-off both funnel through `clearHistory`, which
    /// deliberately resets the streak so a bragging count can't outlive the data
    /// it counted (PRD #97).
    func testClearHistoryResetsTheStreak() {
        let (controller, _, spy) = makeController()

        controller.model.onClearHistory?()

        XCTAssertEqual(spy.resetCallCount, 1)
    }

    /// A per-row delete is a rolling-window edit, not a wipe, so it must NOT reset
    /// the streak. This pins the exact refactor risk: were `deleteHistory` changed
    /// to call `statsStore.reset()`, this assertion would flip to 1 and fail.
    func testPerRowDeleteDoesNotResetTheStreak() {
        let (controller, historyStore, spy) = makeController()
        let row = entry(text: "spoken earlier")
        historyStore.append(row)

        controller.model.onDeleteHistory?(row)

        XCTAssertEqual(spy.resetCallCount, 0)
    }

    /// The retention sweep is a rolling window, not a wipe, so tightening
    /// retention (which triggers `commit()`'s immediate sweep) must NOT reset the
    /// streak. `commit()` reads `model.pttKey` and early-returns on an unparseable
    /// hotkey, so a valid key is set first; the tighter window (7 vs the default
    /// 30 days) is what makes `commit` actually run the sweep. `commit` writes to
    /// the temp config path, so this touches nothing real. (The sweep invariant is
    /// also covered structurally: HistoryStore.sweep holds no reference to
    /// StatsStore, so it cannot reset a streak.)
    func testRetentionSweepDoesNotResetTheStreak() {
        let (controller, _, spy) = makeController()
        controller.model.pttKey = "F5" // so commit() parses and does not early-return
        controller.model.retention = .sevenDays // tighter than the default 30 → commit sweeps

        controller.model.onCommit?()

        XCTAssertEqual(spy.resetCallCount, 0)
    }
}
