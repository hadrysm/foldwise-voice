import Foundation

struct HomePaneInterface {
    let readProjectionInput: () -> HomeProjection.Input
    let readCurrentStreak: () -> Int?
    let readPushToTalkKey: () -> String
    let readPermissionSnapshot: () -> PermissionRecoverySnapshot
    let readEffectiveASRModelName: () -> String
    let readSelectedPolishModel: () -> String
    let readWindowWidth: () -> Double
    let performance: PaneNavigationPerformance
    let selectPane: (SettingsModel.Pane) -> Void
    let performHistoryCommand: (HistoryEntry, DictationRowCommand) -> Void
    let openPermissionRecovery: () -> Void

    var projectionInput: HomeProjection.Input {
        readProjectionInput()
    }

    var currentStreak: Int? {
        readCurrentStreak()
    }

    var pushToTalkKey: String {
        readPushToTalkKey()
    }

    var permissionSnapshot: PermissionRecoverySnapshot {
        readPermissionSnapshot()
    }

    var effectiveASRModelName: String {
        readEffectiveASRModelName()
    }

    var selectedPolishModel: String {
        readSelectedPolishModel()
    }

    var windowWidth: Double {
        readWindowWidth()
    }
}

struct HistoryPaneInterface {
    let readEntries: () -> [HistoryEntry]
    let readModes: () -> [Mode]
    let readSaveHistory: () -> Bool
    let readRetention: () -> RetentionWindow
    let performance: PaneNavigationPerformance
    let setSaveHistory: (Bool) -> Void
    let setRetention: (RetentionWindow) -> Void
    let performHistoryCommand: (HistoryEntry, DictationRowCommand) -> Void
    let clearHistory: () -> Void

    var entries: [HistoryEntry] {
        readEntries()
    }

    var modes: [Mode] {
        readModes()
    }

    var saveHistory: Bool {
        readSaveHistory()
    }

    var retention: RetentionWindow {
        readRetention()
    }
}

struct StatsPaneInterface {
    let readInput: () -> StatsProjection.Input
    let performance: PaneNavigationPerformance
    let openHistory: () -> Void

    var input: StatsProjection.Input {
        readInput()
    }
}

struct ModelsPaneInterface {
    let readASRSnapshot: () -> ASRModelLifecycleSnapshot?
    let readASRFailures: () -> ModelsASRFailures
    let readPolishState: () -> ModelsPolishState
    let readModes: () -> [Mode]
    let readRequestedPolishInspection: () -> String?
    let readCustomModel: () -> String
    let readWindowWidth: () -> Double
    let setCustomModel: (String) -> Void
    let clearRequestedPolishInspection: () -> Void
    let cancelASROperation: () -> Void
    let selectASRModel: (String) -> Void
    let downloadASRModel: (String) -> Void
    let retryASRBootstrap: () -> Void
    let installPolishModel: (String) -> Void
    let installCustomPolishModel: () -> Void
    let refreshPolishModels: () -> Void
    let deleteASRModel: (String) -> Void
    let deletePolishModel: (String) -> Void

    var asrSnapshot: ASRModelLifecycleSnapshot? {
        readASRSnapshot()
    }

    var asrFailures: ModelsASRFailures {
        readASRFailures()
    }

    var polishState: ModelsPolishState {
        readPolishState()
    }

    var modes: [Mode] {
        readModes()
    }

    var requestedPolishInspection: String? {
        readRequestedPolishInspection()
    }

    var customModel: String {
        readCustomModel()
    }

    var windowWidth: Double {
        readWindowWidth()
    }
}

@MainActor
final class ModesPaneInterface {
    private let model: SettingsModel

    init(model: SettingsModel) {
        self.model = model
    }

    var modeSelection: ModeSelectionProjection {
        model.modeSelection
    }

    var modes: [Mode] {
        model.modes
    }

    var selectedEditableMode: Mode? {
        model.selectedEditableMode
    }

    var selectedEditableModeItem: ModeSelectionItem? {
        model.selectedEditableModeItem
    }

    var installed: [OllamaClient.InstalledModel]? {
        model.installed
    }

    var onSelectMode: ((DictationSelection) -> Void)? {
        model.onSelectMode
    }

    var onAddMode: (() -> Void)? {
        model.onAddMode
    }

    var onEditMode: ((ModeID) -> Void)? {
        model.onEditMode
    }

    var onDuplicateMode: ((ModeID) -> Void)? {
        model.onDuplicateMode
    }

    var onMoveMode: ((ModeID, ModeMoveDirection) -> Void)? {
        model.onMoveMode
    }

    var onRequestModeDeletion: ((ModeID) -> Void)? {
        model.onRequestModeDeletion
    }

    func selectPane(_ pane: SettingsModel.Pane) {
        model.selectPane(pane)
    }
}

@MainActor
final class PreferencesPaneInterface {
    private let model: SettingsModel

    init(model: SettingsModel) {
        self.model = model
    }

    var permissionRecovery: PermissionRecoveryWorkflow.State {
        model.permissionRecovery
    }

    var pttKey: String {
        get { model.pttKey }
        set { model.pttKey = newValue }
    }

    var toggleKey: String {
        get { model.toggleKey }
        set { model.toggleKey = newValue }
    }

    var cycleKey: String {
        get { model.cycleKey }
        set { model.cycleKey = newValue }
    }

    var pauseAudio: Bool {
        get { model.pauseAudio }
        set { model.pauseAudio = newValue }
    }

    var appearance: AppearancePreference {
        get { model.appearance }
        set { model.appearance = newValue }
    }

    var inputState: AudioInputState {
        model.inputState
    }

    var windowWidth: Double {
        model.windowWidth
    }

    var shortcutListenerHealth: ShortcutListenerHealth {
        model.shortcutListenerHealth
    }

    var canCheckForUpdates: Bool {
        model.canCheckForUpdates
    }

    var recordingField: SettingsModel.RecordingField? {
        model.recordingField
    }

    var status: String {
        model.status
    }

    var statusIsError: Bool {
        model.statusIsError
    }

    var statusOwner: SettingsFeedbackOwner {
        model.statusOwner
    }

    var onOpenPermissionRecovery: (() -> Void)? {
        model.onOpenPermissionRecovery
    }

    var onOpenShortcutPermissions: (() -> Void)? {
        model.onOpenShortcutPermissions
    }

    var onCommit: ((SettingsFeedbackOwner) -> Void)? {
        model.onCommit
    }

    var onSelectInputDevice: ((String?) -> Void)? {
        model.onSelectInputDevice
    }

    var onCheckUpdates: (() -> Void)? {
        model.onCheckUpdates
    }

    var onRecord: ((SettingsModel.RecordingField) -> Void)? {
        model.onRecord
    }
}

@MainActor
extension SettingsModel {
    var modesPaneInterface: ModesPaneInterface {
        ModesPaneInterface(model: self)
    }

    var preferencesPaneInterface: PreferencesPaneInterface {
        PreferencesPaneInterface(model: self)
    }

    var homePaneInterface: HomePaneInterface {
        HomePaneInterface(
            readProjectionInput: {
                HomeProjection.Input(entries: self.historyEntries, modes: self.modes)
            },
            readCurrentStreak: { self.currentStreak },
            readPushToTalkKey: { self.pttKey },
            readPermissionSnapshot: { self.permissionRecovery.snapshot },
            readEffectiveASRModelName: { self.effectiveASRModelName },
            readSelectedPolishModel: { self.selectedModel },
            readWindowWidth: { self.windowWidth },
            performance: panePerformance,
            selectPane: { [weak self] in self?.selectPane($0) },
            performHistoryCommand: { [weak self] in self?.onHistoryCommand?($0, $1) },
            openPermissionRecovery: { [weak self] in self?.onOpenPermissionRecovery?() }
        )
    }

    var historyPaneInterface: HistoryPaneInterface {
        HistoryPaneInterface(
            readEntries: { self.historyEntries },
            readModes: { self.modes },
            readSaveHistory: { self.saveHistory },
            readRetention: { self.retention },
            performance: panePerformance,
            setSaveHistory: { [weak self] isEnabled in
                guard let self else { return }
                saveHistory = isEnabled
                onCommit?(.global)
            },
            setRetention: { [weak self] retention in
                guard let self else { return }
                self.retention = retention
                onCommit?(.global)
            },
            performHistoryCommand: { [weak self] in self?.onHistoryCommand?($0, $1) },
            clearHistory: { [weak self] in self?.onClearHistory?() }
        )
    }

    var statsPaneInterface: StatsPaneInterface {
        StatsPaneInterface(
            readInput: {
                StatsProjection.Input(
                    entries: self.historyEntries,
                    currentStreak: self.currentStreak,
                    savingEnabled: self.saveHistory
                )
            },
            performance: panePerformance,
            openHistory: { [weak self] in self?.selectPane(.history) }
        )
    }

    var modelsPaneInterface: ModelsPaneInterface {
        ModelsPaneInterface(
            readASRSnapshot: { self.asrSnapshot },
            readASRFailures: { self.asrFailures },
            readPolishState: { self.polishModelsState },
            readModes: { self.modes },
            readRequestedPolishInspection: { self.requestedPolishInspection },
            readCustomModel: { self.customModel },
            readWindowWidth: { self.windowWidth },
            setCustomModel: { [weak self] in self?.customModel = $0 },
            clearRequestedPolishInspection: { [weak self] in
                self?.requestedPolishInspection = nil
            },
            cancelASROperation: { [weak self] in self?.onCancelASROperation?() },
            selectASRModel: { [weak self] in self?.onSelectASRModel?($0) },
            downloadASRModel: { [weak self] in self?.onDownloadASRModel?($0) },
            retryASRBootstrap: { [weak self] in self?.onRetryASRBootstrap?() },
            installPolishModel: { [weak self] in self?.onInstallModel?($0) },
            installCustomPolishModel: { [weak self] in self?.onInstallCustomModel?() },
            refreshPolishModels: { [weak self] in self?.onRefreshModels?() },
            deleteASRModel: { [weak self] in self?.onDeleteASRModel?($0) },
            deletePolishModel: { [weak self] in self?.onDeleteModel?($0) }
        )
    }
}
