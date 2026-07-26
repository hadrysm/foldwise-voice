// Observable state for the settings window. SettingsController owns the
// instance and wires the callbacks; SettingsView renders it.

import Observation
import SwiftUI

enum SettingsFeedbackOwner: Equatable {
    case global
    case shortcuts
    case input
    case sound
    case appearance
}

enum SettingsAppearanceLayout: Equatable {
    case horizontal
    case vertical

    static func forContentWidth(_ width: Double) -> SettingsAppearanceLayout {
        width >= 650 ? .horizontal : .vertical
    }
}

@MainActor
@Observable
final class SettingsModel {
    let panePerformance: PaneNavigationPerformance
    let paneProjections: PaneProjectionStore

    init() {
        panePerformance = PaneNavigationPerformance()
        paneProjections = PaneProjectionStore()
    }

    init(panePerformance: PaneNavigationPerformance) {
        self.panePerformance = panePerformance
        paneProjections = PaneProjectionStore()
    }

    init(
        panePerformance: PaneNavigationPerformance,
        paneProjections: PaneProjectionStore
    ) {
        self.panePerformance = panePerformance
        self.paneProjections = paneProjections
    }

    /// The six destinations of the redesigned sidebar (PRD #103). The old
    /// Speech pane lives inside Models; Configuration and Sound merged into
    /// Settings.
    enum Pane: String, CaseIterable, Codable, Identifiable {
        case home = "Home"
        case modes = "Modes"
        case models = "Models"
        case history = "History"
        case stats = "Stats"
        case settings = "Settings"
        var id: String {
            rawValue
        }

        var icon: String {
            switch self {
            case .home: "house"
            case .modes: "sparkles"
            case .models: "shippingbox"
            case .history: "clock"
            case .stats: "chart.bar"
            case .settings: "slider.horizontal.3"
            }
        }

        var isAvailableInConfigurationRecovery: Bool {
            switch self {
            case .home, .stats: true
            case .modes, .models, .history, .settings: false
            }
        }
    }

    enum RecordingField {
        case ptt
        case toggle
        case cycle

        var command: ShortcutCommand {
            switch self {
            case .ptt: .pushToTalk
            case .toggle: .toggleRecording
            case .cycle: .modeCycle
            }
        }
    }

    var pane: Pane = .home
    var canCheckForUpdates = false
    var selectedModel = ""
    /// The lifecycle is the single source of ASR truth. Presentation properties
    /// below derive from one immutable value so Settings cannot expose mixed
    /// selected/available/operating states while snapshots change.
    private(set) var asrSnapshot: ASRModelLifecycleSnapshot?
    private(set) var asrFailures = ModelsASRFailures()
    var installed: [OllamaClient.InstalledModel]? // nil = checking, [] = Ollama down
    var pullingModel: String?
    var pullStatus = ""
    var pullFraction: Double?
    var pullFailures = ModelsOperationFailures()
    var deletingModel: String?
    var deleteFailures = ModelsOperationFailures()
    var customModel = ""
    var requestedPolishInspection: String?
    var pttKey = ""
    var toggleKey = ""
    var cycleKey = ""
    var pauseAudio = true
    var appearance: AppearancePreference = .system
    var inputState = AudioInputState(
        devices: [], systemDefault: nil, preferredUID: nil, preferredName: nil,
        effectiveDevice: nil, pendingDevice: nil,
        status: .unavailable(message: "No input device is available.")
    )
    /// Master "Save dictation history" switch, surfaced in the History pane.
    var saveHistory = true {
        didSet {
            applyProjectionInvalidation(
                paneProjections.setSavingEnabled(saveHistory)
            )
        }
    }

    /// Auto-delete window for history, a control distinct from `saveHistory`.
    var retention = RetentionWindow.default
    /// Sidebar rendering rule: seeded from Config's persisted preference when
    /// the window opens; explicit toggles mutate it and commit the preference.
    var sidebar = SidebarPresentation(prefersCollapsed: false)
    /// Live window width, feeding the sidebar's auto-collapse rule.
    var windowWidth: Double = 980
    /// The rail tile currently under the pointer, driving its tooltip chip.
    var hoveredRailPane: Pane?
    var status = ""
    var statusIsError = false
    var statusOwner = SettingsFeedbackOwner.global
    var recordingField: RecordingField?
    var shortcutListenerHealth: ShortcutListenerHealth = .global
    var configurationRecoveryMessage: String?
    var permissionRecovery = PermissionRecoveryWorkflow.State()

    func selectPane(_ destination: Pane) {
        guard destination != pane else { return }
        panePerformance.beginNavigation(to: destination)
        pane = destination
    }

    private func applyProjectionInvalidation(
        _ invalidation: PaneProjectionStore.Invalidation
    ) {
        if invalidation.contains(.home) {
            homeProjectionRevision.advance()
        }
        if invalidation.contains(.history) {
            historyProjectionRevision.advance()
        }
        if invalidation.contains(.stats) {
            statsProjectionRevision.advance()
        }
    }

    func isPaneAvailable(_ pane: Pane) -> Bool {
        configurationRecoveryMessage == nil || pane.isAvailableInConfigurationRecovery
    }

    func applyASRLifecycleSnapshot(_ snapshot: ASRModelLifecycleSnapshot) {
        asrFailures.apply(snapshot)
        asrSnapshot = snapshot
    }

    var asrModel: String {
        asrSnapshot?.storedSelection ?? ""
    }

    var asrCatalog: [ASRModelDescriptor] {
        asrSnapshot?.models ?? []
    }

    var effectiveASRModelName: String {
        guard let effectiveSelection = asrSnapshot?.effectiveSelection else {
            return "Speech unavailable"
        }
        return asrCatalog.first { $0.id == effectiveSelection }?.name
            ?? "Speech unavailable"
    }

    var asrDownloaded: Set<String> {
        Set(asrCatalog.filter(\.isAvailable).map(\.id))
    }

    var asrDownloading: String? {
        switch asrSnapshot?.operation {
        case let .downloading(modelID, _):
            modelID
        case .bootstrapping:
            asrCatalog.first(where: \.isDefault)?.id
        case .switching, .restoring, .deleting, nil:
            nil
        }
    }

    var asrDownloadFraction: Double? {
        switch asrSnapshot?.operation {
        case let .downloading(_, fraction), let .bootstrapping(fraction):
            fraction
        case .switching, .restoring, .deleting, nil:
            nil
        }
    }

    var isASRBootstrapping: Bool {
        if case .bootstrapping = asrSnapshot?.operation {
            return true
        }
        return false
    }

    var asrSwitching: String? {
        if case let .switching(modelID) = asrSnapshot?.operation {
            return modelID
        }
        return nil
    }

    var asrRestoring: String? {
        if case let .restoring(modelID) = asrSnapshot?.operation {
            return modelID
        }
        return nil
    }

    var asrDeleting: String? {
        if case let .deleting(modelID) = asrSnapshot?.operation {
            return modelID
        }
        return nil
    }

    var asrRecoveryMessage: String? {
        switch asrSnapshot?.recovery {
        case let .storedSelectionUnavailable(modelID, fallbackModelID):
            "\(asrModelName(modelID)) is unavailable. Using "
                + "\(asrModelName(fallbackModelID)) until you download it again."
        case let .storedSelectionUnknown(modelID, fallbackModelID):
            "Stored speech model “\(modelID)” isn't recognized. Using \(asrModelName(fallbackModelID))."
        case nil:
            nil
        }
    }

    var asrDownloadError: String {
        switch asrSnapshot?.failure {
        case let .downloadFailed(modelID, reason):
            "Couldn't download \(asrModelName(modelID)): \(reason)"
        case let .downloadedDataInvalid(modelID):
            "Downloaded data for \(asrModelName(modelID)) is incomplete or corrupt."
        case let .bootstrapFailed(reason):
            "Couldn't prepare the default speech model: \(reason)"
        case let .engineLoadFailed(modelID, reason):
            "Couldn't load \(asrModelName(modelID)): \(reason)"
        case let .selectionFailed(modelID, reason):
            "Couldn't switch to \(asrModelName(modelID)): \(reason)"
        case .selectionCanceled:
            ""
        case let .selectionDegraded(modelID, fallbackModelID, reason):
            "Couldn't restore \(asrModelName(modelID)). Using "
                + "\(asrModelName(fallbackModelID))\(reason.map { ": \($0)" } ?? ".")"
        case .deletionFailed, .deletionSelectionFailed, nil:
            ""
        }
    }

    var asrDeleteError: String {
        switch asrSnapshot?.failure {
        case let .deletionFailed(modelID, reason),
             let .deletionSelectionFailed(modelID, reason):
            "Couldn't delete \(asrModelName(modelID)): \(reason)"
        case .downloadFailed, .downloadedDataInvalid, .bootstrapFailed, .engineLoadFailed,
             .selectionFailed, .selectionCanceled, .selectionDegraded, nil:
            ""
        }
    }

    var canRetryASRBootstrap: Bool {
        asrSnapshot?.isDictationBlocked == true
            && asrSnapshot?.operation == nil
            && asrSnapshot?.failure?.allowsBootstrapRetry == true
    }

    var hasActiveASRManagementOperation: Bool {
        asrSnapshot?.operation != nil
    }

    private func asrModelName(_ id: String) -> String {
        asrCatalog.first { $0.id == id }?.name ?? id
    }

    var modeSelection = ModePresentationFactory.projection(
        modes: [], selection: .voiceToText
    )
    var modes: [Mode] = [] {
        didSet {
            applyProjectionInvalidation(paneProjections.setModes(modes))
        }
    }

    var modeEditor: ModeEditorState?
    var modePendingDeletion: ModeDeletionState?
    /// Loaded from the HistoryStore when the window opens and re-read after a
    /// delete or clear-all, so the History pane reflects the store live.
    var historyEntries: [HistoryEntry] {
        get {
            paneProjections.historyEntries
        }
        set {
            applyProjectionInvalidation(
                paneProjections.setHistoryEntries(newValue)
            )
        }
    }

    @discardableResult
    func applyHistoryMutation(
        _ mutation: PaneProjectionStore.HistoryMutation
    ) -> Bool {
        let invalidation = paneProjections.applyHistoryMutation(mutation)
        applyProjectionInvalidation(invalidation)
        return !invalidation.isEmpty
    }

    /// The lifetime streak to show, computed by the controller from the StatsStore
    /// through `StreakRules.display`: the run's length while it is alive (last
    /// active today or yesterday), `nil` — rendered "No active streak" — when it
    /// has lapsed or never started. Refreshed on window open and as new dictations
    /// append.
    var currentStreak: Int? {
        didSet {
            applyProjectionInvalidation(
                paneProjections.setCurrentStreak(currentStreak)
            )
        }
    }

    private(set) var homeProjectionRevision = PaneProjectionStore.Revision()
    private(set) var historyProjectionRevision = PaneProjectionStore.Revision()
    private(set) var statsProjectionRevision = PaneProjectionStore.Revision()

    // wired by SettingsController
    @ObservationIgnored var onCommit: ((SettingsFeedbackOwner) -> Void)?
    @ObservationIgnored var onSelectInputDevice: ((String?) -> Void)?
    @ObservationIgnored var onRecord: ((RecordingField) -> Void)?
    @ObservationIgnored var onOpenShortcutPermissions: (() -> Void)?
    @ObservationIgnored var onOpenPermissionRecovery: (() -> Void)?
    @ObservationIgnored var onDismissPermissionRecovery: (() -> Void)?
    @ObservationIgnored var onRevealShortcutFallback: (() -> Void)?
    @ObservationIgnored var onRequestPermission: ((PermissionKind) -> Void)?
    @ObservationIgnored var onOpenPermissionSettings: ((PermissionKind) -> Void)?
    @ObservationIgnored var onSelectMode: ((DictationSelection) -> Void)?
    @ObservationIgnored var onAddMode: (() -> Void)?
    @ObservationIgnored var onEditMode: ((ModeID) -> Void)?
    @ObservationIgnored var onDuplicateMode: ((ModeID) -> Void)?
    @ObservationIgnored var onMoveMode: ((ModeID, ModeMoveDirection) -> Void)?
    @ObservationIgnored var onRequestModeDeletion: ((ModeID) -> Void)?
    @ObservationIgnored var onConfirmModeDeletion: (() -> Void)?
    @ObservationIgnored var onCancelModeDeletion: (() -> Void)?
    @ObservationIgnored var onSaveModeEditor: (() -> Void)?
    @ObservationIgnored var onCancelModeEditor: (() -> Void)?
    @ObservationIgnored var onInstallModel: ((String) -> Void)?
    @ObservationIgnored var onInstallCustomModel: (() -> Void)?
    @ObservationIgnored var onDeleteModel: ((String) -> Void)?
    @ObservationIgnored var onRefreshModels: (() -> Void)?
    /// Speech pane actions select an already-downloaded model as active or
    /// download an available model's weights.
    @ObservationIgnored var onSelectASRModel: ((String) -> Void)?
    @ObservationIgnored var onDownloadASRModel: ((String) -> Void)?
    /// Abort an in-flight download/prepare and return the row to its pre-download
    /// state, so a slow or stalled fetch (or the post-100% compile) can be escaped.
    @ObservationIgnored var onCancelASROperation: (() -> Void)?
    @ObservationIgnored var onRetryASRBootstrap: (() -> Void)?
    /// Delete a downloaded model's on-disk weights to reclaim space (#95). If it
    /// was selected, the lifecycle commits Parakeet before removing its data.
    @ObservationIgnored var onDeleteASRModel: ((String) -> Void)?
    @ObservationIgnored var onCheckUpdates: (() -> Void)?
    /// One semantic row-action seam. Clear All remains collection-level.
    @ObservationIgnored var onHistoryCommand: ((HistoryEntry, DictationRowCommand) -> Void)?
    @ObservationIgnored var onClearHistory: (() -> Void)?
    @ObservationIgnored var onResetConfiguration: (() -> Void)?
    @ObservationIgnored var onQuitRecovery: (() -> Void)?

    var configurationReadOnly: Bool {
        configurationRecoveryMessage != nil
    }

    var ollamaDown: Bool {
        installed?.isEmpty ?? false
    }

    var polishModelsState: ModelsPolishState {
        ModelsPolishState(
            installed: installed,
            pullingModel: pullingModel,
            pullStatus: pullStatus,
            pullFraction: pullFraction,
            deletingModel: deletingModel,
            pullFailures: pullFailures,
            deleteFailures: deleteFailures,
            customModel: customModel
        )
    }

    /// False only when we can see Ollama's model list and ours isn't in it.
    var selectedModelInstalled: Bool {
        guard let installed, !installed.isEmpty else { return true }
        return installed.contains { $0.name == selectedModel }
    }

    var selectedEditableMode: Mode? {
        guard case let .mode(id) = selectedEditableModeItem?.id else {
            return nil
        }
        return modes.first { $0.id == id }
    }

    var selectedEditableModeItem: ModeSelectionItem? {
        guard let item = modeSelection.items.first(where: \.isSelected), !item.isProtected else {
            return nil
        }
        return item
    }
}
