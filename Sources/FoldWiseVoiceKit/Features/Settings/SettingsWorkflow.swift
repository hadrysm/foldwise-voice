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
    typealias ScheduleStatusClear = @MainActor ((@MainActor () -> Void)?) -> Void
    typealias Copy = @MainActor (String) -> Void

    private let config: Config
    private let model: SettingsModel
    private let historyStore: HistoryStore
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
        observeConfigChanges()
    }

    func populatePreferences() {
        model.configurationRecoveryMessage = config.recovery?.message
        populateModes()
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

    private func populateModes() {
        model.modeSelection = ModePresentationFactory.projection(
            modes: config.orderedModes,
            selection: config.selection
        )
        model.modes = config.orderedModes
        model.selectedModel = config.mode.llmModel ?? ""
    }

    private func observeConfigChanges() {
        config.onChange { [weak self] changes in
            guard let self else { return }
            if changes.contains(.modeLibrary) {
                populateModes()
            } else if changes.contains(.selection) {
                model.modeSelection = model.modeSelection.selecting(config.selection)
                model.selectedModel = config.mode.llmModel ?? ""
            }
        }
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

    func selectMode(_ selection: DictationSelection) {
        do {
            try config.select(selection)
            setStatus("Dictation selection updated ✓", isError: false, clearAfter: true)
        } catch {
            populateModes()
            setStatus(
                "⚠️ couldn’t select Mode: \(error.localizedDescription)",
                isError: true
            )
        }
    }

    func beginAddMode() {
        guard !config.isReadOnly else { return }
        model.modeEditor = ModeEditorState(
            purpose: .add,
            draft: ModeEditorDraft(
                name: "",
                icon: "wand.and.sparkles",
                model: model.installed?.first?.name ?? "",
                transformation: .inPlace,
                systemPrompt: "",
                vocabularyText: ""
            )
        )
    }

    func beginEditMode(_ id: ModeID) {
        guard !config.isReadOnly, let mode = config.mode(id: id) else { return }
        let modelName = mode.llmModel ?? ""
        model.modeEditor = ModeEditorState(
            purpose: .edit(id),
            draft: ModeEditorDraft(
                name: mode.name,
                icon: mode.icon,
                model: modelName,
                transformation: mode.transformation,
                systemPrompt: mode.systemPrompt ?? "",
                vocabularyText: mode.vocab.joined(separator: "\n")
            )
        )
    }

    func saveModeEditor() {
        guard var editor = model.modeEditor else { return }
        let editingID: ModeID? = if case let .edit(id) = editor.purpose { id } else { nil }
        let evaluation = ModeEditorPolicy.evaluate(
            editor.draft,
            existingModes: config.orderedModes,
            editingID: editingID,
            installedModels: Set(model.installed?.map(\.name) ?? [])
        )
        editor.issues = evaluation.issues
        editor.persistenceError = nil
        guard let submission = evaluation.submission else {
            model.modeEditor = editor
            return
        }

        do {
            switch editor.purpose {
            case .add:
                let id = ModeID.random()
                let mode = makeMode(id: id, from: submission)
                try config.replaceModes(
                    config.orderedModes + [mode],
                    selection: .mode(id)
                )
            case let .edit(id):
                guard config.mode(id: id) != nil else {
                    throw ConfigError.invalid("Mode no longer exists.")
                }
                try config.saveMode(makeMode(id: id, from: submission))
            }
            model.modeEditor = nil
        } catch {
            editor.persistenceError = "Couldn't save Mode: \(error.localizedDescription)"
            model.modeEditor = editor
        }
    }

    func cancelModeEditor() {
        model.modeEditor = nil
    }

    private func makeMode(id: ModeID, from submission: ModeEditorSubmission) -> Mode {
        Mode(
            id: id,
            name: submission.name,
            icon: submission.icon,
            asrModel: config.asrModel,
            llmModel: submission.model,
            transformation: submission.transformation,
            systemPrompt: submission.systemPrompt,
            vocabulary: submission.vocabulary
        )
    }

    func selectInputDevice(_ uid: String?) {
        do {
            try config.setInputDevice(uid)
            setStatus("Saved ✓", isError: false, clearAfter: true)
        } catch {
            setStatus("⚠️ save failed: \(error.localizedDescription)", isError: true)
        }
    }

    func copyHistory(_ entry: HistoryEntry) {
        copy(entry.text)
    }

    @discardableResult
    func performHistoryCommand(
        _ command: DictationRowCommand,
        for entry: HistoryEntry
    ) -> Task<Void, Never>? {
        switch command {
        case .copyDisplayed:
            copyHistory(entry)
            return nil
        case .copyRaw:
            copyRawHistory(entry)
            return nil
        case .toggleFlag:
            flagHistory(entry)
            return nil
        case let .rerunPolish(modeID):
            return Task { @MainActor in
                await rerunPolish(entry, modeID: modeID)
            }
        case .delete:
            deleteHistory(entry)
            return nil
        }
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

    func rerunPolish(_ entry: HistoryEntry, modeID: ModeID) async {
        guard let mode = config.mode(id: modeID) else {
            setStatus("⚠️ Mode is no longer available. Choose another Mode.", isError: true)
            return
        }
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

        let retentionChanged = config.historyRetention != model.retention
        var preferences = config.preferences
        if !model.asrModel.isEmpty { preferences.asrModel = model.asrModel }
        preferences.hotkey = ptt
        preferences.toggleHotkey = toggle.isEmpty ? nil : toggle
        preferences.pauseAudio = model.pauseAudio
        preferences.appearance = model.appearance
        preferences.saveHistory = model.saveHistory
        preferences.historyRetention = model.retention
        // Transient auto-collapse never mutates this preference.
        preferences.sidebarCollapsed = model.sidebar.prefersCollapsed

        do {
            try config.apply(preferences)
        } catch {
            populatePreferences()
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
