import Foundation

@MainActor
struct HomePaneInterface {
    private let model: SettingsModel

    init(model: SettingsModel) {
        self.model = model
    }

    var projectionRevision: PaneProjectionStore.Revision {
        model.homeProjectionRevision
    }

    var pushToTalkKey: String {
        model.pttKey
    }

    var permissionSnapshot: PermissionRecoverySnapshot {
        model.permissionRecovery.snapshot
    }

    var effectiveASRModelName: String {
        model.effectiveASRModelName
    }

    var selectedPolishModel: String {
        model.selectedModel
    }

    var windowWidth: Double {
        model.windowWidth
    }

    var performance: PaneNavigationPerformance {
        model.panePerformance
    }

    var projection: PaneProjectionStore.Projection<PaneProjectionStore.HomeValue> {
        model.paneProjections.homeProjection
    }

    func prepareProjection(
        in environment: PaneProjectionStore.Environment
    ) {
        model.paneProjections.prepareHome(in: environment)
    }

    func selectPane(_ pane: SettingsModel.Pane) {
        model.selectPane(pane)
    }

    func performHistoryCommand(_ entry: HistoryEntry, _ command: DictationRowCommand) {
        model.onHistoryCommand?(entry, command)
    }

    func openPermissionRecovery() {
        model.onOpenPermissionRecovery?()
    }
}

@MainActor
struct HistoryPaneInterface {
    private let model: SettingsModel

    init(model: SettingsModel) {
        self.model = model
    }

    var hasEntries: Bool {
        !model.historyEntries.isEmpty
    }

    var polishModes: [DictationRowPolishMode] {
        model.modes.compactMap { mode in
            guard mode.usesLLM, let id = mode.id else { return nil }
            return DictationRowPolishMode(id: id, name: mode.name)
        }
    }

    var projectionRevision: PaneProjectionStore.Revision {
        model.historyProjectionRevision
    }

    var saveHistory: Bool {
        model.saveHistory
    }

    var retention: RetentionWindow {
        model.retention
    }

    var performance: PaneNavigationPerformance {
        model.panePerformance
    }

    var projection: PaneProjectionStore.Projection<HistoryProjection> {
        model.paneProjections.historyProjection
    }

    func prepareProjection(
        search: String,
        flaggedOnly: Bool,
        in environment: PaneProjectionStore.Environment
    ) {
        model.paneProjections.prepareHistory(
            search: search,
            flaggedOnly: flaggedOnly,
            in: environment
        )
    }

    func setSaveHistory(_ isEnabled: Bool) {
        model.saveHistory = isEnabled
        model.onCommit?(.global)
    }

    func setRetention(_ retention: RetentionWindow) {
        model.retention = retention
        model.onCommit?(.global)
    }

    func performHistoryCommand(_ entry: HistoryEntry, _ command: DictationRowCommand) {
        model.onHistoryCommand?(entry, command)
    }

    func clearHistory() {
        model.onClearHistory?()
    }
}

@MainActor
struct StatsPaneInterface {
    private let model: SettingsModel

    init(model: SettingsModel) {
        self.model = model
    }

    var projectionRevision: PaneProjectionStore.Revision {
        model.statsProjectionRevision
    }

    var performance: PaneNavigationPerformance {
        model.panePerformance
    }

    var projection: PaneProjectionStore.Projection<StatsProjection> {
        model.paneProjections.statsProjection
    }

    func prepareProjection(
        in environment: PaneProjectionStore.Environment
    ) {
        model.paneProjections.prepareStats(in: environment)
    }

    func openHistory() {
        model.selectPane(.history)
    }
}

@MainActor
struct ModelsPaneInterface {
    private let model: SettingsModel

    init(model: SettingsModel) {
        self.model = model
    }

    var asrSnapshot: ASRModelLifecycleSnapshot? {
        model.asrSnapshot
    }

    var asrFailures: ModelsASRFailures {
        model.asrFailures
    }

    var polishState: ModelsPolishState {
        model.polishModelsState
    }

    var modes: [Mode] {
        model.modes
    }

    var requestedPolishInspection: String? {
        model.requestedPolishInspection
    }

    var customModel: String {
        model.customModel
    }

    var windowWidth: Double {
        model.windowWidth
    }

    func setCustomModel(_ name: String) {
        model.customModel = name
    }

    func clearRequestedPolishInspection() {
        model.requestedPolishInspection = nil
    }

    func cancelASROperation() {
        model.onCancelASROperation?()
    }

    func selectASRModel(_ id: String) {
        model.onSelectASRModel?(id)
    }

    func downloadASRModel(_ id: String) {
        model.onDownloadASRModel?(id)
    }

    func retryASRBootstrap() {
        model.onRetryASRBootstrap?()
    }

    func installPolishModel(_ name: String) {
        model.onInstallModel?(name)
    }

    func installCustomPolishModel() {
        model.onInstallCustomModel?()
    }

    func refreshPolishModels() {
        model.onRefreshModels?()
    }

    func deleteASRModel(_ id: String) {
        model.onDeleteASRModel?(id)
    }

    func deletePolishModel(_ name: String) {
        model.onDeleteModel?(name)
    }
}

@MainActor
struct ModesPaneInterface {
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

    func selectMode(_ selection: DictationSelection) {
        model.onSelectMode?(selection)
    }

    func addMode() {
        model.onAddMode?()
    }

    func editMode(_ id: ModeID) {
        model.onEditMode?(id)
    }

    func duplicateMode(_ id: ModeID) {
        model.onDuplicateMode?(id)
    }

    func moveMode(_ id: ModeID, _ direction: ModeMoveDirection) {
        model.onMoveMode?(id, direction)
    }

    func requestModeDeletion(_ id: ModeID) {
        model.onRequestModeDeletion?(id)
    }

    func selectPane(_ pane: SettingsModel.Pane) {
        model.selectPane(pane)
    }
}

@MainActor
struct PreferencesPaneInterface {
    private let model: SettingsModel

    init(model: SettingsModel) {
        self.model = model
    }

    var permissionRecovery: PermissionRecoveryWorkflow.State {
        model.permissionRecovery
    }

    var pttKey: String {
        get { model.pttKey }
        nonmutating set { model.pttKey = newValue }
    }

    var toggleKey: String {
        get { model.toggleKey }
        nonmutating set { model.toggleKey = newValue }
    }

    var cycleKey: String {
        get { model.cycleKey }
        nonmutating set { model.cycleKey = newValue }
    }

    var pauseAudio: Bool {
        get { model.pauseAudio }
        nonmutating set { model.pauseAudio = newValue }
    }

    var appearance: AppearancePreference {
        get { model.appearance }
        nonmutating set { model.appearance = newValue }
    }

    var inputState: AudioInputState {
        model.inputState
    }

    var windowWidth: Double {
        model.windowWidth
    }

    var sidebarMode: SidebarMode {
        model.sidebar.mode(forWidth: model.windowWidth)
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

    func openPermissionRecovery() {
        model.onOpenPermissionRecovery?()
    }

    func openShortcutPermissions() {
        model.onOpenShortcutPermissions?()
    }

    func commit(_ owner: SettingsFeedbackOwner) {
        model.onCommit?(owner)
    }

    func selectInputDevice(_ uid: String?) {
        model.onSelectInputDevice?(uid)
    }

    func checkForUpdates() {
        model.onCheckUpdates?()
    }

    func record(_ field: SettingsModel.RecordingField) {
        model.onRecord?(field)
    }
}

@MainActor
extension SettingsModel {
    var homePaneInterface: HomePaneInterface {
        HomePaneInterface(model: self)
    }

    var modesPaneInterface: ModesPaneInterface {
        ModesPaneInterface(model: self)
    }

    var modelsPaneInterface: ModelsPaneInterface {
        ModelsPaneInterface(model: self)
    }

    var historyPaneInterface: HistoryPaneInterface {
        HistoryPaneInterface(model: self)
    }

    var statsPaneInterface: StatsPaneInterface {
        StatsPaneInterface(model: self)
    }

    var preferencesPaneInterface: PreferencesPaneInterface {
        PreferencesPaneInterface(model: self)
    }
}
