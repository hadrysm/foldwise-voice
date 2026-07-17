import Foundation

@MainActor
protocol LLMModelManaging {
    typealias LLMProgress = @MainActor (String, Double?) -> Void

    func list() async -> [OllamaClient.InstalledModel]
    func pull(_ name: String, progress: @escaping LLMProgress) async -> String?
    func delete(_ name: String) async -> String?
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
    typealias DeleteASRModel = @MainActor (String) async -> String?

    private let config: Config
    private let model: SettingsModel
    private let historyStore: HistoryStore
    private let now: () -> Date
    private let scheduleStatusClear: ScheduleStatusClear
    private let llmModels: any LLMModelManaging
    private let deleteASRModel: DeleteASRModel
    private let asrLifecycle: ASRModelLifecycle
    private let copy: Copy
    private let statsStore: StatsStore
    private let calendar: Calendar
    private let reprocessor: HistoryReprocessor
    private let updates: any SettingsUpdateChecking
    private let reportUpdate: (String) -> Void
    private let updateHotkeys: (ShortcutBindings) throws -> Void
    private let captureGate: ShortcutCaptureGate
    private var llmRefreshID: UUID?
    private var llmMutationID: UUID?
    private var asrDeleteID: UUID?
    private var asrDownloadID: UUID?
    private var asrSnapshotTask: Task<Void, Never>?

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
        reportUpdate: @escaping (String) -> Void = { _ in },
        updateHotkeys: ((ShortcutBindings) throws -> Void)? = nil,
        captureGate: ShortcutCaptureGate = ShortcutCaptureGate(),
        asrLifecycle: ASRModelLifecycle
    ) {
        self.init(
            config: config,
            model: model,
            historyStore: historyStore,
            now: now,
            scheduleStatusClear: scheduleStatusClear,
            llmModels: LiveLLMModelManager(),
            deleteASRModel: deleteStoredASRModel,
            asrLifecycle: asrLifecycle,
            copy: copy,
            statsStore: statsStore,
            calendar: calendar,
            polish: polish,
            updates: updates,
            reportUpdate: reportUpdate,
            updateHotkeys: updateHotkeys,
            captureGate: captureGate
        )
    }

    init(
        config: Config,
        model: SettingsModel,
        historyStore: HistoryStore,
        now: @escaping () -> Date,
        scheduleStatusClear: @escaping ScheduleStatusClear,
        llmModels: any LLMModelManaging,
        deleteASRModel: @escaping DeleteASRModel,
        asrLifecycle: ASRModelLifecycle,
        copy: @escaping Copy,
        statsStore: StatsStore = JSONStatsStore(url: JSONStatsStore.defaultURL),
        calendar: Calendar = .current,
        polish: @escaping (String, Mode) async -> String = Pipeline.ollamaPolish,
        updates: (any SettingsUpdateChecking)? = nil,
        reportUpdate: @escaping (String) -> Void = { _ in },
        updateHotkeys: ((ShortcutBindings) throws -> Void)? = nil,
        captureGate: ShortcutCaptureGate = ShortcutCaptureGate()
    ) {
        self.config = config
        self.model = model
        self.historyStore = historyStore
        self.now = now
        self.scheduleStatusClear = scheduleStatusClear
        self.llmModels = llmModels
        self.deleteASRModel = deleteASRModel
        self.asrLifecycle = asrLifecycle
        self.copy = copy
        self.statsStore = statsStore
        self.calendar = calendar
        reprocessor = HistoryReprocessor(store: historyStore, polish: polish)
        self.updates = updates ?? LiveSettingsUpdateChecker()
        self.reportUpdate = reportUpdate
        self.updateHotkeys = updateHotkeys ?? { try config.setShortcutBindings($0) }
        self.captureGate = captureGate
        observeConfigChanges()
        observeASRLifecycle()
    }

    func populatePreferences() {
        model.configurationRecoveryMessage = config.recovery?.message
        populateModes()
        model.asrModel = config.asrModel
        model.asrDeleting = nil
        model.asrDeleteError = ""
        populateShortcutBindings()
        model.pauseAudio = config.pauseAudio
        model.appearance = config.appearance
        model.saveHistory = config.saveHistory
        model.retention = config.historyRetention
        model.sidebar = SidebarPresentation(prefersCollapsed: config.sidebarCollapsed)
        model.status = ""
        reconcileASRAvailability()
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
            if changes.contains(.asrModel) {
                model.asrModel = config.asrModel
            }
        }
    }

    private func observeASRLifecycle() {
        let lifecycle = asrLifecycle
        asrSnapshotTask = Task { [weak self] in
            let updates = await lifecycle.snapshots()
            for await snapshot in updates {
                guard let self, !Task.isCancelled else { return }
                applyASRSnapshot(snapshot)
            }
        }
    }

    private func applyASRSnapshot(_ snapshot: ASRModelLifecycleSnapshot) {
        guard snapshot.storedSelection == config.asrModel else { return }
        model.asrCatalog = snapshot.models
        model.asrModel = snapshot.storedSelection
        model.asrDownloaded = Set(snapshot.models.filter(\.isAvailable).map(\.id))
        model.asrSwitching = nil
        model.asrRestoring = nil
        switch snapshot.recovery {
        case let .storedSelectionUnavailable(modelID, fallbackModelID):
            let selected = asrModelName(modelID, in: snapshot.models)
            let fallback = asrModelName(fallbackModelID, in: snapshot.models)
            model.asrRecoveryMessage = "\(selected) is unavailable. Using \(fallback) until you download it again."
        case let .storedSelectionUnknown(modelID, fallbackModelID):
            let fallback = asrModelName(fallbackModelID, in: snapshot.models)
            model.asrRecoveryMessage = "Stored speech model “\(modelID)” isn't recognized. Using \(fallback)."
        case nil:
            model.asrRecoveryMessage = nil
        }
        switch snapshot.operation {
        case let .downloading(modelID, fraction):
            model.asrDownloading = modelID
            model.asrDownloadFraction = fraction
            model.isASRBootstrapping = false
        case let .bootstrapping(fraction):
            model.asrDownloading = ASRModelCatalog.defaultID
            model.asrDownloadFraction = fraction
            model.isASRBootstrapping = true
        case let .switching(modelID):
            model.asrSwitching = modelID
            model.asrDownloading = nil
            model.asrDownloadFraction = nil
            model.isASRBootstrapping = false
        case let .restoring(modelID):
            model.asrRestoring = modelID
            model.asrDownloading = nil
            model.asrDownloadFraction = nil
            model.isASRBootstrapping = false
        case nil:
            model.asrDownloading = nil
            model.asrDownloadFraction = nil
            model.isASRBootstrapping = false
        }
        switch snapshot.failure {
        case let .downloadFailed(modelID, reason):
            let name = asrModelName(modelID, in: snapshot.models)
            model.asrDownloadError = "Couldn't download \(name): \(reason)"
        case let .downloadedDataInvalid(modelID):
            let name = asrModelName(modelID, in: snapshot.models)
            model.asrDownloadError = "Downloaded data for \(name) is incomplete or corrupt."
        case let .bootstrapFailed(reason):
            model.asrDownloadError = "Couldn't prepare the default speech model: \(reason)"
        case let .engineLoadFailed(modelID, reason):
            let name = asrModelName(modelID, in: snapshot.models)
            model.asrDownloadError = "Couldn't load \(name): \(reason)"
        case let .selectionFailed(modelID, reason):
            let name = asrModelName(modelID, in: snapshot.models)
            model.asrDownloadError = "Couldn't switch to \(name): \(reason)"
        case .selectionCanceled:
            model.asrDownloadError = ""
        case let .selectionDegraded(modelID, fallbackModelID, reason):
            let selected = asrModelName(modelID, in: snapshot.models)
            let fallback = asrModelName(fallbackModelID, in: snapshot.models)
            let detail = reason.map { ": \($0)" } ?? "."
            model.asrDownloadError = "Couldn't restore \(selected). Using \(fallback)\(detail)"
        case nil:
            model.asrDownloadError = ""
        }
        model.canRetryASRBootstrap = snapshot.isDictationBlocked
            && snapshot.operation == nil
            && snapshot.failure?.allowsBootstrapRetry == true
    }

    private func asrModelName(_ id: String, in models: [ASRModelDescriptor]) -> String {
        models.first { $0.id == id }?.name ?? id
    }

    private func reconcileASRAvailability() {
        Task { await asrLifecycle.reconcileAvailability() }
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

    @discardableResult
    func beginRecording(_ field: SettingsModel.RecordingField) -> Bool {
        if model.recordingField == field {
            cancelRecording()
            return false
        }
        model.recordingField = field
        captureGate.isCapturing = true
        return true
    }

    func finishRecording(with key: String?) {
        guard let field = model.recordingField else { return }
        guard let key, !key.isEmpty else {
            cancelRecording()
            return
        }
        switch field {
        case .ptt:
            model.pttKey = key
        case .toggle:
            model.toggleKey = key
        case .cycle:
            model.cycleKey = key
        }
        commit(changedShortcut: field)
        model.recordingField = nil
        captureGate.isCapturing = false
    }

    func cancelRecording() {
        populateShortcutBindings()
        model.recordingField = nil
        captureGate.isCapturing = false
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
        model.modeEditor = editorState(for: mode, purpose: .edit(id), name: mode.name)
    }

    func beginDuplicateMode(_ id: ModeID) {
        guard !config.isReadOnly, let mode = config.mode(id: id) else { return }
        let name = ModeEditorPolicy.duplicateName(
            for: mode.name,
            existingNames: config.orderedModes.map(\.name)
        )
        model.modeEditor = editorState(for: mode, purpose: .duplicate(id), name: name)
    }

    private func editorState(
        for mode: Mode,
        purpose: ModeEditorPurpose,
        name: String
    ) -> ModeEditorState {
        let modelName = mode.llmModel ?? ""
        return ModeEditorState(
            purpose: purpose,
            draft: ModeEditorDraft(
                name: name,
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
            installedModels: model.installed.map { Set($0.map(\.name)) }
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
            case let .duplicate(sourceID):
                let id = ModeID.random()
                let mode = makeMode(id: id, from: submission)
                guard let candidate = ModeLibraryPolicy.insertingDuplicate(
                    mode,
                    after: sourceID,
                    in: config.orderedModes
                ) else {
                    throw ConfigError.invalid("Source Mode no longer exists.")
                }
                try config.replaceModes(candidate.modes, selection: candidate.selection)
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

    func moveMode(_ id: ModeID, direction: ModeMoveDirection) {
        guard !config.isReadOnly,
              let candidate = ModeLibraryPolicy.moving(
                  id,
                  direction: direction,
                  in: config.orderedModes,
                  selection: config.selection
              )
        else { return }
        do {
            try config.replaceModes(candidate.modes, selection: candidate.selection)
            setStatus("Mode order updated ✓", isError: false, clearAfter: true)
        } catch {
            populateModes()
            setStatus("⚠️ couldn't reorder Mode: \(error.localizedDescription)", isError: true)
        }
    }

    func requestModeDeletion(_ id: ModeID) {
        guard !config.isReadOnly, let mode = config.mode(id: id) else { return }
        let modelName = mode.llmModel ?? "referenced AI model"
        model.modePendingDeletion = ModeDeletionState(
            id: id,
            title: "Delete \(mode.name)?",
            message: "Your History will remain. The \(modelName) AI model will not be uninstalled."
        )
    }

    func confirmModeDeletion() {
        guard let pending = model.modePendingDeletion,
              let candidate = ModeLibraryPolicy.deleting(
                  pending.id,
                  from: config.orderedModes,
                  selection: config.selection
              )
        else {
            model.modePendingDeletion = nil
            return
        }
        do {
            try config.replaceModes(candidate.modes, selection: candidate.selection)
            model.modePendingDeletion = nil
            setStatus("Mode deleted ✓", isError: false, clearAfter: true)
        } catch {
            populateModes()
            setStatus("⚠️ couldn't delete Mode: \(error.localizedDescription)", isError: true)
        }
    }

    func cancelModeDeletion() {
        model.modePendingDeletion = nil
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
        guard !model.hasActiveASRManagementOperation else { return }
        Task { await asrLifecycle.select(id) }
    }

    func downloadASRModel(_ id: String) {
        guard asrDeleteID == nil, asrDownloadID == nil,
              !model.hasActiveASRManagementOperation else { return }
        let operationID = UUID()
        asrDownloadID = operationID
        Task { @MainActor in
            await asrLifecycle.download(id)
            guard asrDownloadID == operationID else { return }
            asrDownloadID = nil
        }
    }

    func cancelASRDownload() {
        cancelASROperation()
    }

    func cancelASROperation() {
        Task { await asrLifecycle.cancelCurrentOperation() }
    }

    func retryASRBootstrap() {
        Task { await asrLifecycle.retryBootstrap() }
    }

    func deleteASRModel(_ id: String) {
        guard asrDeleteID == nil, asrDownloadID == nil,
              !model.hasActiveASRManagementOperation,
              let descriptor = model.asrCatalog.first(where: { $0.id == id }),
              descriptor.allowsDeletion else { return }
        let operationID = UUID()
        asrDeleteID = operationID
        model.asrDeleting = id
        model.asrDeleteError = ""
        Task { @MainActor in
            let failure = await deleteASRModel(id)
            guard asrDeleteID == operationID else { return }
            asrDeleteID = nil
            model.asrDeleting = nil
            if let failure {
                model.asrDeleteError = "Couldn't delete \(descriptor.name): \(failure)"
                return
            }
            await asrLifecycle.reconcileAvailability()
            if model.asrModel == id {
                selectASRModel(ASRModelCatalog.defaultID)
            }
        }
    }

    func commit(changedShortcut: SettingsModel.RecordingField? = nil) {
        let ptt = model.pttKey.trimmingCharacters(in: .whitespaces)
        let toggle = model.toggleKey.trimmingCharacters(in: .whitespaces)
        let cycle = model.cycleKey.trimmingCharacters(in: .whitespaces)
        do {
            _ = try KeyMap.parse(ptt)
            if !toggle.isEmpty { _ = try KeyMap.parse(toggle) }
            if !cycle.isEmpty { _ = try KeyMap.parse(cycle) }
        } catch {
            populateShortcutBindings()
            setStatus("⚠️ \(error.localizedDescription)", isError: true)
            return
        }

        let bindings = ShortcutBindings(
            pushToTalk: ptt,
            toggleRecording: toggle.isEmpty ? nil : toggle,
            modeCycle: cycle.isEmpty ? nil : cycle
        )
        let committedBindings = ShortcutBindings(
            pushToTalk: config.hotkey,
            toggleRecording: config.toggleHotkey,
            modeCycle: config.modeCycleHotkey
        )
        let changedCommands = ShortcutCommand.precedence.filter {
            bindings.value(for: $0) != committedBindings.value(for: $0)
        }
        if !changedCommands.isEmpty {
            let commands = if let changedShortcut {
                [changedShortcut.command] + changedCommands.filter { $0 != changedShortcut.command }
            } else {
                changedCommands
            }
            do {
                for command in commands {
                    try bindings.validateAssignment(for: command)
                }
            } catch {
                populateShortcutBindings()
                setStatus("⚠️ \(error.localizedDescription)", isError: true)
                return
            }
            do {
                try updateHotkeys(bindings)
            } catch {
                populateShortcutBindings()
                setStatus("⚠️ save failed: \(error.localizedDescription)", isError: true)
                return
            }
        }

        let retentionChanged = config.historyRetention != model.retention
        var preferences = config.preferences
        preferences.hotkey = bindings.pushToTalk
        preferences.toggleHotkey = bindings.toggleRecording
        preferences.pauseAudio = model.pauseAudio
        preferences.appearance = model.appearance
        preferences.saveHistory = model.saveHistory
        preferences.historyRetention = model.retention
        // Transient auto-collapse never mutates this preference.
        preferences.sidebarCollapsed = model.sidebar.prefersCollapsed

        if config.isReadOnly || preferences != config.preferences {
            do {
                try config.apply(preferences)
            } catch {
                populatePreferences()
                setStatus("⚠️ save failed: \(error.localizedDescription)", isError: true)
                return
            }
        }

        if retentionChanged {
            // The passive sweep runs only at launch. Apply a newly selected
            // window immediately and reload so an open pane drops purged rows.
            historyStore.sweep(retention: config.historyRetention, now: now())
            model.historyEntries = historyStore.load()
        }
        setStatus("Saved ✓", isError: false, clearAfter: true)
    }

    private func populateShortcutBindings() {
        model.pttKey = config.hotkey
        model.toggleKey = config.toggleHotkey ?? ""
        model.cycleKey = config.modeCycleHotkey ?? ""
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
