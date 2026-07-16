import AppKit
import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class SettingsWorkflowTests: XCTestCase {
    private final class NonPersistingHistoryStore: HistoryStore {
        private let entries: [HistoryEntry]

        init(entries: [HistoryEntry]) {
            self.entries = entries
        }

        func append(_: HistoryEntry) {}
        func load() -> [HistoryEntry] {
            entries
        }

        func update(_: HistoryEntry) {}
        func delete(id _: UUID) {}
        func clearAll() {}
        func sweep(retention _: RetentionWindow, now _: Date) {}
        func onAppend(_: @escaping (HistoryEntry) -> Void) {}
    }

    private struct PreferenceState: Equatable {
        let pttKey: String
        let toggleKey: String
        let pauseAudio: Bool
        let appearance: AppearancePreference
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
        let appearance: AppearancePreference
        let saveHistory: Bool
        let retention: RetentionWindow
        let sidebarCollapsed: Bool
        let llmModel: String?
        let asrModel: String
        let persistedHotkey: String?
        let persistedLLMModel: String?
        let persistedASRModel: String?
        let persistedAppearance: AppearancePreference
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
        let statusIsError: Bool
        let statusContainsUnknownHotkey: Bool
        let clearScheduled: Bool
    }

    private struct FailureStatus: Equatable {
        let hasSaveFailurePrefix: Bool
        let isError: Bool
        let clearScheduled: Bool
    }

    private struct LLMInstallState: Equatable {
        let selectedModel: String
        let persistedModel: String?
        let pullingModel: String?
        let progressStatus: String
        let progressFraction: Double?
        let error: String
        let customModel: String
        let installed: [String]?
    }

    private struct LLMInstallCompletion: Equatable {
        let selectedModel: String
        let persistedModel: String?
        let pullingModel: String?
        let customModel: String
        let installed: [String]?
    }

    private struct LLMProgressState: Equatable {
        let status: String
        let fraction: Double?
    }

    private struct ASRDownloadState: Equatable {
        let downloading: String?
        let fraction: Double?
        let preparing: Bool
        let downloaded: Set<String>
        let error: String
    }

    private struct ASRProgressState: Equatable {
        let fraction: Double?
        let preparing: Bool
    }

    private struct ASRDeleteState: Equatable {
        let deleting: String?
        let downloaded: Set<String>
        let selected: String
        let persisted: String
        let error: String
    }

    private struct ASRPopulationState: Equatable {
        let downloading: String?
        let downloaded: Set<String>
        let downloadError: String
        let deleting: String?
        let deleteError: String
    }

    @MainActor
    private final class SuspendedLLMLists {
        private(set) var requestCount = 0
        private var continuations: [Int: CheckedContinuation<[OllamaClient.InstalledModel], Never>] = [:]

        func run() async -> [OllamaClient.InstalledModel] {
            requestCount += 1
            let request = requestCount
            return await withCheckedContinuation { continuations[request] = $0 }
        }

        func finish(request: Int, with models: [OllamaClient.InstalledModel]) {
            continuations.removeValue(forKey: request)?.resume(returning: models)
        }
    }

    @MainActor
    private final class SuspendedASRPreparation {
        private(set) var started = false
        private var progress: ASRModelManaging.ASRProgress?
        private var loading: ASRModelManaging.ASRLoading?
        private var continuation: CheckedContinuation<String?, Never>?

        func run(
            _: ASRModelCatalog.Entry,
            progress: @escaping ASRModelManaging.ASRProgress,
            loading: @escaping ASRModelManaging.ASRLoading
        ) async -> String? {
            started = true
            self.progress = progress
            self.loading = loading
            return await withCheckedContinuation { continuation = $0 }
        }

        func report(fraction: Double, loading: Bool) {
            progress?(fraction)
            self.loading?(loading)
        }

        func finish(_ failure: String?) {
            continuation?.resume(returning: failure)
            continuation = nil
        }
    }

    @MainActor
    private final class CannedModelManagers: LLMModelManaging, ASRModelManaging {
        let listResult: @MainActor () async -> [OllamaClient.InstalledModel]
        let pullResult: @MainActor (
            String, @escaping LLMModelManaging.LLMProgress
        ) async -> String?
        let deleteLLMResult: @MainActor (String) async -> String?
        let prepareASRResult: @MainActor (
            ASRModelCatalog.Entry,
            @escaping ASRModelManaging.ASRProgress,
            @escaping ASRModelManaging.ASRLoading
        ) async -> String?
        let deleteASRResult: @MainActor (ASRModelCatalog.Entry) async -> String?

        init(
            list: @escaping @MainActor () async -> [OllamaClient.InstalledModel],
            pull: @escaping @MainActor (
                String, @escaping LLMModelManaging.LLMProgress
            ) async -> String?,
            deleteLLM: @escaping @MainActor (String) async -> String?,
            prepareASR: @escaping @MainActor (
                ASRModelCatalog.Entry,
                @escaping ASRModelManaging.ASRProgress,
                @escaping ASRModelManaging.ASRLoading
            ) async -> String?,
            deleteASR: @escaping @MainActor (ASRModelCatalog.Entry) async -> String?
        ) {
            listResult = list
            pullResult = pull
            deleteLLMResult = deleteLLM
            prepareASRResult = prepareASR
            deleteASRResult = deleteASR
        }

        func list() async -> [OllamaClient.InstalledModel] {
            await listResult()
        }

        func pull(_ name: String, progress: @escaping LLMProgress) async -> String? {
            await pullResult(name, progress)
        }

        func delete(_ name: String) async -> String? {
            await deleteLLMResult(name)
        }

        func prepare(
            _ entry: ASRModelCatalog.Entry,
            progress: @escaping ASRProgress,
            loading: @escaping ASRLoading
        ) async -> String? {
            await prepareASRResult(entry, progress, loading)
        }

        func delete(_ entry: ASRModelCatalog.Entry) async -> String? {
            await deleteASRResult(entry)
        }
    }

    @MainActor
    private final class CannedUpdateChecker: SettingsUpdateChecking {
        let isAvailable: Bool
        let result: UpdateChecker.CheckResult

        init(isAvailable: Bool = true, result: UpdateChecker.CheckResult) {
            self.isAvailable = isAvailable
            self.result = result
        }

        func check() async -> UpdateChecker.CheckResult {
            result
        }
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
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            scheduleStatusClear: { _ in },
            copy: { _ in }
        )

        workflow.populatePreferences()

        XCTAssertEqual(
            preferenceState(model),
            PreferenceState(
                pttKey: "F5", toggleKey: "F6", pauseAudio: false, appearance: .dark,
                saveHistory: false, retention: .sevenDays,
                sidebarCollapsed: true, activeMode: "Clean",
                modeNames: ["Voice to Text", "Clean"], llmModes: ["Clean"],
                selectedModel: "qwen2.5:3b", asrModel: ASRModelCatalog.defaultID,
                status: ""
            )
        )
    }

    func testPopulateMakesPersistedASRModelAvailableAndClearsTransientState() throws {
        let config = makeConfig()
        try config.setASRModel("whisper-small")
        let model = SettingsModel()
        model.asrDownloading = "whisper-large-v3-turbo"
        model.asrDownloadError = "old download error"
        model.asrDeleting = "whisper-small"
        model.asrDeleteError = "old delete error"
        let workflow = makeWorkflow(config: config, model: model)

        workflow.populatePreferences()

        XCTAssertEqual(
            ASRPopulationState(
                downloading: model.asrDownloading,
                downloaded: model.asrDownloaded,
                downloadError: model.asrDownloadError,
                deleting: model.asrDeleting,
                deleteError: model.asrDeleteError
            ),
            ASRPopulationState(
                downloading: nil,
                downloaded: [ASRModelCatalog.defaultID, "whisper-small"],
                downloadError: "",
                deleting: nil,
                deleteError: ""
            )
        )
    }

    func testUnavailableUpdateCheckPublishesUnavailableState() {
        let config = makeConfig()
        let model = SettingsModel()
        let updates = CannedUpdateChecker(isAvailable: false, result: .failed)
        let workflow = makeWorkflow(config: config, model: model, updates: updates)

        workflow.checkForUpdates()

        guard case .unavailable = model.updateState else {
            return XCTFail("expected unavailable update state")
        }
    }

    func testAvailableUpdatePublishesStateAndReportsVersion() async {
        let config = makeConfig()
        let model = SettingsModel()
        let updates = CannedUpdateChecker(
            result: .updateAvailable(version: "2.0.0", downloadURL: nil)
        )
        var reported: String?
        let workflow = makeWorkflow(
            config: config,
            model: model,
            updates: updates,
            reportUpdate: { reported = $0 }
        )

        workflow.checkForUpdates()
        await waitUntil {
            if case .available = model.updateState { return true }
            return false
        }

        XCTAssertEqual(reported, "2.0.0")
    }

    func testFailedUpdateCheckPublishesFailureState() async {
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(
            config: config,
            model: model,
            updates: CannedUpdateChecker(result: .failed)
        )

        workflow.checkForUpdates()
        await waitUntil {
            if case .failed = model.updateState { return true }
            return false
        }

        guard case .failed = model.updateState else {
            return XCTFail("expected failed update state")
        }
    }

    func testCommitPersistsEditedPreferences() throws {
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = SettingsWorkflow(
            config: config,
            model: model,
            historyStore: JSONLHistoryStore(url: dir.appendingPathComponent("history.jsonl")),
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            scheduleStatusClear: { _ in },
            copy: { _ in }
        )
        workflow.populatePreferences()
        model.activeMode = "Voice to Text"
        model.pttKey = "  F7  "
        model.toggleKey = " "
        model.pauseAudio = true
        model.appearance = .light
        model.saveHistory = true
        model.retention = .ninetyDays
        model.sidebar = SidebarPresentation(prefersCollapsed: false)
        model.asrModel = "whisper-small"

        workflow.commit()

        let persisted = try Config.load(from: config.path)
        XCTAssertEqual(
            configState(config, persisted: persisted),
            ConfigState(
                activeMode: "Voice to Text", hotkey: "F7", toggleHotkey: nil,
                pauseAudio: true, appearance: .light,
                saveHistory: true, retention: .ninetyDays,
                sidebarCollapsed: false, llmModel: "qwen2.5:3b", asrModel: "whisper-small",
                persistedHotkey: "F7", persistedLLMModel: "qwen2.5:3b",
                persistedASRModel: "whisper-small", persistedAppearance: .light
            )
        )
    }

    func testCommitPreservesDistinctPerModeModelAssignments() throws {
        let config = Config.defaultConfig(
            path: dir.appendingPathComponent("per-mode-models-config.json")
        )
        var email = try XCTUnwrap(config.orderedModes.last)
        email.llmModel = "llama3.2:3b"
        try config.saveMode(email)
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model)
        workflow.populatePreferences()
        model.pttKey = "F7"

        workflow.commit()

        XCTAssertEqual(
            config.orderedModes.map(\.llmModel),
            ["qwen2.5:3b", "llama3.2:3b"]
        )
    }

    func testRecoveryPopulationDisablesConfigurationAndKeepsVoiceToText() throws {
        let path = dir.appendingPathComponent("invalid-config.json")
        let original = Data("invalid".utf8)
        try original.write(to: path)
        let config = Config.loadOrCreate(at: path)
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model)

        workflow.populatePreferences()
        model.activeMode = "Email"
        workflow.commit()

        XCTAssertTrue(model.configurationReadOnly)
        XCTAssertEqual(model.activeMode, "Voice to Text")
        XCTAssertTrue(model.statusIsError)
        XCTAssertEqual(try Data(contentsOf: path), original)
    }

    func testSuccessfulCommitReportsAndClearsStatus() {
        let config = makeConfig()
        let model = SettingsModel()
        var scheduledClear: (@MainActor () -> Void)?
        let workflow = SettingsWorkflow(
            config: config,
            model: model,
            historyStore: JSONLHistoryStore(url: dir.appendingPathComponent("history.jsonl")),
            now: Date.init,
            scheduleStatusClear: { scheduledClear = $0 },
            copy: { _ in }
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
        var scheduledClear: (@MainActor () -> Void)?
        let workflow = SettingsWorkflow(
            config: config,
            model: model,
            historyStore: JSONLHistoryStore(url: dir.appendingPathComponent("history.jsonl")),
            now: Date.init,
            scheduleStatusClear: { scheduledClear = $0 },
            copy: { _ in }
        )
        workflow.populatePreferences()
        model.pttKey = "not_a_key"

        workflow.commit()

        XCTAssertEqual(
            InvalidCommitState(
                configKey: config.hotkey,
                statusIsError: model.statusIsError,
                statusContainsUnknownHotkey: model.status.contains("Unknown hotkey"),
                clearScheduled: scheduledClear != nil
            ),
            InvalidCommitState(
                configKey: "F5", statusIsError: true,
                statusContainsUnknownHotkey: true, clearScheduled: false
            )
        )
    }

    func testCommitRejectsInvalidToggleWithoutPersisting() {
        let config = makeConfig()
        let model = SettingsModel()
        var scheduledClear: (@MainActor () -> Void)?
        let workflow = SettingsWorkflow(
            config: config,
            model: model,
            historyStore: JSONLHistoryStore(url: dir.appendingPathComponent("history.jsonl")),
            now: Date.init,
            scheduleStatusClear: { scheduledClear = $0 },
            copy: { _ in }
        )
        workflow.populatePreferences()
        model.toggleKey = "not_a_key"

        workflow.commit()

        XCTAssertEqual(
            InvalidCommitState(
                configKey: config.toggleHotkey ?? "",
                statusIsError: model.statusIsError,
                statusContainsUnknownHotkey: model.status.contains("Unknown hotkey"),
                clearScheduled: scheduledClear != nil
            ),
            InvalidCommitState(
                configKey: "F6", statusIsError: true,
                statusContainsUnknownHotkey: true, clearScheduled: false
            )
        )
    }

    func testFailedPersistenceReportsError() {
        let config = makeFailingConfig()
        let model = SettingsModel()
        var scheduledClear: (@MainActor () -> Void)?
        let workflow = SettingsWorkflow(
            config: config,
            model: model,
            historyStore: JSONLHistoryStore(url: dir.appendingPathComponent("history.jsonl")),
            now: Date.init,
            scheduleStatusClear: { scheduledClear = $0 },
            copy: { _ in }
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
        let config = makeFailingConfig()
        let model = SettingsModel()
        var received: [Config.ChangeSet] = []
        config.onChange { received.append($0) }
        let workflow = SettingsWorkflow(
            config: config,
            model: model,
            historyStore: JSONLHistoryStore(url: dir.appendingPathComponent("history.jsonl")),
            now: Date.init,
            scheduleStatusClear: { _ in },
            copy: { _ in }
        )
        workflow.populatePreferences()
        model.pttKey = "F8"

        workflow.commit()

        XCTAssertEqual(received.count, 0)
    }

    func testFailedInputDeviceSelectionReportsPersistenceError() {
        let config = makeFailingConfig()
        let model = SettingsModel()
        let workflow = SettingsWorkflow(
            config: config,
            model: model,
            historyStore: JSONLHistoryStore(url: dir.appendingPathComponent("history.jsonl")),
            now: Date.init,
            scheduleStatusClear: { _ in },
            copy: { _ in }
        )

        workflow.selectInputDevice("usb-1")

        XCTAssertTrue(model.status.hasPrefix("⚠️ save failed:"))
        XCTAssertTrue(model.statusIsError)
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
            now: Date.init,
            scheduleStatusClear: { _ in },
            copy: { _ in }
        )
        workflow.populatePreferences()

        workflow.commit()

        XCTAssertEqual(received.count, 0)
    }

    func testTightenedRetentionRefreshesVisibleHistory() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let config = makeConfig()
        try config.setHistoryRetention(.ninetyDays)
        let model = SettingsModel()
        let historyStore = JSONLHistoryStore(url: dir.appendingPathComponent("history.jsonl"))
        historyStore.append(entry(createdAt: now.addingTimeInterval(-10 * 86400), text: "old"))
        historyStore.append(entry(createdAt: now, text: "new"))
        let workflow = SettingsWorkflow(
            config: config,
            model: model,
            historyStore: historyStore,
            now: { now },
            scheduleStatusClear: { _ in },
            copy: { _ in }
        )
        workflow.populatePreferences()
        model.retention = .sevenDays

        workflow.commit()

        XCTAssertEqual(model.historyEntries.map(\.text), ["new"])
    }

    func testTightenedRetentionPreservesStreak() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let config = makeConfig()
        try config.setHistoryRetention(.ninetyDays)
        let model = SettingsModel()
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("retention-streak-history.jsonl"))
        let stats = JSONStatsStore(url: dir.appendingPathComponent("retention-streak-stats.json"))
        stats.advance(on: now, calendar: utcCalendar())
        let workflow = makeWorkflow(
            config: config,
            model: model,
            historyStore: store,
            statsStore: stats,
            now: { now },
            calendar: utcCalendar()
        )
        workflow.populatePreferences()
        workflow.populateHistory()
        model.retention = .sevenDays

        workflow.commit()

        XCTAssertEqual(model.currentStreak, 1)
    }

    func testCopyHistoryWritesDisplayedTextToIsolatedPasteboard() {
        let pasteboard = NSPasteboard(name: .init("SettingsWorkflowTests.copy.\(UUID())"))
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model, pasteboard: pasteboard)
        let row = entry(createdAt: Date(), text: "polished words")

        workflow.performHistoryCommand(.copyDisplayed, for: row)

        XCTAssertEqual(pasteboard.string(forType: .string), "polished words")
    }

    func testCopyRawHistoryWritesTranscriptToIsolatedPasteboard() {
        let pasteboard = NSPasteboard(name: .init("SettingsWorkflowTests.copyRaw.\(UUID())"))
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model, pasteboard: pasteboard)
        let row = entry(createdAt: Date(), text: "polished words")

        workflow.performHistoryCommand(.copyRaw, for: row)

        XCTAssertEqual(pasteboard.string(forType: .string), "polished words raw")
    }

    func testFlagHistoryTogglesAndPublishesPersistedEntry() {
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("flag-history.jsonl"))
        let row = entry(createdAt: Date(), text: "remember this")
        store.append(row)
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model, historyStore: store)

        workflow.performHistoryCommand(.toggleFlag, for: row)

        XCTAssertEqual(model.historyEntries.map(\.flagged), [true])
    }

    func testFlagHistoryPublishesStoredEntryWhenPersistenceFails() {
        let row = entry(createdAt: Date(), text: "unchanged")
        let store = NonPersistingHistoryStore(entries: [row])
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model, historyStore: store)

        workflow.flagHistory(row)

        XCTAssertEqual(model.historyEntries.map(\.flagged), [false])
    }

    func testObservedAppendPrependsHistoryAndRefreshesStreak() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("observed-history.jsonl"))
        let stats = JSONStatsStore(url: dir.appendingPathComponent("observed-stats.json"))
        stats.advance(on: now, calendar: utcCalendar())
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(
            config: config,
            model: model,
            historyStore: store,
            statsStore: stats,
            now: { now },
            calendar: utcCalendar()
        )
        workflow.observeHistoryAppends()

        store.append(entry(createdAt: now, text: "just spoken"))
        await waitUntil { model.historyEntries.count == 1 }

        XCTAssertEqual([model.historyEntries.first?.text, model.currentStreak.map(String.init)], ["just spoken", "1"])
    }

    func testObservedAppendDoesNotDuplicateReloadedEntry() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("duplicate-history.jsonl"))
        let stats = JSONStatsStore(url: dir.appendingPathComponent("duplicate-stats.json"))
        stats.advance(on: now, calendar: utcCalendar())
        let row = entry(createdAt: now, text: "already loaded")
        let config = makeConfig()
        let model = SettingsModel()
        model.historyEntries = [row]
        let workflow = makeWorkflow(
            config: config,
            model: model,
            historyStore: store,
            statsStore: stats,
            now: { now },
            calendar: utcCalendar()
        )
        workflow.observeHistoryAppends()

        store.append(row)
        await waitUntil { model.currentStreak == 1 }

        XCTAssertEqual(model.historyEntries.map(\.id), [row.id])
    }

    func testFailedAppendDoesNotPopulateUnpersistedHistory() throws {
        let blocker = dir.appendingPathComponent("not-a-directory")
        try Data().write(to: blocker)
        let store = JSONLHistoryStore(url: blocker.appendingPathComponent("history.jsonl"))
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model, historyStore: store)

        store.append(entry(createdAt: Date(), text: "cannot persist"))
        workflow.populateHistory()

        XCTAssertTrue(model.historyEntries.isEmpty)
    }

    func testRerunPolishPublishesPersistedCompletion() async {
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("rerun-history.jsonl"))
        var row = entry(createdAt: Date(), text: "earlier words")
        row.rawText = "hey can you send the quarterly numbers over to the finance team when you get a chance"
        store.append(row)
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(
            config: config,
            model: model,
            historyStore: store,
            polish: { _, _ in
                "Hey, can you send the quarterly numbers over to the finance team when you get a chance?"
            }
        )

        let task = workflow.performHistoryCommand(.rerunPolish(modeName: "Clean"), for: row)
        await task?.value

        XCTAssertEqual(
            model.historyEntries.first?.text,
            "Hey, can you send the quarterly numbers over to the finance team when you get a chance?"
        )
    }

    func testRerunPolishPublishesFallbackCompletion() async {
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("rerun-fallback.jsonl"))
        var row = entry(createdAt: Date(), text: "earlier words")
        row.rawText = "hey can you send the quarterly numbers over to the finance team when you get a chance"
        store.append(row)
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(
            config: config,
            model: model,
            historyStore: store,
            polish: { _, _ in
                "I'm sorry, I can't help with that."
            }
        )

        await workflow.rerunPolish(row, modeName: "Clean")

        XCTAssertEqual(model.historyEntries.first?.text, row.rawText)
    }

    func testRerunPolishMissingEntryKeepsPersistedHistory() async {
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("rerun-missing.jsonl"))
        let kept = entry(createdAt: Date(), text: "kept words")
        store.append(kept)
        var missing = entry(createdAt: Date(), text: "missing words")
        missing.rawText = "please summarize the quarterly revenue figures for the board report"
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(
            config: config,
            model: model,
            historyStore: store,
            polish: { _, _ in "Please summarize the quarterly revenue figures for the board report." }
        )

        await workflow.rerunPolish(missing, modeName: "Clean")

        XCTAssertEqual(model.historyEntries.map(\.id), [kept.id])
    }

    func testDeleteHistoryPublishesRemainingPersistedEntries() {
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("delete-history.jsonl"))
        let removed = entry(createdAt: Date(), text: "remove me")
        let kept = entry(createdAt: Date(), text: "keep me")
        store.append(removed)
        store.append(kept)
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model, historyStore: store)

        workflow.performHistoryCommand(.delete, for: removed)

        XCTAssertEqual(model.historyEntries.map(\.text), ["keep me"])
    }

    func testDeletingMissingHistoryEntryKeepsPersistedEntries() {
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("missing-history.jsonl"))
        let kept = entry(createdAt: Date(), text: "keep me")
        store.append(kept)
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model, historyStore: store)

        workflow.deleteHistory(entry(createdAt: Date(), text: "not stored"))

        XCTAssertEqual(model.historyEntries.map(\.text), ["keep me"])
    }

    func testDeleteHistoryPreservesStreak() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("delete-streak-history.jsonl"))
        let row = entry(createdAt: now, text: "remove me")
        store.append(row)
        let stats = JSONStatsStore(url: dir.appendingPathComponent("delete-streak-stats.json"))
        stats.advance(on: now, calendar: utcCalendar())
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(
            config: config,
            model: model,
            historyStore: store,
            statsStore: stats,
            now: { now },
            calendar: utcCalendar()
        )
        workflow.populateHistory()

        workflow.deleteHistory(row)

        XCTAssertEqual(model.currentStreak, 1)
    }

    func testClearHistoryClearsEntriesAndResetsStreak() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("clear-history.jsonl"))
        store.append(entry(createdAt: now, text: "erase me"))
        let stats = JSONStatsStore(url: dir.appendingPathComponent("clear-stats.json"), now: { now })
        stats.advance(on: now, calendar: utcCalendar())
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(
            config: config,
            model: model,
            historyStore: store,
            statsStore: stats,
            now: { now },
            calendar: utcCalendar()
        )

        workflow.clearHistory()

        XCTAssertEqual([model.historyEntries.count, model.currentStreak ?? 0], [0, 0])
    }

    func testPopulateHistoryLoadsEntriesAndCurrentStreak() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("populate-history.jsonl"))
        store.append(entry(createdAt: now, text: "stored words"))
        let stats = JSONStatsStore(url: dir.appendingPathComponent("populate-stats.json"))
        stats.advance(on: now, calendar: utcCalendar())
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(
            config: config,
            model: model,
            historyStore: store,
            statsStore: stats,
            now: { now },
            calendar: utcCalendar()
        )

        workflow.populateHistory()

        XCTAssertEqual([model.historyEntries.first?.text, model.currentStreak.map(String.init)], ["stored words", "1"])
    }

    func testSelectingLLMModelPersistsTheChoice() {
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model)
        workflow.populatePreferences()

        workflow.selectLLMModel("llama3.2:3b")

        XCTAssertEqual(config.llmModel, "llama3.2:3b")
    }

    func testSelectingLLMModelUpdatesEveryModeFromTheGlobalPane() {
        let config = Config.defaultConfig(
            path: dir.appendingPathComponent("global-model-config.json")
        )
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model)
        workflow.populatePreferences()

        workflow.selectLLMModel("llama3.2:3b")

        XCTAssertEqual(
            config.orderedModes.map(\.llmModel),
            ["llama3.2:3b", "llama3.2:3b"]
        )
    }

    func testRefreshingLLMModelsPublishesTheBoundaryResult() async {
        let config = makeConfig()
        let model = SettingsModel()
        let effects = makeModelEffects(
            list: { [.init(name: "llama3.2:3b", sizeBytes: 42)] }
        )
        let workflow = makeWorkflow(config: config, model: model, effects: effects)

        workflow.refreshLLMModels()
        await waitUntil { model.installed != nil }

        XCTAssertEqual(model.installed?.map(\.name), ["llama3.2:3b"])
    }

    func testRefreshingLLMModelsIgnoresAnOlderResult() async {
        let config = makeConfig()
        let model = SettingsModel()
        let lists = SuspendedLLMLists()
        let workflow = makeWorkflow(
            config: config,
            model: model,
            effects: makeModelEffects(list: lists.run)
        )

        workflow.refreshLLMModels()
        await waitUntil { lists.requestCount == 1 }
        workflow.refreshLLMModels()
        await waitUntil { lists.requestCount == 2 }
        lists.finish(request: 2, with: [.init(name: "newest", sizeBytes: 2)])
        await waitUntil { model.installed?.first?.name == "newest" }

        lists.finish(request: 1, with: [.init(name: "stale", sizeBytes: 1)])
        await Task.yield()

        XCTAssertEqual(model.installed?.map(\.name), ["newest"])
    }

    func testInstallingLLMModelSelectsAndRefreshesIt() async {
        let config = makeConfig()
        let model = SettingsModel()
        model.customModel = "llama3.2:3b"
        let effects = makeModelEffects(
            list: { [.init(name: "llama3.2:3b", sizeBytes: 42)] },
            pull: { _, _ in nil }
        )
        let workflow = makeWorkflow(config: config, model: model, effects: effects)
        workflow.populatePreferences()

        workflow.installLLMModel("llama3.2:3b")
        await waitUntil { model.installed != nil }

        XCTAssertEqual(
            LLMInstallCompletion(
                selectedModel: model.selectedModel, persistedModel: config.llmModel,
                pullingModel: model.pullingModel, customModel: model.customModel,
                installed: model.installed?.map(\.name)
            ),
            LLMInstallCompletion(
                selectedModel: "llama3.2:3b", persistedModel: "llama3.2:3b",
                pullingModel: nil, customModel: "", installed: ["llama3.2:3b"]
            )
        )
    }

    func testLLMInstallPublishesProgress() async {
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(
            config: config,
            model: model,
            effects: makeModelEffects(pull: { _, progress in
                progress("downloading", 0.75)
                return nil
            })
        )
        workflow.populatePreferences()

        workflow.installLLMModel("llama3.2:3b")
        await waitUntil { model.pullFraction != nil }

        XCTAssertEqual(
            LLMProgressState(status: model.pullStatus, fraction: model.pullFraction),
            LLMProgressState(status: "downloading", fraction: 0.75)
        )
    }

    func testFailedLLMInstallPreservesSelectionAndReportsError() async {
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(
            config: config,
            model: model,
            effects: makeModelEffects(pull: { _, _ in "connection refused" })
        )
        workflow.populatePreferences()

        workflow.installLLMModel("llama3.2:3b")
        await waitUntil { model.pullingModel == nil }

        XCTAssertEqual(
            LLMInstallState(
                selectedModel: model.selectedModel, persistedModel: config.llmModel,
                pullingModel: model.pullingModel, progressStatus: model.pullStatus,
                progressFraction: model.pullFraction, error: model.pullError,
                customModel: model.customModel, installed: model.installed?.map(\.name)
            ),
            LLMInstallState(
                selectedModel: "qwen2.5:3b", persistedModel: "qwen2.5:3b",
                pullingModel: nil, progressStatus: "contacting Ollama…", progressFraction: nil,
                error: "Couldn't install llama3.2:3b: connection refused",
                customModel: "", installed: nil
            )
        )
    }

    func testDeletingLLMModelRefreshesInstalledModels() async {
        let config = makeConfig()
        let model = SettingsModel()
        var deleted: String?
        let workflow = makeWorkflow(
            config: config,
            model: model,
            effects: makeModelEffects(
                list: { [] },
                deleteLLM: { name in deleted = name
                    return nil
                }
            )
        )

        workflow.deleteLLMModel("old:latest")
        await waitUntil { model.installed != nil }

        XCTAssertEqual([deleted, model.deletingModel], ["old:latest", nil])
    }

    func testFailedLLMDeleteReportsErrorWithoutRefreshing() async {
        let config = makeConfig()
        let model = SettingsModel()
        var listCount = 0
        let workflow = makeWorkflow(
            config: config,
            model: model,
            effects: makeModelEffects(
                list: { listCount += 1
                    return []
                },
                deleteLLM: { _ in "busy" }
            )
        )

        workflow.deleteLLMModel("old:latest")
        await waitUntil { model.deletingModel == nil }

        XCTAssertEqual([model.deleteError, String(listCount)], ["Couldn't uninstall old:latest: busy", "0"])
    }

    func testSelectingASRModelPersistsTheChoice() {
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model)
        workflow.populatePreferences()

        workflow.selectASRModel("whisper-small")

        XCTAssertEqual([model.asrModel, config.asrModel], ["whisper-small", "whisper-small"])
    }

    func testDownloadingASRModelMakesItAvailable() async {
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(
            config: config,
            model: model,
            effects: makeModelEffects(prepareASR: { _, _, _ in nil })
        )

        workflow.downloadASRModel("whisper-small")
        await waitUntil { model.asrDownloaded.contains("whisper-small") }

        XCTAssertEqual(model.asrDownloaded, [ASRModelCatalog.defaultID, "whisper-small"])
    }

    func testASRDownloadPublishesProgressWhileRunning() async {
        let config = makeConfig()
        let model = SettingsModel()
        let preparation = SuspendedASRPreparation()
        let workflow = makeWorkflow(
            config: config,
            model: model,
            effects: makeModelEffects(prepareASR: preparation.run)
        )
        workflow.downloadASRModel("whisper-small")
        await waitUntil { preparation.started }

        preparation.report(fraction: 0.6, loading: true)

        XCTAssertEqual(
            ASRProgressState(fraction: model.asrDownloadFraction, preparing: model.asrPreparing),
            ASRProgressState(fraction: 0.6, preparing: true)
        )
        workflow.cancelASRDownload()
        preparation.finish(nil)
    }

    func testFailedASRDownloadPreservesAvailabilityAndReportsError() async {
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(
            config: config,
            model: model,
            effects: makeModelEffects(prepareASR: { _, _, _ in "disk full" })
        )

        workflow.downloadASRModel("whisper-small")
        await waitUntil { !model.asrDownloadError.isEmpty }

        XCTAssertEqual(
            ASRDownloadState(
                downloading: model.asrDownloading, fraction: model.asrDownloadFraction,
                preparing: model.asrPreparing, downloaded: model.asrDownloaded,
                error: model.asrDownloadError
            ),
            ASRDownloadState(
                downloading: nil, fraction: nil, preparing: false,
                downloaded: [ASRModelCatalog.defaultID],
                error: "Couldn't download Whisper small: disk full"
            )
        )
    }

    func testCancellingASRDownloadIgnoresLateProgressAndCompletion() async {
        let config = makeConfig()
        let model = SettingsModel()
        let preparation = SuspendedASRPreparation()
        let workflow = makeWorkflow(
            config: config,
            model: model,
            effects: makeModelEffects(prepareASR: preparation.run)
        )
        workflow.downloadASRModel("whisper-small")
        await waitUntil { preparation.started }

        workflow.cancelASRDownload()
        preparation.report(fraction: 1, loading: true)
        preparation.finish(nil)
        await Task.yield()

        XCTAssertEqual(
            ASRDownloadState(
                downloading: model.asrDownloading, fraction: model.asrDownloadFraction,
                preparing: model.asrPreparing, downloaded: model.asrDownloaded,
                error: model.asrDownloadError
            ),
            ASRDownloadState(
                downloading: nil, fraction: nil, preparing: false,
                downloaded: [ASRModelCatalog.defaultID], error: ""
            )
        )
    }

    func testDeletingActiveASRModelFallsBackToDefault() async throws {
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(
            config: config,
            model: model,
            effects: makeModelEffects(deleteASR: { _ in nil })
        )
        workflow.populatePreferences()
        model.asrModel = "whisper-small"
        try config.setASRModel("whisper-small")
        model.asrDownloaded.insert("whisper-small")

        workflow.deleteASRModel("whisper-small")
        await waitUntil { model.asrDeleting == nil }

        XCTAssertEqual(
            ASRDeleteState(
                deleting: model.asrDeleting, downloaded: model.asrDownloaded,
                selected: model.asrModel, persisted: config.asrModel,
                error: model.asrDeleteError
            ),
            ASRDeleteState(
                deleting: nil, downloaded: [ASRModelCatalog.defaultID],
                selected: ASRModelCatalog.defaultID, persisted: ASRModelCatalog.defaultID,
                error: ""
            )
        )
    }

    func testFailedASRDeleteKeepsModelAvailableAndReportsError() async {
        let config = makeConfig()
        let model = SettingsModel()
        model.asrDownloaded.insert("whisper-small")
        let workflow = makeWorkflow(
            config: config,
            model: model,
            effects: makeModelEffects(deleteASR: { _ in "permission denied" })
        )

        workflow.deleteASRModel("whisper-small")
        await waitUntil { model.asrDeleting == nil }

        XCTAssertEqual(
            ASRDeleteState(
                deleting: model.asrDeleting, downloaded: model.asrDownloaded,
                selected: model.asrModel, persisted: config.asrModel,
                error: model.asrDeleteError
            ),
            ASRDeleteState(
                deleting: nil,
                downloaded: [ASRModelCatalog.defaultID, "whisper-small"],
                selected: ASRModelCatalog.defaultID,
                persisted: ASRModelCatalog.defaultID,
                error: "Couldn't delete Whisper small: permission denied"
            )
        )
    }

    private func preferenceState(_ model: SettingsModel) -> PreferenceState {
        PreferenceState(
            pttKey: model.pttKey,
            toggleKey: model.toggleKey,
            pauseAudio: model.pauseAudio,
            appearance: model.appearance,
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
            appearance: config.appearance,
            saveHistory: config.saveHistory,
            retention: config.historyRetention,
            sidebarCollapsed: config.sidebarCollapsed,
            llmModel: config.llmModel,
            asrModel: config.asrModel,
            persistedHotkey: persisted.hotkey,
            persistedLLMModel: persisted.llmModel,
            persistedASRModel: persisted.asrModel,
            persistedAppearance: persisted.appearance
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

    private func makeWorkflow(
        config: Config,
        model: SettingsModel,
        effects: CannedModelManagers? = nil,
        pasteboard: NSPasteboard = NSPasteboard(name: .init("SettingsWorkflowTests.\(UUID())")),
        historyStore: HistoryStore? = nil,
        statsStore: StatsStore? = nil,
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_700_000_000) },
        calendar: Calendar = .current,
        polish: @escaping (String, Mode) async -> String = Pipeline.ollamaPolish,
        updates: (any SettingsUpdateChecking)? = nil,
        reportUpdate: @escaping (String) -> Void = { _ in }
    ) -> SettingsWorkflow {
        let historyStore = historyStore
            ?? JSONLHistoryStore(url: dir.appendingPathComponent("history.jsonl"))
        let statsStore = statsStore
            ?? JSONStatsStore(url: dir.appendingPathComponent("stats.json"))
        if let effects {
            return SettingsWorkflow(
                config: config,
                model: model,
                historyStore: historyStore,
                now: now,
                scheduleStatusClear: { _ in },
                llmModels: effects,
                asrModels: effects,
                copy: { text in
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                },
                statsStore: statsStore,
                calendar: calendar,
                polish: polish,
                updates: updates ?? CannedUpdateChecker(result: .failed),
                reportUpdate: reportUpdate
            )
        }
        return SettingsWorkflow(
            config: config,
            model: model,
            historyStore: historyStore,
            now: now,
            scheduleStatusClear: { _ in },
            copy: { text in
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            },
            statsStore: statsStore,
            calendar: calendar,
            polish: polish,
            updates: updates ?? CannedUpdateChecker(result: .failed),
            reportUpdate: reportUpdate
        )
    }

    private func makeModelEffects(
        list: @escaping @MainActor () async -> [OllamaClient.InstalledModel] = { [] },
        pull: @escaping @MainActor (
            String, @escaping LLMModelManaging.LLMProgress
        ) async -> String? = { _, _ in nil },
        deleteLLM: @escaping @MainActor (String) async -> String? = { _ in nil },
        prepareASR: @escaping @MainActor (
            ASRModelCatalog.Entry,
            @escaping ASRModelManaging.ASRProgress,
            @escaping ASRModelManaging.ASRLoading
        ) async -> String? = { _, _, _ in nil },
        deleteASR: @escaping @MainActor (ASRModelCatalog.Entry) async -> String? = { _ in nil }
    ) -> CannedModelManagers {
        CannedModelManagers(
            list: list,
            pull: pull,
            deleteLLM: deleteLLM,
            prepareASR: prepareASR,
            deleteASR: deleteASR
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0 ..< 100 where !condition() {
            await Task.yield()
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    private func makeConfig(path: URL? = nil) -> Config {
        let modes = [
            "Voice to Text": Mode(
                name: "Voice to Text", asrModel: ASRModelCatalog.defaultID,
                llmModel: nil, systemPrompt: nil, vocab: []
            ),
            "Clean": Mode(
                name: "Clean", asrModel: ASRModelCatalog.defaultID,
                llmModel: "qwen2.5:3b", systemPrompt: "Polish", vocab: [], expands: false
            ),
        ]
        return Config(
            activeMode: "Clean", hotkey: "F5", toggleHotkey: "F6", pauseAudio: false,
            appearance: .dark,
            saveHistory: false, historyRetention: .sevenDays, badgePosition: nil,
            sidebarCollapsed: true, modeOrder: ["Voice to Text", "Clean"], modes: modes,
            path: path ?? dir.appendingPathComponent("config.json")
        )
    }

    private func makeFailingConfig() -> Config {
        makeConfig(path: dir.appendingPathComponent("missing/config.json"))
    }

    private func entry(createdAt: Date, text: String) -> HistoryEntry {
        HistoryEntry(
            id: UUID(), createdAt: createdAt, text: text, rawText: text + " raw",
            isPolished: false, modeName: "Voice to Text", wordCount: 1,
            sourceApp: nil, durationMs: nil, flagged: false, flagReason: nil
        )
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }
}
