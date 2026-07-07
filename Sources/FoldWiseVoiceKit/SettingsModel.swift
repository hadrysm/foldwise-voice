// Observable state for the settings window. SettingsController owns the
// instance and wires the callbacks; SettingsView renders it.

import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
    enum Pane: String, CaseIterable, Identifiable {
        case home = "Home"
        case modes = "Modes"
        case speech = "Speech"
        case models = "Models"
        case configuration = "Configuration"
        case sound = "Sound"
        case history = "History"
        var id: String {
            rawValue
        }

        var icon: String {
            switch self {
            case .home: "house.fill"
            case .modes: "sparkles"
            case .speech: "waveform"
            case .models: "shippingbox.fill"
            case .configuration: "gearshape.fill"
            case .sound: "speaker.wave.2.fill"
            case .history: "clock.fill"
            }
        }

        var tint: Color {
            switch self {
            case .home: .orange
            case .modes: .blue
            case .speech: .indigo
            case .models: .purple
            case .configuration: .gray
            case .sound: .teal
            case .history: .pink
            }
        }

        var title: String {
            switch self {
            case .home: "FoldWise Voice"
            case .modes: "Modes"
            case .speech: "Speech Recognition"
            case .models: "Ollama Models"
            case .configuration: "Keyboard Shortcuts"
            case .sound: "Sound"
            case .history: "Dictation History"
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
    /// Master "Save dictation history" switch, surfaced in the History pane.
    @Published var saveHistory = true
    /// Auto-delete window for history, a control distinct from `saveHistory`.
    @Published var retention = RetentionWindow.default
    @Published var hudStyle = HUDStyle.classic.rawValue
    @Published var axTrusted = false
    @Published var status = ""
    @Published var statusIsError = false
    @Published var recordingField: RecordingField?

    var modeNames: [String] = []
    var llmModes: Set<String> = []
    /// Loaded from the HistoryStore when the window opens and re-read after a
    /// delete or clear-all, so the History pane reflects the store live.
    @Published var historyEntries: [HistoryEntry] = []

    // wired by SettingsController
    var onCommit: (() -> Void)?
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
