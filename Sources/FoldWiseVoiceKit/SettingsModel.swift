// Observable state for the settings window. SettingsController owns the
// instance and wires the callbacks; SettingsView renders it.

import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
    enum Pane: String, CaseIterable, Identifiable {
        case home = "Home"
        case modes = "Modes"
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
    @Published var hudStyle = HUDStyle.classic.rawValue
    @Published var axTrusted = false
    @Published var status = ""
    @Published var statusIsError = false
    @Published var recordingField: RecordingField?

    var modeNames: [String] = []
    var llmModes: Set<String> = []
    /// Loaded from the HistoryStore when the window opens; rendered by the
    /// History pane newest-first. Set before navigation, like `modeNames`.
    var historyEntries: [HistoryEntry] = []

    // wired by SettingsController
    var onCommit: (() -> Void)?
    var onRecord: ((RecordingField) -> Void)?
    var onSelectModel: ((String) -> Void)?
    var onInstallModel: ((String) -> Void)?
    var onDeleteModel: ((String) -> Void)?
    var onRefreshModels: (() -> Void)?
    var onEditFile: (() -> Void)?
    var onCheckUpdates: (() -> Void)?

    var ollamaDown: Bool {
        installed?.isEmpty ?? false
    }

    /// False only when we can see Ollama's model list and ours isn't in it.
    var selectedModelInstalled: Bool {
        guard let installed, !installed.isEmpty else { return true }
        return installed.contains { $0.name == selectedModel }
    }
}
