import XCTest
@testable import FoldWiseVoiceKit

private final class WiringStatsStore: StatsStore {
    private(set) var resetCount = 0
    private var record: StreakRecord?

    func load() -> StreakRecord? {
        record
    }

    func advance(on day: Date, calendar: Calendar) {
        record = StreakRules.advance(record, on: day, calendar: calendar)
    }

    func reset() {
        resetCount += 1
        record = nil
    }
}

@MainActor
final class SettingsControllerWiringTests: XCTestCase {
    private let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("foldwise-settings-controller-tests-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    func testFlagHistoryCallbackReachesWorkflow() {
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("flag-history.jsonl"))
        let row = entry(text: "stored words")
        store.append(row)
        let controller = SettingsController(
            config: makeConfig(), historyStore: store, statsStore: WiringStatsStore()
        )

        controller.model.onFlagHistory?(row)

        XCTAssertEqual(store.load().first?.flagged, true)
    }

    func testDeleteHistoryCallbackReachesWorkflow() {
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("delete-history.jsonl"))
        let row = entry(text: "stored words")
        store.append(row)
        let controller = SettingsController(
            config: makeConfig(), historyStore: store, statsStore: WiringStatsStore()
        )

        controller.model.onDeleteHistory?(row)

        XCTAssertTrue(store.load().isEmpty)
    }

    func testClearHistoryCallbackReachesWorkflow() {
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("clear-history.jsonl"))
        let stats = WiringStatsStore()
        let controller = SettingsController(
            config: makeConfig(), historyStore: store, statsStore: stats
        )

        controller.model.onClearHistory?()

        XCTAssertEqual(stats.resetCount, 1)
    }

    func testPreferenceCallbackReachesWorkflow() {
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("preference-history.jsonl"))
        let config = makeConfig()
        let controller = SettingsController(
            config: config, historyStore: store, statsStore: WiringStatsStore()
        )
        controller.model.pttKey = "F8"

        controller.model.onCommit?()

        XCTAssertEqual(config.hotkey, "F8")
    }

    private func makeConfig() -> Config {
        Config(
            activeMode: "Voice to Text", hotkey: "F5", toggleHotkey: nil, pauseAudio: false,
            badgePosition: nil, modeOrder: ["Voice to Text"],
            modes: ["Voice to Text": Mode(
                name: "Voice to Text", asrModel: "", llmModel: nil,
                systemPrompt: nil, vocab: []
            )],
            path: dir.appendingPathComponent("modes.json")
        )
    }

    private func entry(text: String) -> HistoryEntry {
        HistoryEntry(
            id: UUID(), createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            text: text, rawText: text, isPolished: false, modeName: "Voice to Text",
            wordCount: 2, sourceApp: nil, durationMs: nil, flagged: false, flagReason: nil
        )
    }
}
