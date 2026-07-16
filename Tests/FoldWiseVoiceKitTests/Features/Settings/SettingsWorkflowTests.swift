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

    private struct SelectionState: Equatable {
        let committed: DictationSelection
        let projected: DictationSelection?
        let persisted: DictationSelection
        let statusIsError: Bool
    }

    private struct FailedSelectionState: Equatable {
        let committed: DictationSelection
        let projected: DictationSelection?
        let reportsSelectionFailure: Bool
        let statusIsError: Bool
    }

    private struct AddEditorOpening: Equatable {
        let editor: ModeEditorState?
        let modes: [Mode]
        let selection: DictationSelection
    }

    private struct DuplicateEditorOpening: Equatable {
        let editor: ModeEditorState?
        let committedIDs: [ModeID]
    }

    private struct InvalidEditorSave: Equatable {
        let draft: ModeEditorDraft?
        let issues: ModeEditorIssues?
        let modeNames: [String]
        let selection: DictationSelection
    }

    private struct AddedModeResult: Equatable {
        let editorDismissed: Bool
        let names: [String]
        let models: [String?]
        let addedTransformation: ModeTransformation?
        let addedPrompt: String?
        let addedVocabulary: [String]?
        let addedHasNewID: Bool
        let selectionMatchesAddedID: Bool
        let persistedMatchesLive: Bool
        let projectedSelection: DictationSelection?
    }

    private struct DuplicatedModeResult: Equatable {
        let names: [String]
        let copiedSettings: Bool
        let mintedDistinctID: Bool
        let selection: DictationSelection
        let persistedModes: [Mode]
    }

    private struct ReorderedModeResult: Equatable {
        let names: [String]
        let selection: DictationSelection
        let projectedNames: [String]
        let menuBarNames: [String]
        let badgeMenuNames: [String]
        let badgeModeName: String
        let badgeState: BadgeState
        let nextCycleModeID: ModeID?
        let persistedNames: [String]
        let changes: [Config.ChangeSet]
    }

    private struct DeletedModeResult: Equatable {
        let names: [String]
        let selection: DictationSelection
        let persistedSelection: DictationSelection
        let retainedHistoryModeID: ModeID?
        let installedModels: [String]
        let confirmationDismissed: Bool
    }

    private struct UnselectedDeletionResult: Equatable {
        let names: [String]
        let activeMode: String
        let selection: DictationSelection
    }

    private struct ZeroModeResult: Equatable {
        let configIsEmpty: Bool
        let selection: DictationSelection
        let settingsIsEmpty: Bool
        let projectionIsEmpty: Bool
        let systemSelectionIsSelected: Bool
    }

    private struct FailedLifecycleResult: Equatable {
        let modes: [Mode]
        let selection: DictationSelection
        let projectedModes: [Mode]
        let notifications: [Config.ChangeSet]
        let liveSurfacesUnchanged: Bool
        let retryID: ModeID?
        let errorMatchesOperation: Bool
        let fileExists: Bool
    }

    private struct FailedDuplicateResult: Equatable {
        let modes: [Mode]
        let selection: DictationSelection
        let settingsUnchanged: Bool
        let purpose: ModeEditorPurpose?
        let actionTitle: String?
        let hasPersistenceError: Bool
        let liveSurfacesUnchanged: Bool
        let fileExists: Bool
    }

    private struct LiveModeSurfaceState: Equatable {
        let menuBarNames: [String]
        let badgeMenuNames: [String]
        let badgeModeName: String
        let badgeState: BadgeState
        let historyModeName: String
        let historyModeIcon: String
        let historyModeIsDeleted: Bool
        let nextCycleModeID: ModeID?
    }

    private struct LiveModeSurfaces {
        let menuBar: MenuBarController
        let menuBarMenu: NSMenu
        let badge: BadgeController
        let badgeMenu: NSMenu
        let historyEntry: HistoryEntry
    }

    private struct SettingsModeState: Equatable {
        let modes: [Mode]
        let selection: ModeSelectionProjection
    }

    private struct EditorRetryResult: Equatable {
        let failedDraft: ModeEditorDraft?
        let failedActionTitle: String?
        let failedErrorIsVisible: Bool
        let failedModeNames: [String]
        let failedSelection: DictationSelection
        let failedSettingsUnchanged: Bool
        let failedLiveSurfacesUnchanged: Bool
        let retryDismissed: Bool
        let retryModeNames: [String]
        let retryPersisted: Bool
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
                sidebarCollapsed: true,
                selectedModel: "qwen2.5:3b", asrModel: ASRModelCatalog.defaultID,
                status: ""
            )
        )
    }

    func testModeLibraryChangesRefreshOpenHistoryInputs() throws {
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model)
        workflow.populatePreferences()

        try config.replaceModes([], selection: .voiceToText)

        XCTAssertTrue(model.modes.isEmpty)
    }

    func testExternalSelectionChangesRefreshOpenModesProjection() throws {
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model)
        workflow.populatePreferences()

        try config.select(.voiceToText)

        XCTAssertEqual(
            model.modeSelection.items.first(where: \.isSelected)?.id,
            .voiceToText
        )
    }

    func testSelectingModeCommitsStableIDAndRefreshesProjection() throws {
        let config = Config.defaultConfig(path: dir.appendingPathComponent("selection.json"))
        try config.save()
        let emailID = try XCTUnwrap(config.orderedModes.last?.id)
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model)
        workflow.populatePreferences()

        workflow.selectMode(.mode(emailID))

        XCTAssertEqual(
            SelectionState(
                committed: config.selection,
                projected: model.modeSelection.items.first(where: \.isSelected)?.id,
                persisted: try Config.load(from: config.path).selection,
                statusIsError: model.statusIsError
            ),
            SelectionState(
                committed: .mode(emailID),
                projected: .mode(emailID),
                persisted: .mode(emailID),
                statusIsError: false
            )
        )
    }

    func testFailedModeSelectionKeepsCommittedProjectionAndReportsRecovery() throws {
        let path = dir.appendingPathComponent("missing/selection.json")
        let config = Config.defaultConfig(path: path)
        let original = config.selection
        let emailID = try XCTUnwrap(config.orderedModes.last?.id)
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model)
        workflow.populatePreferences()

        workflow.selectMode(.mode(emailID))

        XCTAssertEqual(
            FailedSelectionState(
                committed: config.selection,
                projected: model.modeSelection.items.first(where: \.isSelected)?.id,
                reportsSelectionFailure: model.status.contains("couldn’t select Mode"),
                statusIsError: model.statusIsError
            ),
            FailedSelectionState(
                committed: original,
                projected: original,
                reportsSelectionFailure: true,
                statusIsError: true
            )
        )
    }

    func testBeginAddModeOpensIsolatedDraftUsingInstalledModel() {
        let config = makeConfig()
        let model = SettingsModel()
        model.installed = [.init(name: "llama3.2:3b", sizeBytes: 42)]
        let workflow = makeWorkflow(config: config, model: model)

        workflow.beginAddMode()

        XCTAssertEqual(
            AddEditorOpening(
                editor: model.modeEditor,
                modes: config.orderedModes,
                selection: config.selection
            ),
            AddEditorOpening(
                editor: ModeEditorState(
                    purpose: .add,
                    draft: ModeEditorDraft(
                        name: "",
                        icon: "wand.and.sparkles",
                        model: "llama3.2:3b",
                        transformation: .inPlace,
                        systemPrompt: "",
                        vocabularyText: ""
                    )
                ),
                modes: config.orderedModes,
                selection: config.selection
            )
        )
    }

    func testBeginEditModeCopiesStableModeWhenModelBecameUnavailable() throws {
        let config = makeConfig()
        let mode = try XCTUnwrap(config.orderedModes.first)
        let modeID = try XCTUnwrap(mode.id)
        let model = SettingsModel()
        model.installed = [.init(name: "llama3.2:3b", sizeBytes: 42)]
        let workflow = makeWorkflow(config: config, model: model)

        workflow.beginEditMode(modeID)

        XCTAssertEqual(
            model.modeEditor,
            ModeEditorState(
                purpose: .edit(modeID),
                draft: ModeEditorDraft(
                    name: "Clean",
                    icon: "text.bubble",
                    model: "qwen2.5:3b",
                    transformation: .inPlace,
                    systemPrompt: "Polish",
                    vocabularyText: ""
                )
            )
        )
    }

    func testBeginDuplicateModeCopiesSettingsWithoutMintingAnID() throws {
        let config = makeConfig()
        let source = try XCTUnwrap(config.orderedModes.first)
        let sourceID = try XCTUnwrap(source.id)
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model)

        workflow.beginDuplicateMode(sourceID)

        XCTAssertEqual(
            DuplicateEditorOpening(
                editor: model.modeEditor,
                committedIDs: config.orderedModes.compactMap(\.id)
            ),
            DuplicateEditorOpening(
                editor: ModeEditorState(
                    purpose: .duplicate(sourceID),
                    draft: ModeEditorDraft(
                        name: "Clean Copy",
                        icon: "text.bubble",
                        model: "qwen2.5:3b",
                        transformation: .inPlace,
                        systemPrompt: "Polish",
                        vocabularyText: ""
                    )
                ),
                committedIDs: [sourceID]
            )
        )
    }

    func testSaveModeEditorReportsAllValidationWithoutChangingConfig() throws {
        let config = makeConfig()
        let model = SettingsModel()
        model.installed = [.init(name: "qwen2.5:3b", sizeBytes: 42)]
        let workflow = makeWorkflow(config: config, model: model)
        workflow.beginAddMode()
        var editor = try XCTUnwrap(model.modeEditor)
        editor.draft.name = "  clean  "
        editor.draft.model = "missing:latest"
        editor.draft.systemPrompt = "  \n  "
        model.modeEditor = editor

        workflow.saveModeEditor()

        XCTAssertEqual(
            InvalidEditorSave(
                draft: model.modeEditor?.draft,
                issues: model.modeEditor?.issues,
                modeNames: config.orderedModes.map(\.name),
                selection: config.selection
            ),
            InvalidEditorSave(
                draft: editor.draft,
                issues: ModeEditorIssues(
                    name: "A Mode named 'clean' already exists.",
                    model: "missing:latest isn't installed. Install it in Models before saving.",
                    systemPrompt: "Enter Polish instructions."
                ),
                modeNames: ["Clean"],
                selection: config.selection
            )
        )
    }

    func testSaveModeEditorReportsPendingModelInventoryWithoutCallingModelUnavailable() throws {
        let config = makeConfig()
        let modeID = try XCTUnwrap(config.orderedModes.first?.id)
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model)
        workflow.beginEditMode(modeID)

        workflow.saveModeEditor()

        XCTAssertEqual(
            model.modeEditor?.issues.model,
            "Installed AI models are still loading. Try again in a moment."
        )
    }

    func testCancelModeEditorDiscardsDraftWithoutChangingConfig() throws {
        let config = makeConfig()
        let originalModes = config.orderedModes
        let originalSelection = config.selection
        let model = SettingsModel()
        model.installed = [.init(name: "qwen2.5:3b", sizeBytes: 42)]
        let workflow = makeWorkflow(config: config, model: model)
        workflow.beginAddMode()
        var editor = try XCTUnwrap(model.modeEditor)
        editor.draft.name = "Discard me"
        editor.draft.systemPrompt = "Discard these instructions"
        model.modeEditor = editor

        workflow.cancelModeEditor()

        XCTAssertEqual(
            AddEditorOpening(
                editor: model.modeEditor,
                modes: config.orderedModes,
                selection: config.selection
            ),
            AddEditorOpening(
                editor: nil,
                modes: originalModes,
                selection: originalSelection
            )
        )
    }

    func testSaveAddAppendsNormalizesActivatesAndPersistsOneMode() throws {
        let config = makeConfig()
        let originalID = try XCTUnwrap(config.orderedModes.first?.id)
        let model = SettingsModel()
        model.installed = [
            .init(name: "qwen2.5:3b", sizeBytes: 42),
            .init(name: "llama3.2:3b", sizeBytes: 42),
        ]
        let workflow = makeWorkflow(config: config, model: model)
        workflow.populatePreferences()
        workflow.beginAddMode()
        var editor = try XCTUnwrap(model.modeEditor)
        editor.draft = ModeEditorDraft(
            name: "  Team   Update ",
            icon: "person.3",
            model: " llama3.2:3b ",
            transformation: .expanding,
            systemPrompt: "  Turn this into a concise update.  ",
            vocabularyText: " FoldWise\nfoldwise\nBuenos Aires "
        )
        model.modeEditor = editor

        workflow.saveModeEditor()

        let added = try XCTUnwrap(config.orderedModes.last)
        let addedID = try XCTUnwrap(added.id)
        let persisted = try Config.load(from: config.path)
        XCTAssertEqual(
            AddedModeResult(
                editorDismissed: model.modeEditor == nil,
                names: config.orderedModes.map(\.name),
                models: config.orderedModes.map(\.llmModel),
                addedTransformation: added.transformation,
                addedPrompt: added.systemPrompt,
                addedVocabulary: added.vocab,
                addedHasNewID: addedID != originalID,
                selectionMatchesAddedID: config.selection == .mode(addedID),
                persistedMatchesLive: persisted.orderedModes == config.orderedModes
                    && persisted.selection == config.selection,
                projectedSelection: model.modeSelection.items.first(where: \.isSelected)?.id
            ),
            AddedModeResult(
                editorDismissed: true,
                names: ["Clean", "Team Update"],
                models: ["qwen2.5:3b", "llama3.2:3b"],
                addedTransformation: .expanding,
                addedPrompt: "Turn this into a concise update.",
                addedVocabulary: ["FoldWise", "Buenos Aires"],
                addedHasNewID: true,
                selectionMatchesAddedID: true,
                persistedMatchesLive: true,
                projectedSelection: .mode(addedID)
            )
        )
    }

    func testSaveDuplicateInsertsAfterSourceMintsIDAndActivates() throws {
        let config = Config.defaultConfig(path: dir.appendingPathComponent("duplicate.json"))
        let source = try XCTUnwrap(config.orderedModes.first)
        let sourceID = try XCTUnwrap(source.id)
        let model = SettingsModel()
        model.installed = [.init(name: "qwen2.5:3b", sizeBytes: 42)]
        let workflow = makeWorkflow(config: config, model: model)
        workflow.populatePreferences()
        workflow.beginDuplicateMode(sourceID)

        workflow.saveModeEditor()

        let duplicate = try XCTUnwrap(config.orderedModes.dropFirst().first)
        let duplicateID = try XCTUnwrap(duplicate.id)
        XCTAssertEqual(
            DuplicatedModeResult(
                names: config.orderedModes.map(\.name),
                copiedSettings: duplicate.icon == source.icon
                    && duplicate.llmModel == source.llmModel
                    && duplicate.transformation == source.transformation
                    && duplicate.systemPrompt == source.systemPrompt
                    && duplicate.vocab == source.vocab,
                mintedDistinctID: duplicateID != sourceID,
                selection: config.selection,
                persistedModes: try Config.load(from: config.path).orderedModes
            ),
            DuplicatedModeResult(
                names: ["Casual", "Casual Copy", "Email"],
                copiedSettings: true,
                mintedDistinctID: true,
                selection: .mode(duplicateID),
                persistedModes: config.orderedModes
            )
        )
    }

    func testMoveModePersistsSoleOrderAndPreservesStableSelection() throws {
        let config = Config.defaultConfig(path: dir.appendingPathComponent("reorder.json"))
        let selectedID = try XCTUnwrap(config.orderedModes.first?.id)
        let thirdID = ModeID.random()
        let thirdMode = Mode(
            id: thirdID,
            name: "Meeting",
            icon: "person.3",
            asrModel: config.asrModel,
            llmModel: "qwen2.5:3b",
            transformation: .expanding,
            systemPrompt: "Turn this into meeting notes.",
            vocabulary: []
        )
        try config.replaceModes(
            config.orderedModes + [thirdMode],
            selection: .mode(selectedID)
        )
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model)
        let menuBarMenu = NSMenu()
        let menuBar = MenuBarController(
            config: config,
            onSettings: {},
            onCheckForUpdates: {},
            onModeSelectionError: {},
            onQuit: {},
            menu: menuBarMenu
        )
        let badge = BadgeController(config: config, onOpenApp: {})
        let badgeMenu = badge.makeLiveModeMenu()
        workflow.populatePreferences()
        var changes: [Config.ChangeSet] = []
        config.onChange { changes.append($0) }

        workflow.moveMode(selectedID, direction: .down)

        XCTAssertEqual(
            ReorderedModeResult(
                names: config.orderedModes.map(\.name),
                selection: config.selection,
                projectedNames: model.modeSelection.editableItems.map(\.name),
                menuBarNames: modeNames(in: menuBarMenu),
                badgeMenuNames: modeNames(in: badgeMenu),
                badgeModeName: badge.model.activeModeName,
                badgeState: badge.model.state,
                nextCycleModeID: config.modeCycleSuccessor(after: selectedID),
                persistedNames: try Config.load(from: config.path).orderedModes.map(\.name),
                changes: changes
            ),
            ReorderedModeResult(
                names: ["Email", "Casual", "Meeting"],
                selection: .mode(selectedID),
                projectedNames: ["Email", "Casual", "Meeting"],
                menuBarNames: ["Voice to Text", "Email", "Casual", "Meeting"],
                badgeMenuNames: ["Voice to Text", "Email", "Casual", "Meeting"],
                badgeModeName: "Casual",
                badgeState: .idle,
                nextCycleModeID: thirdID,
                persistedNames: ["Email", "Casual", "Meeting"],
                changes: [.modeLibrary]
            )
        )
        withExtendedLifetime(menuBar) {}
    }

    func testRequestModeDeletionExplainsHistoryAndModelRetention() throws {
        let config = Config.defaultConfig(path: dir.appendingPathComponent("delete-prompt.json"))
        let sourceID = try XCTUnwrap(config.orderedModes.first?.id)
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model)

        workflow.requestModeDeletion(sourceID)

        XCTAssertEqual(
            model.modePendingDeletion,
            ModeDeletionState(
                id: sourceID,
                title: "Delete Casual?",
                message: "Your History will remain. The qwen2.5:3b AI model will not be "
                    + "uninstalled."
            )
        )
    }

    func testConfirmSelectedModeDeletionFallsBackAndRetainsHistoryAndModel() throws {
        let config = Config.defaultConfig(path: dir.appendingPathComponent("delete-selected.json"))
        try config.save()
        let sourceID = try XCTUnwrap(config.orderedModes.first?.id)
        let historyStore = JSONLHistoryStore(url: dir.appendingPathComponent("delete-history.jsonl"))
        var history = entry(createdAt: Date(), text: "Saved words")
        history.modeName = "Casual"
        history.modeID = sourceID
        historyStore.append(history)
        let model = SettingsModel()
        model.installed = [.init(name: "qwen2.5:3b", sizeBytes: 42)]
        let workflow = makeWorkflow(
            config: config,
            model: model,
            historyStore: historyStore
        )
        workflow.populatePreferences()
        workflow.requestModeDeletion(sourceID)

        workflow.confirmModeDeletion()

        let persisted = try Config.load(from: config.path)
        XCTAssertEqual(
            DeletedModeResult(
                names: config.orderedModes.map(\.name),
                selection: config.selection,
                persistedSelection: persisted.selection,
                retainedHistoryModeID: historyStore.load().first?.modeID,
                installedModels: model.installed?.map(\.name) ?? [],
                confirmationDismissed: model.modePendingDeletion == nil
            ),
            DeletedModeResult(
                names: ["Email"],
                selection: .voiceToText,
                persistedSelection: .voiceToText,
                retainedHistoryModeID: sourceID,
                installedModels: ["qwen2.5:3b"],
                confirmationDismissed: true
            )
        )
    }

    func testConfirmUnselectedModeDeletionPreservesSelection() throws {
        let config = Config.defaultConfig(path: dir.appendingPathComponent("delete-unselected.json"))
        let selectedID = try XCTUnwrap(config.orderedModes.first?.id)
        let deletedID = try XCTUnwrap(config.orderedModes.last?.id)
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model)
        workflow.populatePreferences()
        workflow.requestModeDeletion(deletedID)

        workflow.confirmModeDeletion()

        XCTAssertEqual(
            UnselectedDeletionResult(
                names: config.orderedModes.map(\.name),
                activeMode: config.activeMode,
                selection: config.selection
            ),
            UnselectedDeletionResult(
                names: ["Casual"],
                activeMode: "Casual",
                selection: .mode(selectedID)
            )
        )
    }

    func testDeletingLastModePublishesInvitingZeroModeState() throws {
        let config = makeConfig()
        let deletedID = try XCTUnwrap(config.orderedModes.first?.id)
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model)
        workflow.populatePreferences()
        workflow.requestModeDeletion(deletedID)

        workflow.confirmModeDeletion()

        XCTAssertEqual(
            ZeroModeResult(
                configIsEmpty: config.orderedModes.isEmpty,
                selection: config.selection,
                settingsIsEmpty: model.modes.isEmpty,
                projectionIsEmpty: model.modeSelection.editableItems.isEmpty,
                systemSelectionIsSelected: model.modeSelection.systemItem.isSelected
            ),
            ZeroModeResult(
                configIsEmpty: true,
                selection: .voiceToText,
                settingsIsEmpty: true,
                projectionIsEmpty: true,
                systemSelectionIsSelected: true
            )
        )
    }

    func testFailedReorderKeepsCommittedLibrarySelectionAndProjection() throws {
        let config = Config.defaultConfig(
            path: dir.appendingPathComponent("missing-reorder/config.json")
        )
        let originalModes = config.orderedModes
        let originalSelection = config.selection
        let movedID = try XCTUnwrap(originalModes.first?.id)
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model)
        workflow.populatePreferences()
        let surfaces = try makeLiveModeSurfaces(config)
        let originalSurfaceState = liveModeSurfaceState(surfaces, config: config)
        var changes: [Config.ChangeSet] = []
        config.onChange { changes.append($0) }

        workflow.moveMode(movedID, direction: .down)

        XCTAssertEqual(
            FailedLifecycleResult(
                modes: config.orderedModes,
                selection: config.selection,
                projectedModes: model.modes,
                notifications: changes,
                liveSurfacesUnchanged: liveModeSurfaceState(surfaces, config: config)
                    == originalSurfaceState,
                retryID: nil,
                errorMatchesOperation: model.status.contains("couldn't reorder Mode"),
                fileExists: FileManager.default.fileExists(atPath: config.path.path)
            ),
            FailedLifecycleResult(
                modes: originalModes,
                selection: originalSelection,
                projectedModes: originalModes,
                notifications: [],
                liveSurfacesUnchanged: true,
                retryID: nil,
                errorMatchesOperation: true,
                fileExists: false
            )
        )
    }

    func testFailedDeleteKeepsCommittedStateAndConfirmationForRetry() throws {
        let config = Config.defaultConfig(
            path: dir.appendingPathComponent("missing-delete/config.json")
        )
        let originalModes = config.orderedModes
        let originalSelection = config.selection
        let deletedID = try XCTUnwrap(originalModes.first?.id)
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model)
        workflow.populatePreferences()
        workflow.requestModeDeletion(deletedID)
        let surfaces = try makeLiveModeSurfaces(config)
        let originalSurfaceState = liveModeSurfaceState(surfaces, config: config)
        var changes: [Config.ChangeSet] = []
        config.onChange { changes.append($0) }

        workflow.confirmModeDeletion()

        XCTAssertEqual(
            FailedLifecycleResult(
                modes: config.orderedModes,
                selection: config.selection,
                projectedModes: model.modes,
                notifications: changes,
                liveSurfacesUnchanged: liveModeSurfaceState(surfaces, config: config)
                    == originalSurfaceState,
                retryID: model.modePendingDeletion?.id,
                errorMatchesOperation: model.status.contains("couldn't delete Mode"),
                fileExists: FileManager.default.fileExists(atPath: config.path.path)
            ),
            FailedLifecycleResult(
                modes: originalModes,
                selection: originalSelection,
                projectedModes: originalModes,
                notifications: [],
                liveSurfacesUnchanged: true,
                retryID: deletedID,
                errorMatchesOperation: true,
                fileExists: false
            )
        )
    }

    func testFailedDuplicateKeepsDraftAndCommittedStateForRetry() throws {
        let config = Config.defaultConfig(
            path: dir.appendingPathComponent("missing-duplicate/config.json")
        )
        let originalModes = config.orderedModes
        let originalSelection = config.selection
        let sourceID = try XCTUnwrap(originalModes.first?.id)
        let model = SettingsModel()
        model.installed = [.init(name: "qwen2.5:3b", sizeBytes: 42)]
        let workflow = makeWorkflow(config: config, model: model)
        workflow.populatePreferences()
        let originalSettingsState = settingsModeState(model)
        workflow.beginDuplicateMode(sourceID)
        let surfaces = try makeLiveModeSurfaces(config)
        let originalSurfaceState = liveModeSurfaceState(surfaces, config: config)

        workflow.saveModeEditor()

        XCTAssertEqual(
            FailedDuplicateResult(
                modes: config.orderedModes,
                selection: config.selection,
                settingsUnchanged: settingsModeState(model) == originalSettingsState,
                purpose: model.modeEditor?.purpose,
                actionTitle: model.modeEditor?.saveActionTitle,
                hasPersistenceError: model.modeEditor?.persistenceError?.contains(
                    "Couldn't save Mode"
                ) == true,
                liveSurfacesUnchanged: liveModeSurfaceState(surfaces, config: config)
                    == originalSurfaceState,
                fileExists: FileManager.default.fileExists(atPath: config.path.path)
            ),
            FailedDuplicateResult(
                modes: originalModes,
                selection: originalSelection,
                settingsUnchanged: true,
                purpose: .duplicate(sourceID),
                actionTitle: "Retry",
                hasPersistenceError: true,
                liveSurfacesUnchanged: true,
                fileExists: false
            )
        )
    }

    func testSaveEditPreservesStableIDAndSelectionChangedWhileDraftWasOpen() throws {
        let config = makeConfig()
        let modeID = try XCTUnwrap(config.orderedModes.first?.id)
        let model = SettingsModel()
        model.installed = [.init(name: "llama3.2:3b", sizeBytes: 42)]
        let workflow = makeWorkflow(config: config, model: model)
        workflow.populatePreferences()
        workflow.beginEditMode(modeID)
        workflow.selectMode(.voiceToText)
        var editor = try XCTUnwrap(model.modeEditor)
        editor.draft.name = "  Renamed   Mode  "
        editor.draft.model = "llama3.2:3b"
        editor.draft.transformation = .expanding
        editor.draft.systemPrompt = "Reshape this while preserving meaning."
        model.modeEditor = editor

        workflow.saveModeEditor()

        let edited = try XCTUnwrap(config.orderedModes.first)
        let persisted = try Config.load(from: config.path)
        XCTAssertEqual(
            [
                edited.id?.rawValue,
                edited.name,
                edited.llmModel,
                edited.transformation.rawValue,
                config.selection == .voiceToText ? "voice_to_text" : "mode",
                persisted.selection == .voiceToText ? "voice_to_text" : "mode",
                model.modeEditor == nil ? "dismissed" : "open",
            ],
            [
                modeID.rawValue,
                "Renamed Mode",
                "llama3.2:3b",
                ModeTransformation.expanding.rawValue,
                "voice_to_text",
                "voice_to_text",
                "dismissed",
            ]
        )
    }

    func testSaveEditChangesOnlyTargetModesModelAssignment() throws {
        let config = Config.defaultConfig(path: dir.appendingPathComponent("owned-models.json"))
        let firstID = try XCTUnwrap(config.orderedModes.first?.id)
        let model = SettingsModel()
        model.installed = [
            .init(name: "qwen2.5:3b", sizeBytes: 42),
            .init(name: "llama3.2:3b", sizeBytes: 42),
        ]
        let workflow = makeWorkflow(config: config, model: model)
        workflow.beginEditMode(firstID)
        var editor = try XCTUnwrap(model.modeEditor)
        editor.draft.model = "llama3.2:3b"
        model.modeEditor = editor

        workflow.saveModeEditor()

        XCTAssertEqual(
            config.orderedModes.map(\.llmModel),
            ["llama3.2:3b", "qwen2.5:3b"]
        )
    }

    func testFailedSaveRetainsCompleteDraftAndRetryCommitsIt() throws {
        let config = makeFailingConfig()
        let originalSelection = config.selection
        let model = SettingsModel()
        model.installed = [.init(name: "qwen2.5:3b", sizeBytes: 42)]
        let workflow = makeWorkflow(config: config, model: model)
        workflow.populatePreferences()
        let originalSettingsState = settingsModeState(model)
        workflow.beginAddMode()
        var editor = try XCTUnwrap(model.modeEditor)
        editor.draft.name = "Retry Mode"
        editor.draft.systemPrompt = "Keep this complete draft."
        editor.draft.vocabularyText = "FoldWise\nBuenos Aires"
        model.modeEditor = editor
        let surfaces = try makeLiveModeSurfaces(config)
        let originalSurfaceState = liveModeSurfaceState(surfaces, config: config)

        workflow.saveModeEditor()

        let failedEditor = try XCTUnwrap(model.modeEditor)
        let failedModeNames = config.orderedModes.map(\.name)
        let failedSettingsUnchanged = settingsModeState(model) == originalSettingsState
        let failedLiveSurfacesUnchanged = liveModeSurfaceState(surfaces, config: config)
            == originalSurfaceState
        try FileManager.default.createDirectory(
            at: config.path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        workflow.saveModeEditor()
        let persisted = try Config.load(from: config.path)

        XCTAssertEqual(
            EditorRetryResult(
                failedDraft: failedEditor.draft,
                failedActionTitle: failedEditor.saveActionTitle,
                failedErrorIsVisible: failedEditor.persistenceError?.contains(
                    "Couldn't save Mode"
                ) == true,
                failedModeNames: failedModeNames,
                failedSelection: originalSelection,
                failedSettingsUnchanged: failedSettingsUnchanged,
                failedLiveSurfacesUnchanged: failedLiveSurfacesUnchanged,
                retryDismissed: model.modeEditor == nil,
                retryModeNames: config.orderedModes.map(\.name),
                retryPersisted: persisted.orderedModes == config.orderedModes
                    && persisted.selection == config.selection
            ),
            EditorRetryResult(
                failedDraft: editor.draft,
                failedActionTitle: "Retry",
                failedErrorIsVisible: true,
                failedModeNames: ["Clean"],
                failedSelection: originalSelection,
                failedSettingsUnchanged: true,
                failedLiveSurfacesUnchanged: true,
                retryDismissed: true,
                retryModeNames: ["Clean", "Retry Mode"],
                retryPersisted: true
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
        workflow.selectMode(.voiceToText)
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
        workflow.commit()

        XCTAssertTrue(model.configurationReadOnly)
        XCTAssertEqual(
            model.modeSelection.items.first(where: \.isSelected)?.id,
            .voiceToText
        )
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

    func testFinishRecordingCommitsCapturedModeCycleKey() {
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model)
        workflow.populatePreferences()
        workflow.beginRecording(.cycle)

        workflow.finishRecording(with: "F9")

        XCTAssertEqual(config.modeCycleHotkey, "F9")
        XCTAssertEqual(model.cycleKey, "F9")
        XCTAssertNil(model.recordingField)
    }

    func testCaptureSuspendsCommandsUntilCommitOrCancel() {
        let config = makeConfig()
        let model = SettingsModel()
        let gate = ShortcutCaptureGate()
        let workflow = makeWorkflow(config: config, model: model, captureGate: gate)
        workflow.populatePreferences()

        workflow.beginRecording(.cycle)
        XCTAssertTrue(gate.isCapturing)

        workflow.cancelRecording()
        XCTAssertFalse(gate.isCapturing)
    }

    func testCollisionIdentifiesOwnerAndRestoresCommittedShortcut() {
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model)
        workflow.populatePreferences()
        workflow.beginRecording(.cycle)

        workflow.finishRecording(with: " f5 ")

        XCTAssertNil(config.modeCycleHotkey)
        XCTAssertEqual(model.cycleKey, "")
        XCTAssertTrue(model.status.contains("Push to Talk"))
        XCTAssertTrue(model.statusIsError)
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

    func testConfigurationRecoveryDoesNotOpenModeEditor() throws {
        let path = dir.appendingPathComponent("invalid-mode-editor-config.json")
        let original = Data("invalid".utf8)
        try original.write(to: path)
        let config = Config.loadOrCreate(at: path)
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model)

        workflow.beginAddMode()

        XCTAssertEqual(
            [model.modeEditor == nil, try Data(contentsOf: path) == original],
            [true, true]
        )
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

        guard let modeID = config.orderedModes.first?.id else {
            return XCTFail("expected an editable Mode")
        }
        let task = workflow.performHistoryCommand(.rerunPolish(modeID: modeID), for: row)
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

        guard let modeID = config.orderedModes.first?.id else {
            return XCTFail("expected an editable Mode")
        }
        await workflow.rerunPolish(row, modeID: modeID)

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

        guard let modeID = config.orderedModes.first?.id else {
            return XCTFail("expected an editable Mode")
        }
        await workflow.rerunPolish(missing, modeID: modeID)

        XCTAssertEqual(model.historyEntries.map(\.id), [kept.id])
    }

    func testRerunPolishMissingModeKeepsEntryUnchanged() async {
        let result = await rerunPolishWithMissingMode()

        XCTAssertEqual(result.persistedText, "unchanged words")
    }

    func testRerunPolishMissingModeShowsRecoverableError() async {
        let result = await rerunPolishWithMissingMode()

        XCTAssertEqual(
            result.status,
            WorkflowStatus(
                message: "⚠️ Mode is no longer available. Choose another Mode.",
                isError: true
            )
        )
    }

    private func rerunPolishWithMissingMode() async -> MissingModeResult {
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("rerun-missing-mode.jsonl"))
        let row = entry(createdAt: Date(), text: "unchanged words")
        store.append(row)
        let config = makeConfig()
        let model = SettingsModel()
        let workflow = makeWorkflow(config: config, model: model, historyStore: store)

        await workflow.rerunPolish(row, modeID: .random())

        return MissingModeResult(
            persistedText: store.load().first?.text,
            status: WorkflowStatus(message: model.status, isError: model.statusIsError)
        )
    }

    func testRerunPolishFreezesModeAtExecutionStartAcrossDeletion() async throws {
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("rerun-frozen-mode.jsonl"))
        var row = entry(createdAt: Date(), text: "earlier words")
        row.rawText = "hey can you send the quarterly numbers over to the finance team when you get a chance"
        store.append(row)
        let config = makeConfig()
        let mode = try XCTUnwrap(config.orderedModes.first)
        let modeID = try XCTUnwrap(mode.id)
        let model = SettingsModel()
        let polishing = expectation(description: "reprocessing started")
        let finishPolishing = Latch()
        let receivedMode = ModeCapture()
        let workflow = makeWorkflow(
            config: config,
            model: model,
            historyStore: store,
            polish: { _, snapshot in
                receivedMode.value = snapshot
                polishing.fulfill()
                await finishPolishing.wait()
                return "Hey, can you send the quarterly numbers over to the finance team when you get a chance?"
            }
        )

        let task = Task { await workflow.rerunPolish(row, modeID: modeID) }
        await fulfillment(of: [polishing])
        try config.replaceModes([], selection: .voiceToText)
        await finishPolishing.open()
        await task.value

        let updated = try XCTUnwrap(store.load().first)
        XCTAssertEqual(
            [receivedMode.value?.name, updated.modeName, updated.modeID?.rawValue],
            ["Clean", "Clean", modeID.rawValue]
        )
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

    func testInstallingLLMModelRefreshesInventoryWithoutReassigningModes() async {
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
                selectedModel: "qwen2.5:3b", persistedModel: "qwen2.5:3b",
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

    private func makeLiveModeSurfaces(_ config: Config) throws -> LiveModeSurfaces {
        let menuBarMenu = NSMenu()
        let menuBar = MenuBarController(
            config: config,
            onSettings: {},
            onCheckForUpdates: {},
            onModeSelectionError: {},
            onQuit: {},
            menu: menuBarMenu
        )
        let badge = BadgeController(config: config, onOpenApp: {})
        let badgeMenu = badge.makeLiveModeMenu()
        let mode = try XCTUnwrap(config.orderedModes.first)
        var historyEntry = entry(createdAt: Date(timeIntervalSince1970: 1_700_000_000), text: "Saved")
        historyEntry.modeID = try XCTUnwrap(mode.id)
        historyEntry.modeName = mode.name
        return LiveModeSurfaces(
            menuBar: menuBar,
            menuBarMenu: menuBarMenu,
            badge: badge,
            badgeMenu: badgeMenu,
            historyEntry: historyEntry
        )
    }

    private func liveModeSurfaceState(
        _ surfaces: LiveModeSurfaces,
        config: Config
    ) -> LiveModeSurfaceState {
        withExtendedLifetime(surfaces.menuBar) {
            let history = DictationRowPresentation(
                entry: surfaces.historyEntry,
                modes: config.orderedModes
            )
            return LiveModeSurfaceState(
                menuBarNames: modeNames(in: surfaces.menuBarMenu),
                badgeMenuNames: modeNames(in: surfaces.badgeMenu),
                badgeModeName: surfaces.badge.model.activeModeName,
                badgeState: surfaces.badge.model.state,
                historyModeName: history.fullModeName,
                historyModeIcon: history.modeIcon,
                historyModeIsDeleted: history.isDeletedMode,
                nextCycleModeID: modeCycleSuccessor(in: config)
            )
        }
    }

    private func settingsModeState(_ model: SettingsModel) -> SettingsModeState {
        SettingsModeState(modes: model.modes, selection: model.modeSelection)
    }

    private func modeCycleSuccessor(in config: Config) -> ModeID? {
        guard case let .mode(id) = config.selection else { return nil }
        return config.modeCycleSuccessor(after: id)
    }

    private func modeNames(in menu: NSMenu) -> [String] {
        menu.items.compactMap { item in
            item.representedObject as? DictationSelection == nil ? nil : item.title
        }
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
        reportUpdate: @escaping (String) -> Void = { _ in },
        captureGate: ShortcutCaptureGate = ShortcutCaptureGate()
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
                reportUpdate: reportUpdate,
                captureGate: captureGate
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
            reportUpdate: reportUpdate,
            captureGate: captureGate
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

    private struct WorkflowStatus: Equatable {
        let message: String
        let isError: Bool
    }

    private struct MissingModeResult {
        let persistedText: String?
        let status: WorkflowStatus
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
