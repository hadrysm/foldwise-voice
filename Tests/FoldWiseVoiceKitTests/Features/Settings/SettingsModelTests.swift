import Observation
import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class SettingsModelTests: XCTestCase {
    func testHomeObservationInvalidatesForCurrentStreakChange() {
        let model = SettingsModel()
        let interface = model.homePaneInterface
        let invalidations = ObservationInvalidationCounter()

        withObservationTracking {
            _ = interface.projectionInput
            _ = interface.currentStreak
            _ = interface.pushToTalkKey
            _ = interface.permissionSnapshot
            _ = interface.effectiveASRModelName
            _ = interface.selectedPolishModel
            _ = interface.windowWidth
        } onChange: {
            invalidations.increment()
        }

        model.currentStreak = 3

        XCTAssertEqual(invalidations.value, 1)
    }

    func testHomeObservationIgnoresUnrelatedSoundChange() {
        let model = SettingsModel()
        let interface = model.homePaneInterface
        let invalidations = ObservationInvalidationCounter()

        withObservationTracking {
            _ = interface.projectionInput
            _ = interface.currentStreak
            _ = interface.pushToTalkKey
            _ = interface.permissionSnapshot
            _ = interface.effectiveASRModelName
            _ = interface.selectedPolishModel
            _ = interface.windowWidth
        } onChange: {
            invalidations.increment()
        }

        model.pauseAudio.toggle()

        XCTAssertEqual(invalidations.value, 0)
    }

    func testOutgoingHistoryObservationIgnoresAcceptedPaneSelection() {
        let model = SettingsModel()
        model.pane = .history
        let interface = model.historyPaneInterface
        let invalidations = ObservationInvalidationCounter()

        withObservationTracking {
            _ = interface.entries
            _ = interface.modes
            _ = interface.saveHistory
            _ = interface.retention
        } onChange: {
            invalidations.increment()
        }

        model.selectPane(.stats)

        XCTAssertEqual(invalidations.value, 0)
    }

    func testModelsObservationIgnoresUnrelatedShortcutChange() {
        let model = SettingsModel()
        let interface = model.modelsPaneInterface
        let invalidations = ObservationInvalidationCounter()

        withObservationTracking {
            _ = interface.asrSnapshot
            _ = interface.asrFailures
            _ = interface.polishState
            _ = interface.modes
            _ = interface.requestedPolishInspection
            _ = interface.customModel
            _ = interface.windowWidth
        } onChange: {
            invalidations.increment()
        }

        model.pttKey = "f18"

        XCTAssertEqual(invalidations.value, 0)
    }

    func testModesObservationIgnoresUnrelatedHistoryChange() {
        let model = SettingsModel()
        let interface = model.modesPaneInterface
        let invalidations = ObservationInvalidationCounter()

        withObservationTracking {
            _ = interface.modeSelection
            _ = interface.modes
            _ = interface.selectedEditableMode
            _ = interface.selectedEditableModeItem
            _ = interface.installed
        } onChange: {
            invalidations.increment()
        }

        model.historyEntries = [HistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1),
            text: "Unrelated history",
            rawText: "Unrelated history",
            isPolished: false,
            modeName: "Voice to Text",
            modeID: nil,
            wordCount: 2,
            sourceApp: nil,
            durationMs: 1000,
            flagged: false,
            flagReason: nil
        )]

        XCTAssertEqual(invalidations.value, 0)
    }

    func testPreferencesObservationIgnoresUnrelatedHistoryChange() {
        let model = SettingsModel()
        let interface = model.preferencesPaneInterface
        let invalidations = ObservationInvalidationCounter()

        withObservationTracking {
            _ = interface.permissionRecovery
            _ = interface.pttKey
            _ = interface.toggleKey
            _ = interface.cycleKey
            _ = interface.pauseAudio
            _ = interface.appearance
            _ = interface.inputState
            _ = interface.windowWidth
            _ = interface.shortcutListenerHealth
            _ = interface.canCheckForUpdates
            _ = interface.recordingField
            _ = interface.status
            _ = interface.statusIsError
            _ = interface.statusOwner
        } onChange: {
            invalidations.increment()
        }

        model.historyEntries = [HistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1),
            text: "Unrelated history",
            rawText: "Unrelated history",
            isPolished: false,
            modeName: "Voice to Text",
            modeID: nil,
            wordCount: 2,
            sourceApp: nil,
            durationMs: 1000,
            flagged: false,
            flagReason: nil
        )]

        XCTAssertEqual(invalidations.value, 0)
    }

    func testPaneInterfacesForwardDestinationCommands() {
        let model = SettingsModel()
        let modeID = ModeID.random()
        let entry = HistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1),
            text: "Test",
            rawText: "Test",
            isPolished: false,
            modeName: "Voice to Text",
            modeID: nil,
            wordCount: 1,
            sourceApp: nil,
            durationMs: 100,
            flagged: false,
            flagReason: nil
        )
        var events: [String] = []
        model.onCommit = { events.append("commit:\($0)") }
        model.onOpenPermissionRecovery = { events.append("permission") }
        model.onHistoryCommand = { _, command in events.append("history:\(command)") }
        model.onClearHistory = { events.append("clear-history") }
        model.onCancelASROperation = { events.append("cancel-asr") }
        model.onSelectASRModel = { events.append("select-asr:\($0)") }
        model.onDownloadASRModel = { events.append("download-asr:\($0)") }
        model.onRetryASRBootstrap = { events.append("retry-asr") }
        model.onInstallModel = { events.append("install-polish:\($0)") }
        model.onInstallCustomModel = { events.append("install-custom") }
        model.onRefreshModels = { events.append("refresh-polish") }
        model.onDeleteASRModel = { events.append("delete-asr:\($0)") }
        model.onDeleteModel = { events.append("delete-polish:\($0)") }
        model.onSelectMode = { events.append("select-mode:\($0)") }
        model.onAddMode = { events.append("add-mode") }
        model.onEditMode = { events.append("edit-mode:\($0)") }
        model.onDuplicateMode = { events.append("duplicate-mode:\($0)") }
        model.onMoveMode = { events.append("move-mode:\($0):\($1)") }
        model.onRequestModeDeletion = { events.append("delete-mode:\($0)") }
        model.onOpenShortcutPermissions = { events.append("shortcut-permission") }
        model.onSelectInputDevice = { events.append("input:\($0 ?? "default")") }
        model.onCheckUpdates = { events.append("updates") }
        model.onRecord = { events.append("record:\($0)") }

        let home = model.homePaneInterface
        home.openPermissionRecovery()
        home.performHistoryCommand(entry, .copyDisplayed)
        home.selectPane(.history)
        let history = model.historyPaneInterface
        history.setSaveHistory(false)
        history.setRetention(.forever)
        history.performHistoryCommand(entry, .delete)
        history.clearHistory()
        model.statsPaneInterface.openHistory()
        let models = model.modelsPaneInterface
        models.cancelASROperation()
        models.selectASRModel("asr")
        models.downloadASRModel("download")
        models.retryASRBootstrap()
        models.installPolishModel("polish")
        models.installCustomPolishModel()
        models.refreshPolishModels()
        models.deleteASRModel("old-asr")
        models.deletePolishModel("old-polish")
        let modes = model.modesPaneInterface
        modes.onSelectMode?(.voiceToText)
        modes.onAddMode?()
        modes.onEditMode?(modeID)
        modes.onDuplicateMode?(modeID)
        modes.onMoveMode?(modeID, .up)
        modes.onRequestModeDeletion?(modeID)
        modes.selectPane(.models)
        let preferences = model.preferencesPaneInterface
        preferences.onOpenPermissionRecovery?()
        preferences.onOpenShortcutPermissions?()
        preferences.onCommit?(.appearance)
        preferences.onSelectInputDevice?(nil)
        preferences.onCheckUpdates?()
        preferences.onRecord?(.ptt)

        XCTAssertEqual(
            events,
            [
                "permission",
                "history:copyDisplayed",
                "commit:global",
                "commit:global",
                "history:delete",
                "clear-history",
                "cancel-asr",
                "select-asr:asr",
                "download-asr:download",
                "retry-asr",
                "install-polish:polish",
                "install-custom",
                "refresh-polish",
                "delete-asr:old-asr",
                "delete-polish:old-polish",
                "select-mode:voiceToText",
                "add-mode",
                "edit-mode:\(modeID)",
                "duplicate-mode:\(modeID)",
                "move-mode:\(modeID):up",
                "delete-mode:\(modeID)",
                "permission",
                "shortcut-permission",
                "commit:appearance",
                "input:default",
                "updates",
                "record:ptt",
            ]
        )
    }

    func testPaneInterfacesApplyDestinationEdits() {
        let model = SettingsModel()
        let history = model.historyPaneInterface
        let models = model.modelsPaneInterface
        let preferences = model.preferencesPaneInterface

        history.setSaveHistory(false)
        history.setRetention(.forever)
        models.setCustomModel("custom:model")
        model.requestedPolishInspection = "polish:model"
        model.modelsPaneInterface.clearRequestedPolishInspection()
        preferences.pttKey = "f18"
        preferences.toggleKey = "f19"
        preferences.cycleKey = "f20"
        preferences.pauseAudio = false
        preferences.appearance = .dark

        XCTAssertEqual(
            [
                String(model.saveHistory),
                String(model.retention.rawValue),
                model.customModel,
                model.requestedPolishInspection ?? "none",
                model.pttKey,
                model.toggleKey,
                model.cycleKey,
                String(model.pauseAudio),
                model.appearance.rawValue,
            ],
            ["false", "0", "custom:model", "none", "f18", "f19", "f20", "false", "dark"]
        )
    }

    func testSidebarObservationIgnoresUnrelatedModelSelectionChange() {
        let model = SettingsModel()
        let invalidations = ObservationInvalidationCounter()

        withObservationTracking {
            _ = model.pane
            _ = model.configurationRecoveryMessage
            _ = model.sidebar
            _ = model.windowWidth
            _ = model.hoveredRailPane
        } onChange: {
            invalidations.increment()
        }

        model.selectedModel = "qwen2.5:3b"

        XCTAssertEqual(invalidations.value, 0)
    }

    func testASRPresentationDerivesCoherentStateFromOneLifecycleSnapshot() async {
        let lifecycle = ASRModelLifecycle(storedSelection: "whisper-small", adapters: [])
        let snapshot = await lifecycle.snapshot()
        let model = SettingsModel()

        model.applyASRLifecycleSnapshot(ASRModelLifecycleSnapshot(
            models: snapshot.models,
            storedSelection: "whisper-small",
            effectiveSelection: ASRModelCatalog.defaultID,
            recovery: .storedSelectionUnavailable(
                modelID: "whisper-small",
                fallbackModelID: ASRModelCatalog.defaultID
            ),
            operation: .downloading(modelID: "whisper-large-v3-turbo", fraction: 0.4),
            failure: nil,
            isDictationBlocked: false
        ))

        XCTAssertEqual(
            ASRPresentationState(
                selected: model.asrModel,
                downloading: model.asrDownloading,
                fraction: model.asrDownloadFraction,
                recovery: model.asrRecoveryMessage,
                effectiveModelName: model.effectiveASRModelName,
                actionsDisabled: model.hasActiveASRManagementOperation
            ),
            ASRPresentationState(
                selected: "whisper-small",
                downloading: "whisper-large-v3-turbo",
                fraction: 0.4,
                recovery: "Whisper small is unavailable. Using Parakeet TDT v3 until you download it again.",
                effectiveModelName: "Parakeet TDT v3",
                actionsDisabled: true
            )
        )
    }

    func testUnrelatedASROperationKeepsExistingModelFailure() {
        let model = SettingsModel()
        let failure = ASRModelLifecycleFailure.downloadFailed(
            modelID: "whisper-small",
            reason: "disk full"
        )
        model.applyASRLifecycleSnapshot(snapshot(failure: failure))
        model.applyASRLifecycleSnapshot(snapshot(
            operation: .downloading(modelID: "whisper-large-v3-turbo", fraction: 0.2)
        ))

        XCTAssertEqual(model.asrFailures.failure(for: "whisper-small"), failure)
    }

    func testRelevantASROperationClearsExistingModelFailure() {
        let model = SettingsModel()
        model.applyASRLifecycleSnapshot(snapshot(failure: .downloadFailed(
            modelID: "whisper-small",
            reason: "disk full"
        )))
        model.applyASRLifecycleSnapshot(snapshot(
            operation: .downloading(modelID: "whisper-small", fraction: nil)
        ))

        XCTAssertNil(model.asrFailures.failure(for: "whisper-small"))
    }

    func testPaneIDsMatchEachDestination() {
        XCTAssertEqual(
            SettingsModel.Pane.allCases.map(\.id),
            ["Home", "Modes", "Models", "History", "Stats", "Settings"]
        )
    }

    private func snapshot(
        operation: ASRModelLifecycleOperation? = nil,
        failure: ASRModelLifecycleFailure? = nil
    ) -> ASRModelLifecycleSnapshot {
        ASRModelLifecycleSnapshot(
            models: ASRModelCatalog.entries.map { ASRModelDescriptor(entry: $0, isAvailable: true) },
            storedSelection: ASRModelCatalog.defaultID,
            effectiveSelection: ASRModelCatalog.defaultID,
            recovery: nil,
            operation: operation,
            failure: failure,
            isDictationBlocked: false
        )
    }

    func testPaneIconsMatchEachDestination() {
        XCTAssertEqual(
            SettingsModel.Pane.allCases.map(\.icon),
            ["house", "sparkles", "shippingbox", "clock", "chart.bar", "slider.horizontal.3"]
        )
    }

    func testOllamaDownOnlyWhenTheAvailableListIsEmpty() {
        let model = SettingsModel()
        XCTAssertFalse(model.ollamaDown)

        model.installed = []
        XCTAssertTrue(model.ollamaDown)

        model.installed = [installed("qwen2.5:3b")]
        XCTAssertFalse(model.ollamaDown)
    }

    func testPolishModelsStateCapturesOneCoherentLifecycleValue() {
        let model = SettingsModel()
        model.installed = [installed("qwen2.5:3b")]
        model.pullingModel = "gemma3:4b"
        model.pullStatus = "pulling layers"
        model.pullFraction = 0.4
        model.pullFailures = ModelsOperationFailures([
            "old:model": "Couldn't install old:model: failed",
        ])
        model.deleteFailures = ModelsOperationFailures([
            "stale:model": "Couldn't uninstall stale:model: busy",
        ])
        model.customModel = "custom:model"

        XCTAssertEqual(
            model.polishModelsState,
            ModelsPolishState(
                installed: [installed("qwen2.5:3b")],
                pullingModel: "gemma3:4b",
                pullStatus: "pulling layers",
                pullFraction: 0.4,
                pullFailures: ModelsOperationFailures([
                    "old:model": "Couldn't install old:model: failed",
                ]),
                deleteFailures: ModelsOperationFailures([
                    "stale:model": "Couldn't uninstall stale:model: busy",
                ]),
                customModel: "custom:model"
            )
        )
    }

    func testSelectedModelIsAllowedWhileAvailabilityIsUnknownOrOllamaIsDown() {
        let model = SettingsModel()
        model.selectedModel = "qwen2.5:3b"
        XCTAssertTrue(model.selectedModelInstalled)

        model.installed = []
        XCTAssertTrue(model.selectedModelInstalled)
    }

    func testSelectedModelInstalledReflectsTheAvailableModelList() {
        let model = SettingsModel()
        model.selectedModel = "qwen2.5:3b"
        model.installed = [installed("llama3.2:3b"), installed("qwen2.5:3b")]

        XCTAssertTrue(model.selectedModelInstalled)

        model.selectedModel = "missing:latest"
        XCTAssertFalse(model.selectedModelInstalled)
    }

    func testSelectedEditableModePresentationUsesProjectedIconFallback() {
        let model = SettingsModel()
        let id = ModeID.random()
        let mode = Mode(
            id: id,
            name: "Custom",
            icon: "symbol.that.is.not.available",
            asrModel: ASRModelCatalog.defaultID,
            llmModel: "qwen2.5:3b",
            transformation: .inPlace,
            systemPrompt: "Keep wording.",
            vocabulary: []
        )
        model.modes = [mode]
        model.modeSelection = ModePresentationFactory.projection(
            modes: [mode],
            selection: .mode(id)
        )

        XCTAssertEqual(model.selectedEditableMode?.id, id)
        XCTAssertEqual(model.selectedEditableModeItem?.icon, "text.bubble")
    }

    private func installed(_ name: String) -> OllamaClient.InstalledModel {
        OllamaClient.InstalledModel(name: name, sizeBytes: 1)
    }
}

private struct ASRPresentationState: Equatable {
    let selected: String
    let downloading: String?
    let fraction: Double?
    let recovery: String?
    let effectiveModelName: String
    let actionsDisabled: Bool
}

private final class ObservationInvalidationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock {
            count += 1
        }
    }
}
