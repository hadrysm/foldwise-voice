import Foundation

/// Deterministic settings decisions shared by the SwiftUI/AppKit shell.
@MainActor
final class SettingsWorkflow {
    typealias Persist = @MainActor () throws -> Void
    typealias ScheduleStatusClear = @MainActor ((@MainActor () -> Void)?) -> Void

    private let config: Config
    private let model: SettingsModel
    private let historyStore: HistoryStore
    private let persist: Persist
    private let now: () -> Date
    private let scheduleStatusClear: ScheduleStatusClear

    init(
        config: Config,
        model: SettingsModel,
        historyStore: HistoryStore,
        persist: @escaping Persist,
        now: @escaping () -> Date,
        scheduleStatusClear: @escaping ScheduleStatusClear
    ) {
        self.config = config
        self.model = model
        self.historyStore = historyStore
        self.persist = persist
        self.now = now
        self.scheduleStatusClear = scheduleStatusClear
    }

    func populatePreferences() {
        model.modeNames = config.modeOrder
        model.llmModes = Set(config.modeOrder.filter { config.modes[$0]?.usesLLM == true })
        model.activeMode = config.activeMode
        model.selectedModel = config.llmModel ?? ""
        model.asrModel = config.asrModel
        model.pttKey = config.hotkey
        model.toggleKey = config.toggleHotkey ?? ""
        model.pauseAudio = config.pauseAudio
        model.saveHistory = config.saveHistory
        model.retention = config.historyRetention
        model.sidebar = SidebarPresentation(prefersCollapsed: config.sidebarCollapsed)
        model.status = ""
    }

    func beginRecording(_ field: SettingsModel.RecordingField) {
        model.recordingField = field
    }

    func finishRecording(with key: String?) {
        guard let field = model.recordingField else { return }
        model.recordingField = nil
        guard let key, !key.isEmpty else { return }
        switch field {
        case .ptt:
            model.pttKey = key
        case .toggle:
            model.toggleKey = key
        }
        commit()
    }

    func commit() {
        let ptt = model.pttKey.trimmingCharacters(in: .whitespaces)
        let toggle = model.toggleKey.trimmingCharacters(in: .whitespaces)
        do {
            _ = try KeyMap.parse(ptt)
            if !toggle.isEmpty { _ = try KeyMap.parse(toggle) }
        } catch {
            setStatus("⚠️ \(error.localizedDescription)", isError: true)
            return
        }

        if !model.selectedModel.isEmpty {
            config.setLLMModel(model.selectedModel)
        }
        if !model.asrModel.isEmpty {
            config.setASRModel(model.asrModel)
        }
        config.setActiveMode(model.activeMode)
        config.hotkey = ptt
        config.toggleHotkey = toggle.isEmpty ? nil : toggle
        config.pauseAudio = model.pauseAudio
        config.saveHistory = model.saveHistory
        let retentionChanged = config.historyRetention != model.retention
        config.historyRetention = model.retention
        // Transient auto-collapse never mutates `prefersCollapsed`, so only
        // the explicit sidebar toggle can overwrite the user's saved intent.
        config.sidebarCollapsed = model.sidebar.prefersCollapsed

        do {
            try persist()
        } catch {
            setStatus("⚠️ save failed: \(error.localizedDescription)", isError: true)
            return
        }

        if retentionChanged {
            // The passive sweep runs only at launch. Apply a newly selected
            // window immediately and reload so an open pane drops purged rows.
            historyStore.sweep(retention: config.historyRetention, now: now())
            model.historyEntries = historyStore.load()
        }
        setStatus("Saved ✓", isError: false, clearAfter: true)
    }

    private func setStatus(_ text: String, isError: Bool, clearAfter: Bool = false) {
        model.status = text
        model.statusIsError = isError
        guard clearAfter else {
            scheduleStatusClear(nil)
            return
        }
        scheduleStatusClear { [weak self] in
            self?.model.status = ""
        }
    }
}
