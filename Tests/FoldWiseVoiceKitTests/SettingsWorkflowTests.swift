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

    func testSelectingLLMModelPersistsTheChoice() {
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model)
        workflow.populatePreferences()

        workflow.selectLLMModel("llama3.2:3b")

        XCTAssertEqual(config.llmModel, "llama3.2:3b")
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

    func testDeletingActiveASRModelFallsBackToDefault() async {
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(
            config: config,
            model: model,
            effects: makeModelEffects(deleteASR: { _ in nil })
        )
        workflow.populatePreferences()
        model.asrModel = "whisper-small"
        config.setASRModel("whisper-small")
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

    private func makeWorkflow(
        config: Config,
        model: SettingsModel,
        effects: CannedModelManagers? = nil
    ) -> SettingsWorkflow {
        if let effects {
            return SettingsWorkflow(
                config: config,
                model: model,
                historyStore: JSONLHistoryStore(url: dir.appendingPathComponent("history.jsonl")),
                persist: {},
                now: { Date(timeIntervalSince1970: 1_700_000_000) },
                scheduleStatusClear: { _ in },
                llmModels: effects,
                asrModels: effects
            )
        }
        return SettingsWorkflow(
            config: config,
            model: model,
            historyStore: JSONLHistoryStore(url: dir.appendingPathComponent("history.jsonl")),
            persist: {},
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            scheduleStatusClear: { _ in }
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
