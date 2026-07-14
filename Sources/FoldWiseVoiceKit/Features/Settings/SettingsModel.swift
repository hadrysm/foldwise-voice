// Observable state for the settings window. SettingsController owns the
// instance and wires the callbacks; SettingsView renders it.

import SwiftUI

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
    }

    enum RecordingField { case ptt, toggle }

    enum UpdateState {
        case idle
        case checking
        case upToDate
        case available(version: String, downloadURL: URL?)
        case failed
        /// Dev builds (`swift run`) have no bundle version to compare.
        case unavailable
    }

    @Published var pane: Pane = .home
    @Published var updateState: UpdateState = .idle
    @Published var activeMode = ""
    @Published var selectedModel = ""
    /// The active ASR model's catalog id (ADR-0006). Speech-pane state below.
    @Published var asrModel = ASRModelCatalog.defaultID
    /// Catalog ids whose weights are present and thus selectable. Parakeet (the
    /// on-device default) is always in here; Whisper joins after a download.
    @Published var asrDownloaded: Set<String> = [ASRModelCatalog.defaultID]
    @Published var asrDownloading: String?
    /// 0…1 while the downloading model reports progress; nil before the first
    /// fraction arrives or for an engine that can't report one (Parakeet), which
    /// keeps the pane on the indeterminate spinner (#93).
    @Published var asrDownloadFraction: Double?
    /// True while a just-downloaded model compiles/loads onto the Neural Engine —
    /// the phase after the 0…1 fraction reaches 100%, which WhisperKit reports no
    /// further progress for. The pane shows "Preparing…" here rather than a bar
    /// frozen at 100%.
    @Published var asrPreparing = false
    @Published var asrDownloadError = ""
    @Published var asrDeleting: String?
    @Published var asrDeleteError = ""
    @Published var installed: [OllamaClient.InstalledModel]? // nil = checking, [] = Ollama down
    @Published var pullingModel: String?
    @Published var pullStatus = ""
    @Published var pullFraction: Double?
    @Published var pullError = ""
    @Published var deletingModel: String?
    @Published var deleteError = ""
    @Published var customModel = ""
    @Published var pttKey = ""
    @Published var toggleKey = ""
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
    @Published var axTrusted = false
    @Published var status = ""
    @Published var statusIsError = false
    @Published var recordingField: RecordingField?

    var modeNames: [String] = []
    var llmModes: Set<String> = []
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
    var onCommit: (() -> Void)?
    var onSelectInputDevice: ((String?) -> Void)?
    var onRecord: ((RecordingField) -> Void)?
    var onSelectModel: ((String) -> Void)?
    var onInstallModel: ((String) -> Void)?
    var onDeleteModel: ((String) -> Void)?
    var onRefreshModels: (() -> Void)?
    /// Speech pane, the ASR analogues of `onSelectModel` / `onInstallModel`
    /// (ADR-0006): select an already-downloaded model as active; download an
    /// available one's weights so it becomes selectable.
    var onSelectASRModel: ((String) -> Void)?
    var onDownloadASRModel: ((String) -> Void)?
    /// Abort an in-flight download/prepare and return the row to its pre-download
    /// state, so a slow or stalled fetch (or the post-100% compile) can be escaped.
    var onCancelASRDownload: (() -> Void)?
    /// Delete a downloaded model's on-disk weights to reclaim space (#95). If it
    /// was active, dictation falls back to Parakeet until another is selected.
    var onDeleteASRModel: ((String) -> Void)?
    var onEditFile: (() -> Void)?
    var onCheckUpdates: (() -> Void)?
    /// History pane row actions, mediated by SettingsController (which owns the
    /// store and the pasteboard). Copy puts the row's polished text on the
    /// pasteboard; copy-raw puts the pre-Polish `rawText` there; flag toggles
    /// the row's local bookmark; re-run Polish reshapes the stored raw
    /// transcript under the named Mode; delete removes one row; clear empties
    /// the store.
    var onCopyHistory: ((HistoryEntry) -> Void)?
    var onCopyRawHistory: ((HistoryEntry) -> Void)?
    var onFlagHistory: ((HistoryEntry) -> Void)?
    var onRerunPolish: ((HistoryEntry, String) -> Void)?
    var onDeleteHistory: ((HistoryEntry) -> Void)?
    var onClearHistory: (() -> Void)?

    var ollamaDown: Bool {
        installed?.isEmpty ?? false
    }

    /// False only when we can see Ollama's model list and ours isn't in it.
    var selectedModelInstalled: Bool {
        guard let installed, !installed.isEmpty else { return true }
        return installed.contains { $0.name == selectedModel }
    }
}
