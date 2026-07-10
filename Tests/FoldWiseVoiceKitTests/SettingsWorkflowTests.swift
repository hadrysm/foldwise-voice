import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class SettingsWorkflowTests: XCTestCase {
    private enum TestFailure: Error { case save }

    private struct PreferenceState: Equatable {
        let pttKey: String
        let toggleKey: String
        let pauseAudio: Bool
        let saveHistory: Bool
        let retention: RetentionWindow
        let sidebarCollapsed: Bool
        let activeMode: String
        let modeNames: [String]
        let llmModes: Set<String>
        let selectedModel: String
        let asrModel: String
        let status: String
    }

    private struct ConfigState: Equatable {
        let activeMode: String
        let hotkey: String
        let toggleHotkey: String?
        let pauseAudio: Bool
        let saveHistory: Bool
        let retention: RetentionWindow
        let sidebarCollapsed: Bool
        let llmModel: String?
        let asrModel: String
        let persistedHotkey: String?
        let persistedLLMModel: String?
        let persistedASRModel: String?
    }

    private struct RecordingState: Equatable {
        let configHotkey: String
        let configToggle: String?
        let modelHotkey: String
        let modelToggle: String
        let recordingField: SettingsModel.RecordingField?
    }

    private struct StatusTransition: Equatable {
        let text: String
        let isError: Bool
        let clearScheduled: Bool
        let textAfterClear: String
    }

    private struct InvalidCommitState: Equatable {
        let configKey: String
        let persistCount: Int
        let statusIsError: Bool
        let statusContainsUnknownHotkey: Bool
        let clearScheduled: Bool
    }

    private struct FailureStatus: Equatable {
        let hasSaveFailurePrefix: Bool
        let isError: Bool
        let clearScheduled: Bool
    }

    private let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("foldwise-settings-workflow-tests-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    func testPopulateCopiesPreferencesIntoSettingsState() {
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = SettingsWorkflow(
            config: config,
            model: model,
            historyStore: JSONLHistoryStore(url: dir.appendingPathComponent("history.jsonl")),
            persist: {},
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            scheduleStatusClear: { _ in }
        )

        workflow.populatePreferences()

        XCTAssertEqual(
            preferenceState(model),
            PreferenceState(
                pttKey: "F5", toggleKey: "F6", pauseAudio: false,
                saveHistory: false, retention: .sevenDays,
                sidebarCollapsed: true, activeMode: "Clean",
                modeNames: ["Voice to Text", "Clean"], llmModes: ["Clean"],
                selectedModel: "qwen2.5:3b", asrModel: ASRModelCatalog.defaultID,
                status: ""
            )
        )
    }

    func testCommitPersistsEditedPreferences() throws {
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = SettingsWorkflow(
            config: config,
            model: model,
            historyStore: JSONLHistoryStore(url: dir.appendingPathComponent("history.jsonl")),
            persist: { try config.saveAndNotify() },
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            scheduleStatusClear: { _ in }
        )
        workflow.populatePreferences()
        model.activeMode = "Voice to Text"
        model.pttKey = "  F7  "
        model.toggleKey = " "
        model.pauseAudio = true
        model.saveHistory = true
        model.retention = .ninetyDays
        model.sidebar = SidebarPresentation(prefersCollapsed: false)
        model.selectedModel = "llama3.2:3b"
        model.asrModel = "whisper-small"

        workflow.commit()

        let persisted = try Config.load(from: config.path)
        XCTAssertEqual(
            configState(config, persisted: persisted),
            ConfigState(
                activeMode: "Voice to Text", hotkey: "F7", toggleHotkey: nil,
                pauseAudio: true, saveHistory: true, retention: .ninetyDays,
                sidebarCollapsed: false, llmModel: "llama3.2:3b", asrModel: "whisper-small",
                persistedHotkey: "F7", persistedLLMModel: "llama3.2:3b",
                persistedASRModel: "whisper-small"
            )
        )
    }

    func testSuccessfulCommitReportsAndClearsStatus() {
        let config = makeConfig()
        let model = SettingsModel()
        var scheduledClear: (@MainActor () -> Void)?
        let workflow = SettingsWorkflow(
            config: config,
            model: model,
            historyStore: JSONLHistoryStore(url: dir.appendingPathComponent("history.jsonl")),
            persist: {},
            now: Date.init,
            scheduleStatusClear: { scheduledClear = $0 }
        )
        workflow.populatePreferences()

        workflow.commit()
        let text = model.status
        let isError = model.statusIsError
        let clearScheduled = scheduledClear != nil

        scheduledClear?()
        XCTAssertEqual(
            StatusTransition(
                text: text, isError: isError, clearScheduled: clearScheduled,
                textAfterClear: model.status
            ),
            StatusTransition(
                text: "Saved ✓", isError: false, clearScheduled: true, textAfterClear: ""
            )
        )
    }

    func testFinishRecordingCommitsCapturedPushToTalkKey() {
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model)
        workflow.populatePreferences()
        workflow.beginRecording(.ptt)

        workflow.finishRecording(with: "F8")

        XCTAssertEqual(
            recordingState(config, model),
            RecordingState(
                configHotkey: "F8", configToggle: "F6", modelHotkey: "F8",
                modelToggle: "F6", recordingField: nil
            )
        )
    }

    func testFinishRecordingCommitsCapturedToggleKey() {
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model)
        workflow.populatePreferences()
        workflow.beginRecording(.toggle)

        workflow.finishRecording(with: "F9")

        XCTAssertEqual(
            recordingState(config, model),
            RecordingState(
                configHotkey: "F5", configToggle: "F9", modelHotkey: "F5",
                modelToggle: "F9", recordingField: nil
            )
        )
    }

    func testFinishRecordingWithoutAKeyCancelsTheEdit() {
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model)
        workflow.populatePreferences()
        workflow.beginRecording(.ptt)

        workflow.finishRecording(with: nil)

        XCTAssertEqual(
            recordingState(config, model),
            RecordingState(
                configHotkey: "F5", configToggle: "F6", modelHotkey: "F5",
                modelToggle: "F6", recordingField: nil
            )
        )
    }

    func testCommitRejectsInvalidHotkeyWithoutPersisting() {
        let config = makeConfig()
        let model = SettingsModel()
        var persistCount = 0
        var scheduledClear: (@MainActor () -> Void)?
        let workflow = SettingsWorkflow(
            config: config,
            model: model,
            historyStore: JSONLHistoryStore(url: dir.appendingPathComponent("history.jsonl")),
            persist: { persistCount += 1 },
            now: Date.init,
            scheduleStatusClear: { scheduledClear = $0 }
        )
        workflow.populatePreferences()
        model.pttKey = "not_a_key"

        workflow.commit()

        XCTAssertEqual(
            InvalidCommitState(
                configKey: config.hotkey, persistCount: persistCount,
                statusIsError: model.statusIsError,
                statusContainsUnknownHotkey: model.status.contains("Unknown hotkey"),
                clearScheduled: scheduledClear != nil
            ),
            InvalidCommitState(
                configKey: "F5", persistCount: 0, statusIsError: true,
                statusContainsUnknownHotkey: true, clearScheduled: false
            )
        )
    }

    func testCommitRejectsInvalidToggleWithoutPersisting() {
        let config = makeConfig()
        let model = SettingsModel()
        var persistCount = 0
        var scheduledClear: (@MainActor () -> Void)?
        let workflow = SettingsWorkflow(
            config: config,
            model: model,
            historyStore: JSONLHistoryStore(url: dir.appendingPathComponent("history.jsonl")),
            persist: { persistCount += 1 },
            now: Date.init,
            scheduleStatusClear: { scheduledClear = $0 }
        )
        workflow.populatePreferences()
        model.toggleKey = "not_a_key"

        workflow.commit()

        XCTAssertEqual(
            InvalidCommitState(
                configKey: config.toggleHotkey ?? "", persistCount: persistCount,
                statusIsError: model.statusIsError,
                statusContainsUnknownHotkey: model.status.contains("Unknown hotkey"),
                clearScheduled: scheduledClear != nil
            ),
            InvalidCommitState(
                configKey: "F6", persistCount: 0, statusIsError: true,
                statusContainsUnknownHotkey: true, clearScheduled: false
            )
        )
    }

    func testFailedPersistenceReportsError() {
        let config = makeConfig()
        let model = SettingsModel()
        var scheduledClear: (@MainActor () -> Void)?
        let workflow = SettingsWorkflow(
            config: config,
            model: model,
            historyStore: JSONLHistoryStore(url: dir.appendingPathComponent("history.jsonl")),
            persist: { throw TestFailure.save },
            now: Date.init,
            scheduleStatusClear: { scheduledClear = $0 }
        )
        workflow.populatePreferences()
        model.pttKey = "F8"

        workflow.commit()

        XCTAssertEqual(
            FailureStatus(
                hasSaveFailurePrefix: model.status.hasPrefix("⚠️ save failed:"),
                isError: model.statusIsError, clearScheduled: scheduledClear != nil
            ),
            FailureStatus(hasSaveFailurePrefix: true, isError: true, clearScheduled: false)
        )
    }

    func testFailedPersistenceDoesNotNotifyObservers() {
        let config = makeConfig()
        let model = SettingsModel()
        var received: [Config.ChangeSet] = []
        config.onChange { received.append($0) }
        let workflow = SettingsWorkflow(
            config: config,
            model: model,
            historyStore: JSONLHistoryStore(url: dir.appendingPathComponent("history.jsonl")),
            persist: { throw TestFailure.save },
            now: Date.init,
            scheduleStatusClear: { _ in }
        )
        workflow.populatePreferences()
        model.pttKey = "F8"

        workflow.commit()

        XCTAssertEqual(received.count, 0)
    }

    func testNoOpCommitDoesNotNotifyConfigObservers() {
        let config = makeConfig()
        let model = SettingsModel()
        var received: [Config.ChangeSet] = []
        config.onChange { received.append($0) }
        let workflow = SettingsWorkflow(
            config: config,
            model: model,
            historyStore: JSONLHistoryStore(url: dir.appendingPathComponent("history.jsonl")),
            persist: { try config.saveAndNotify() },
            now: Date.init,
            scheduleStatusClear: { _ in }
        )
        workflow.populatePreferences()

        workflow.commit()

        XCTAssertEqual(received.count, 0)
    }

    func testTightenedRetentionRefreshesVisibleHistory() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let config = makeConfig()
        config.historyRetention = .ninetyDays
        let model = SettingsModel()
        let historyStore = JSONLHistoryStore(url: dir.appendingPathComponent("history.jsonl"))
        historyStore.append(entry(createdAt: now.addingTimeInterval(-10 * 86400), text: "old"))
        historyStore.append(entry(createdAt: now, text: "new"))
        let workflow = SettingsWorkflow(
            config: config,
            model: model,
            historyStore: historyStore,
            persist: {},
            now: { now },
            scheduleStatusClear: { _ in }
        )
        workflow.populatePreferences()
        model.retention = .sevenDays

        workflow.commit()

        XCTAssertEqual(model.historyEntries.map(\.text), ["new"])
    }

    private func preferenceState(_ model: SettingsModel) -> PreferenceState {
        PreferenceState(
            pttKey: model.pttKey,
            toggleKey: model.toggleKey,
            pauseAudio: model.pauseAudio,
            saveHistory: model.saveHistory,
            retention: model.retention,
            sidebarCollapsed: model.sidebar.prefersCollapsed,
            activeMode: model.activeMode,
            modeNames: model.modeNames,
            llmModes: model.llmModes,
            selectedModel: model.selectedModel,
            asrModel: model.asrModel,
            status: model.status
        )
    }

    private func configState(_ config: Config, persisted: Config) -> ConfigState {
        ConfigState(
            activeMode: config.activeMode,
            hotkey: config.hotkey,
            toggleHotkey: config.toggleHotkey,
            pauseAudio: config.pauseAudio,
            saveHistory: config.saveHistory,
            retention: config.historyRetention,
            sidebarCollapsed: config.sidebarCollapsed,
            llmModel: config.llmModel,
            asrModel: config.asrModel,
            persistedHotkey: persisted.hotkey,
            persistedLLMModel: persisted.llmModel,
            persistedASRModel: persisted.asrModel
        )
    }

    private func recordingState(_ config: Config, _ model: SettingsModel) -> RecordingState {
        RecordingState(
            configHotkey: config.hotkey,
            configToggle: config.toggleHotkey,
            modelHotkey: model.pttKey,
            modelToggle: model.toggleKey,
            recordingField: model.recordingField
        )
    }

    private func makeWorkflow(config: Config, model: SettingsModel) -> SettingsWorkflow {
        SettingsWorkflow(
            config: config,
            model: model,
            historyStore: JSONLHistoryStore(url: dir.appendingPathComponent("history.jsonl")),
            persist: {},
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            scheduleStatusClear: { _ in }
        )
    }

    private func makeConfig() -> Config {
        let modes = [
            "Voice to Text": Mode(
                name: "Voice to Text", asrModel: ASRModelCatalog.defaultID,
                llmModel: nil, systemPrompt: nil, vocab: []
            ),
            "Clean": Mode(
                name: "Clean", asrModel: ASRModelCatalog.defaultID,
                llmModel: "qwen2.5:3b", systemPrompt: "Polish", vocab: []
            ),
        ]
        return Config(
            activeMode: "Clean", hotkey: "F5", toggleHotkey: "F6", pauseAudio: false,
            saveHistory: false, historyRetention: .sevenDays, badgePosition: nil,
            sidebarCollapsed: true, modeOrder: ["Voice to Text", "Clean"], modes: modes,
            path: dir.appendingPathComponent("modes.json")
        )
    }

    private func entry(createdAt: Date, text: String) -> HistoryEntry {
        HistoryEntry(
            id: UUID(), createdAt: createdAt, text: text, rawText: text,
            isPolished: false, modeName: "Voice to Text", wordCount: 1,
            sourceApp: nil, durationMs: nil, flagged: false, flagReason: nil
        )
    }
}
