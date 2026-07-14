import Foundation

@MainActor
protocol LLMModelManaging {
    typealias LLMProgress = @MainActor (String, Double?) -> Void

    func list() async -> [OllamaClient.InstalledModel]
    func pull(_ name: String, progress: @escaping LLMProgress) async -> String?
    func delete(_ name: String) async -> String?
}

@MainActor
protocol ASRModelManaging {
    typealias ASRProgress = @MainActor (Double) -> Void
    typealias ASRLoading = @MainActor (Bool) -> Void

    func prepare(
        _ entry: ASRModelCatalog.Entry,
        progress: @escaping ASRProgress,
        loading: @escaping ASRLoading
    ) async -> String?
    func delete(_ entry: ASRModelCatalog.Entry) async -> String?
}

@MainActor
protocol SettingsUpdateChecking {
    var isAvailable: Bool { get }
    func check() async -> UpdateChecker.CheckResult
}

/// Deterministic settings decisions shared by the SwiftUI/AppKit shell.
@MainActor
final class SettingsWorkflow {
    typealias Persist = @MainActor () throws -> Void
    typealias ScheduleStatusClear = @MainActor ((@MainActor () -> Void)?) -> Void
    typealias Copy = @MainActor (String) -> Void

    private let config: Config
    private let model: SettingsModel
    private let historyStore: HistoryStore
    private let persist: Persist
    private let now: () -> Date
    private let scheduleStatusClear: ScheduleStatusClear
    private let llmModels: any LLMModelManaging
    private let asrModels: any ASRModelManaging
    private let copy: Copy
    private let statsStore: StatsStore
    private let calendar: Calendar
    private let reprocessor: HistoryReprocessor
    private let updates: any SettingsUpdateChecking
    private let reportUpdate: (String) -> Void
    private var llmRefreshID: UUID?
    private var llmMutationID: UUID?
    private var asrDownloadID: UUID?
    private var asrDownloadTask: Task<Void, Never>?
    private var asrDeleteID: UUID?

    convenience init(
        config: Config,
        model: SettingsModel,
        historyStore: HistoryStore,
        persist: @escaping Persist,
        now: @escaping () -> Date,
        scheduleStatusClear: @escaping ScheduleStatusClear,
        copy: @escaping Copy,
        statsStore: StatsStore = JSONStatsStore(url: JSONStatsStore.defaultURL),
        calendar: Calendar = .current,
        polish: @escaping (String, Mode) async -> String = Pipeline.ollamaPolish,
        updates: (any SettingsUpdateChecking)? = nil,
        reportUpdate: @escaping (String) -> Void = { _ in }
    ) {
        self.init(
            config: config,
            model: model,
            historyStore: historyStore,
            persist: persist,
            now: now,
            scheduleStatusClear: scheduleStatusClear,
            llmModels: LiveLLMModelManager(),
            asrModels: LiveASRModelManager(),
            copy: copy,
            statsStore: statsStore,
            calendar: calendar,
            polish: polish,
            updates: updates,
            reportUpdate: reportUpdate
        )
    }

    init(
        config: Config,
        model: SettingsModel,
        historyStore: HistoryStore,
        persist: @escaping Persist,
        now: @escaping () -> Date,
        scheduleStatusClear: @escaping ScheduleStatusClear,
        llmModels: any LLMModelManaging,
        asrModels: any ASRModelManaging,
        copy: @escaping Copy,
        statsStore: StatsStore = JSONStatsStore(url: JSONStatsStore.defaultURL),
        calendar: Calendar = .current,
        polish: @escaping (String, Mode) async -> String = Pipeline.ollamaPolish,
        updates: (any SettingsUpdateChecking)? = nil,
        reportUpdate: @escaping (String) -> Void = { _ in }
    ) {
        self.config = config
        self.model = model
        self.historyStore = historyStore
        self.persist = persist
        self.now = now
        self.scheduleStatusClear = scheduleStatusClear
        self.llmModels = llmModels
        self.asrModels = asrModels
        self.copy = copy
        self.statsStore = statsStore
        self.calendar = calendar
        reprocessor = HistoryReprocessor(store: historyStore, polish: polish)
        self.updates = updates ?? LiveSettingsUpdateChecker()
        self.reportUpdate = reportUpdate
    }

    func populatePreferences() {
        model.modeNames = config.modeOrder
        model.llmModes = Set(config.modeOrder.filter { config.modes[$0]?.usesLLM == true })
        model.activeMode = config.activeMode
        model.selectedModel = config.llmModel ?? ""
        model.asrModel = config.asrModel
        model.asrDownloaded = [ASRModelCatalog.defaultID]
        if ASRModelCatalog.entry(for: config.asrModel) != nil {
            model.asrDownloaded.insert(config.asrModel)
        }
        model.asrDownloading = nil
        model.asrDownloadError = ""
        model.asrDeleting = nil
        model.asrDeleteError = ""
        model.pttKey = config.hotkey
        model.toggleKey = config.toggleHotkey ?? ""
        model.pauseAudio = config.pauseAudio
        model.appearance = config.appearance
        model.saveHistory = config.saveHistory
        model.retention = config.historyRetention
        model.sidebar = SidebarPresentation(prefersCollapsed: config.sidebarCollapsed)
        model.status = ""
    }

    func populateHistory() {
        model.historyEntries = historyStore.load()
        refreshStreak()
    }

    func observeHistoryAppends() {
        historyStore.onAppend { [weak self] entry in
            Task { @MainActor in
                guard let self else { return }
                self.prependHistory(entry)
                self.refreshStreak()
            }
        }
    }

    func checkForUpdates() {
        guard updates.isAvailable else {
            model.updateState = .unavailable
            return
        }
        if case .checking = model.updateState { return }
        model.updateState = .checking
        Task { @MainActor in
            switch await updates.check() {
            case .upToDate:
                model.updateState = .upToDate
            case let .updateAvailable(version, downloadURL):
                model.updateState = .available(version: version, downloadURL: downloadURL)
                reportUpdate(version)
            case .failed:
                model.updateState = .failed
            }
        }
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

    func selectLLMModel(_ name: String) {
        model.selectedModel = name
        commit()
    }

    func selectInputDevice(_ uid: String?) {
        config.inputDevice = uid
        do {
            try persist()
            setStatus("Saved ✓", isError: false, clearAfter: true)
        } catch {
            setStatus("⚠️ save failed: \(error.localizedDescription)", isError: true)
        }
    }

    func copyHistory(_ entry: HistoryEntry) {
        copy(entry.text)
    }

    func copyRawHistory(_ entry: HistoryEntry) {
        copy(entry.rawText)
    }

    func flagHistory(_ entry: HistoryEntry) {
        var toggled = entry
        toggled.flagged.toggle()
        historyStore.update(toggled)
        model.historyEntries = historyStore.load()
    }

    func rerunPolish(_ entry: HistoryEntry, modeName: String) async {
        guard let mode = config.modes[modeName] else { return }
        await reprocessor.rerunPolish(entry, mode: mode)
        model.historyEntries = historyStore.load()
    }

    func deleteHistory(_ entry: HistoryEntry) {
        historyStore.delete(id: entry.id)
        model.historyEntries = historyStore.load()
    }

    func clearHistory() {
        historyStore.clearAll()
        statsStore.reset()
        model.historyEntries = historyStore.load()
        refreshStreak()
    }

    private func prependHistory(_ entry: HistoryEntry) {
        guard !model.historyEntries.contains(where: { $0.id == entry.id }) else { return }
        model.historyEntries.insert(entry, at: 0)
    }

    private func refreshStreak() {
        model.currentStreak = StreakRules.display(statsStore.load(), now: now(), calendar: calendar)
    }

    func refreshLLMModels() {
        let requestID = UUID()
        llmRefreshID = requestID
        model.installed = nil
        Task { @MainActor in
            let installed = await llmModels.list()
            guard llmRefreshID == requestID else { return }
            model.installed = installed
        }
    }

    func installLLMModel(_ name: String) {
        guard model.pullingModel == nil, model.deletingModel == nil, !name.isEmpty else { return }
        let operationID = UUID()
        llmMutationID = operationID
        model.pullingModel = name
        model.pullError = ""
        model.pullStatus = "contacting Ollama…"
        model.pullFraction = nil
        Task { @MainActor in
            let error = await llmModels.pull(name) { [weak self] status, fraction in
                guard let self, llmMutationID == operationID else { return }
                model.pullStatus = status
                model.pullFraction = fraction
            }
            guard llmMutationID == operationID else { return }
            llmMutationID = nil
            model.pullingModel = nil
            if let error {
                model.pullError = "Couldn't install \(name): \(error)"
            } else {
                model.customModel = ""
                selectLLMModel(name)
                refreshLLMModels()
            }
        }
    }

    func deleteLLMModel(_ name: String) {
        guard model.deletingModel == nil, model.pullingModel == nil, !name.isEmpty else { return }
        let operationID = UUID()
        llmMutationID = operationID
        model.deletingModel = name
        model.deleteError = ""
        Task { @MainActor in
            let error = await llmModels.delete(name)
            guard llmMutationID == operationID else { return }
            llmMutationID = nil
            model.deletingModel = nil
            if let error {
                model.deleteError = "Couldn't uninstall \(name): \(error)"
            } else {
                refreshLLMModels()
            }
        }
    }

    func selectASRModel(_ id: String) {
        model.asrModel = id
        commit()
    }

    func downloadASRModel(_ id: String) {
        guard asrDownloadTask == nil, model.asrDeleting == nil,
              let entry = ASRModelCatalog.entry(for: id) else { return }
        let operationID = UUID()
        asrDownloadID = operationID
        model.asrDownloading = id
        model.asrDownloadError = ""
        model.asrDownloadFraction = nil
        model.asrPreparing = false
        asrDownloadTask = Task { @MainActor in
            let failure = await asrModels.prepare(
                entry,
                progress: { [weak self] fraction in
                    guard let self, asrDownloadID == operationID else { return }
                    model.asrDownloadFraction = fraction
                },
                loading: { [weak self] loading in
                    guard let self, asrDownloadID == operationID else { return }
                    model.asrPreparing = loading
                }
            )
            asrDownloadTask = nil
            guard asrDownloadID == operationID else { return }
            asrDownloadID = nil
            clearASRDownloadUI()
            if let message = ASRModelCatalog.downloadError(for: entry, failure: failure) {
                model.asrDownloadError = message
            } else {
                model.asrDownloaded.insert(id)
            }
        }
    }

    func cancelASRDownload() {
        asrDownloadID = nil
        asrDownloadTask?.cancel()
        clearASRDownloadUI()
    }

    func deleteASRModel(_ id: String) {
        guard asrDeleteID == nil, asrDownloadTask == nil,
              id != ASRModelCatalog.defaultID,
              let entry = ASRModelCatalog.entry(for: id) else { return }
        let operationID = UUID()
        asrDeleteID = operationID
        model.asrDeleting = id
        model.asrDeleteError = ""
        Task { @MainActor in
            let failure = await asrModels.delete(entry)
            guard asrDeleteID == operationID else { return }
            asrDeleteID = nil
            model.asrDeleting = nil
            if let failure {
                model.asrDeleteError = "Couldn't delete \(entry.name): \(failure)"
                return
            }
            model.asrDownloaded.remove(id)
            if ASRModelCatalog.deleteOutcome(for: entry, isActive: model.asrModel == id)
                .fallsBackToDefault {
                selectASRModel(ASRModelCatalog.defaultID)
            }
        }
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
        config.appearance = model.appearance
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

    private func clearASRDownloadUI() {
        model.asrDownloading = nil
        model.asrDownloadFraction = nil
        model.asrPreparing = false
    }
}
