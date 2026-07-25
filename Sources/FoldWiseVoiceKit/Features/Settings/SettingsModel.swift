// Observable state for the settings window. SettingsController owns the
// instance and wires the callbacks; SettingsView renders it.

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
final class SettingsModel: ObservableObject {
    /// The six destinations of the redesigned sidebar (PRD #103). The old
    /// Speech pane lives inside Models; Configuration and Sound merged into
    /// Settings.
    enum Pane: String, CaseIterable, Identifiable {
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

    @Published var pane: Pane = .home
    @Published var canCheckForUpdates = false
    @Published var selectedModel = ""
    /// The lifecycle is the single source of ASR truth. Presentation properties
    /// below derive from one immutable value so Settings cannot expose mixed
    /// selected/available/operating states while snapshots change.
    @Published private(set) var asrSnapshot: ASRModelLifecycleSnapshot?
    private(set) var asrFailures = ModelsASRFailures()
    @Published var installed: [OllamaClient.InstalledModel]? // nil = checking, [] = Ollama down
    @Published var pullingModel: String?
    @Published var pullStatus = ""
    @Published var pullFraction: Double?
    @Published var pullFailures = ModelsOperationFailures()
    @Published var deletingModel: String?
    @Published var deleteFailures = ModelsOperationFailures()
    @Published var customModel = ""
    @Published var requestedPolishInspection: String?
    @Published var pttKey = ""
    @Published var toggleKey = ""
    @Published var cycleKey = ""
    @Published var pauseAudio = true
    @Published var appearance: AppearancePreference = .system
    @Published var inputState = AudioInputState(
        devices: [], systemDefault: nil, preferredUID: nil, preferredName: nil,
        effectiveDevice: nil, pendingDevice: nil,
        status: .unavailable(message: "No input device is available.")
    )
    /// Master "Save dictation history" switch, surfaced in the History pane.
    @Published var saveHistory = true
    /// Auto-delete window for history, a control distinct from `saveHistory`.
    @Published var retention = RetentionWindow.default
    /// Sidebar rendering rule: seeded from Config's persisted preference when
    /// the window opens; explicit toggles mutate it and commit the preference.
    @Published var sidebar = SidebarPresentation(prefersCollapsed: false)
    /// Live window width, feeding the sidebar's auto-collapse rule.
    @Published var windowWidth: Double = 980
    /// The rail tile currently under the pointer, driving its tooltip chip.
    @Published var hoveredRailPane: Pane?
    @Published var status = ""
    @Published var statusIsError = false
    @Published var statusOwner = SettingsFeedbackOwner.global
    @Published var recordingField: RecordingField?
    @Published var shortcutListenerHealth: ShortcutListenerHealth = .global
    @Published var configurationRecoveryMessage: String?
    @Published var permissionRecovery = PermissionRecoveryWorkflow.State()

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

    @Published var modeSelection = ModePresentationFactory.projection(
        modes: [], selection: .voiceToText
    )
    @Published var modes: [Mode] = []
    @Published var modeEditor: ModeEditorState?
    @Published var modePendingDeletion: ModeDeletionState?
    /// Loaded from the HistoryStore when the window opens and re-read after a
    /// delete or clear-all, so the History pane reflects the store live.
    @Published var historyEntries: [HistoryEntry] = []
    /// The lifetime streak to show, computed by the controller from the StatsStore
    /// through `StreakRules.display`: the run's length while it is alive (last
    /// active today or yesterday), `nil` — rendered "No active streak" — when it
    /// has lapsed or never started. Refreshed on window open and as new dictations
    /// append.
    @Published var currentStreak: Int?

    // wired by SettingsController
    var onCommit: ((SettingsFeedbackOwner) -> Void)?
    var onSelectInputDevice: ((String?) -> Void)?
    var onRecord: ((RecordingField) -> Void)?
    var onOpenShortcutPermissions: (() -> Void)?
    var onOpenPermissionRecovery: (() -> Void)?
    var onDismissPermissionRecovery: (() -> Void)?
    var onRevealShortcutFallback: (() -> Void)?
    var onRequestPermission: ((PermissionKind) -> Void)?
    var onOpenPermissionSettings: ((PermissionKind) -> Void)?
    var onSelectMode: ((DictationSelection) -> Void)?
    var onAddMode: (() -> Void)?
    var onEditMode: ((ModeID) -> Void)?
    var onDuplicateMode: ((ModeID) -> Void)?
    var onMoveMode: ((ModeID, ModeMoveDirection) -> Void)?
    var onRequestModeDeletion: ((ModeID) -> Void)?
    var onConfirmModeDeletion: (() -> Void)?
    var onCancelModeDeletion: (() -> Void)?
    var onSaveModeEditor: (() -> Void)?
    var onCancelModeEditor: (() -> Void)?
    var onInstallModel: ((String) -> Void)?
    var onInstallCustomModel: (() -> Void)?
    var onDeleteModel: ((String) -> Void)?
    var onRefreshModels: (() -> Void)?
    /// Speech pane actions select an already-downloaded model as active or
    /// download an available model's weights.
    var onSelectASRModel: ((String) -> Void)?
    var onDownloadASRModel: ((String) -> Void)?
    /// Abort an in-flight download/prepare and return the row to its pre-download
    /// state, so a slow or stalled fetch (or the post-100% compile) can be escaped.
    var onCancelASROperation: (() -> Void)?
    var onRetryASRBootstrap: (() -> Void)?
    /// Delete a downloaded model's on-disk weights to reclaim space (#95). If it
    /// was selected, the lifecycle commits Parakeet before removing its data.
    var onDeleteASRModel: ((String) -> Void)?
    var onCheckUpdates: (() -> Void)?
    /// One semantic row-action seam. Clear All remains collection-level.
    var onHistoryCommand: ((HistoryEntry, DictationRowCommand) -> Void)?
    var onClearHistory: (() -> Void)?
    var onResetConfiguration: (() -> Void)?
    var onQuitRecovery: (() -> Void)?

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
