// Owns the settings NSWindow and mediates between SettingsModel (UI state)
// and Config/OllamaClient/UpdateChecker. Every change commits straight to
// modes.json; there is no Save button.

import AppKit
import SwiftUI

@MainActor
final class SettingsController {
    private let config: Config
    private let historyStore: HistoryStore
    private let statsStore: StatsStore
    private let reprocessor: HistoryReprocessor
    let model = SettingsModel() // internal (not private) so @testable tests can drive the wired closures
    private lazy var workflow = SettingsWorkflow(
        config: config,
        model: model,
        historyStore: historyStore,
        persist: { [config] in try config.saveAndNotify() },
        now: Date.init,
        scheduleStatusClear: { [weak self] clear in self?.scheduleStatusClear(clear) }
    )
    private var window: NSWindow?
    private var keyMonitor: Any?
    private var statusClearTask: Task<Void, Never>?
    /// The in-flight ASR download/prepare, retained so the Speech pane's Cancel
    /// can abort it; nil whenever no download is running.
    private var asrDownloadTask: Task<Void, Never>?
    private var closeObserver: NSObjectProtocol?

    /// Wired by AppDelegate so a manual check here also lights up the
    /// menu-bar "Update Available" item.
    var onUpdateAvailable: ((String) -> Void)?

    init(config: Config, historyStore: HistoryStore, statsStore: StatsStore) {
        self.config = config
        self.historyStore = historyStore
        self.statsStore = statsStore
        reprocessor = HistoryReprocessor(store: historyStore)
        wire()
        // Live-prepend: the store owns change propagation (ADR-0003), so
        // subscribe once here — a dictation spoken while the pane is open appears
        // at the top without a reload, and the Stats pane's streak refreshes with
        // it. Registered before the hotkey listener starts (AppMain order), so no
        // append can race registration, and after AppMain's streak-advance
        // observer, so the streak this re-reads reflects the just-appended entry.
        // The store fires this off the main thread from the pipeline's record seam.
        historyStore.onAppend { [weak self] entry in
            Task { @MainActor in
                self?.prependHistory(entry)
                self?.refreshStreak()
            }
        }
    }

    deinit {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
    }

    func show() {
        if window == nil { build() }
        populate()
        // Accessory apps never own the menu bar; become a regular app while
        // settings is open so the menu bar shows FoldWise Voice, not whatever
        // app was frontmost before.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func wire() {
        model.onCommit = { [weak self] in self?.workflow.commit() }
        model.onRecord = { [weak self] field in self?.startRecording(field) }
        model.onSelectModel = { [weak self] name in self?.selectModel(name) }
        model.onInstallModel = { [weak self] name in self?.installModel(name) }
        model.onDeleteModel = { [weak self] name in self?.deleteModel(name) }
        model.onRefreshModels = { [weak self] in self?.refreshModels() }
        model.onSelectASRModel = { [weak self] id in self?.selectASRModel(id) }
        model.onDownloadASRModel = { [weak self] id in self?.downloadASRModel(id) }
        model.onCancelASRDownload = { [weak self] in self?.cancelASRDownload() }
        model.onDeleteASRModel = { [weak self] id in self?.deleteASRModel(id) }
        model.onEditFile = { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.open(config.path)
        }
        model.onCheckUpdates = { [weak self] in self?.checkForUpdates() }
        model.onCopyHistory = { [weak self] entry in self?.copyToPasteboard(entry.text) }
        model.onCopyRawHistory = { [weak self] entry in self?.copyToPasteboard(entry.rawText) }
        model.onFlagHistory = { [weak self] entry in self?.flagHistory(entry) }
        model.onRerunPolish = { [weak self] entry, modeName in
            self?.rerunPolish(entry, modeName: modeName)
        }
        model.onDeleteHistory = { [weak self] entry in self?.deleteHistory(entry) }
        model.onClearHistory = { [weak self] in self?.clearHistory() }
    }

    private func build() {
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        let win = Self.makeMainWindow(contentViewController: hosting)
        win.center()
        win.setFrameAutosaveName("FoldWiseMainWindow")
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: win, queue: .main
        ) { _ in
            // Back to menu-bar-only once settings closes.
            Task { @MainActor in NSApp.setActivationPolicy(.accessory) }
        }
        window = win
    }

    /// Main-window chrome, internal (not private) so the titlebar tests pin
    /// the exact traffic-light geometry the app ships.
    static func makeMainWindow(contentViewController: NSViewController) -> NSWindow {
        let win = NSWindow(contentViewController: contentViewController)
        win.title = "FoldWise Voice"
        win.styleMask = [
            .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView,
        ]
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        // 980×720 on first launch, 880×640 minimum; the user's size is
        // restored by the standard frame autosave (PRD #103).
        win.setContentSize(NSSize(width: 980, height: 720))
        win.contentMinSize = NSSize(width: 880, height: 640)
        return win
    }

    private func populate() {
        workflow.populatePreferences()
        // The active model must already be on disk (it's transcribing), so seed
        // the downloaded set with the default plus the persisted choice; further
        // downloads join it live. On-disk detection of past downloads is slice 5.
        var downloaded: Set<String> = [ASRModelCatalog.defaultID]
        if ASRModelCatalog.entry(for: config.asrModel) != nil { downloaded.insert(config.asrModel) }
        model.asrDownloaded = downloaded
        model.asrDownloading = nil
        model.asrDownloadError = ""
        model.asrDeleting = nil
        model.asrDeleteError = ""
        model.axTrusted = TextInserter.accessibilityTrusted()
        model.historyEntries = historyStore.load()
        refreshStreak()
        refreshModels()
        checkForUpdates()
    }

    private func refreshModels() {
        model.installed = nil
        Task { @MainActor in
            self.model.installed = await OllamaClient.listModels()
        }
    }

    /// Runs whenever the window opens and on the "Check for Updates" button,
    /// so a pending update can't hide behind the 24-hour passive timer.
    private func checkForUpdates() {
        guard UpdateChecker.currentVersion() != nil else {
            model.updateState = .unavailable
            return
        }
        if case .checking = model.updateState { return }
        model.updateState = .checking
        Task { @MainActor in
            switch await UpdateChecker.checkNow() {
            case .upToDate:
                self.model.updateState = .upToDate
            case let .updateAvailable(version, downloadURL):
                self.model.updateState = .available(
                    version: version, downloadURL: downloadURL
                )
                self.onUpdateAvailable?(version)
            case .failed:
                self.model.updateState = .failed
            }
        }
    }

    // MARK: - Ollama models

    private func selectModel(_ name: String) {
        model.selectedModel = name
        workflow.commit()
    }

    /// Pull `name` from the Ollama library, then make it the polish model.
    private func installModel(_ name: String) {
        guard model.pullingModel == nil, !name.isEmpty else { return }
        model.pullingModel = name
        model.pullError = ""
        model.pullStatus = "contacting Ollama…"
        model.pullFraction = nil
        Task { @MainActor in
            let error = await OllamaClient.pull(model: name) { status, fraction in
                Task { @MainActor in
                    self.model.pullStatus = status
                    self.model.pullFraction = fraction
                }
            }
            self.model.pullingModel = nil
            if let error {
                self.model.pullError = "Couldn't install \(name): \(error)"
            } else {
                self.model.customModel = ""
                self.model.selectedModel = name
                self.workflow.commit()
                self.refreshModels()
            }
        }
    }

    /// Remove `name` from the local Ollama, then refresh the installed list.
    /// Single-flight and blocked while a download runs, so the app is only ever
    /// in one Ollama-mutating state at a time. Removing the active Polish model
    /// deliberately leaves Config untouched (ADR-0003: nothing re-reads it, so
    /// nothing is signalled) — the existing "Not installed — fix…" affordance
    /// picks up the missing model and Polish falls back to the raw transcript.
    private func deleteModel(_ name: String) {
        guard model.deletingModel == nil, model.pullingModel == nil, !name.isEmpty else { return }
        model.deletingModel = name
        model.deleteError = ""
        Task { @MainActor in
            let error = await OllamaClient.delete(model: name)
            self.model.deletingModel = nil
            if let error {
                self.model.deleteError = "Couldn't uninstall \(name): \(error)"
            } else {
                self.refreshModels()
            }
        }
    }

    // MARK: - ASR models (Speech pane)

    /// Make an already-downloaded ASR model active (ADR-0006). `commit` writes
    /// it across every mode via `setASRModel` and notifies the dispatcher, which
    /// performs the drop-before-load swap.
    private func selectASRModel(_ id: String) {
        model.asrModel = id
        workflow.commit()
    }

    /// Fetch an available model's weights so it becomes selectable. Single-flight
    /// and config-untouched: on failure the previous selection is preserved and
    /// an error is shown; on success the id joins the downloaded set (ADR-0005).
    private func downloadASRModel(_ id: String) {
        // `asrDownloadTask` is the single-flight sentinel: it stays set from here
        // until the task actually unwinds — including across a cancel of a
        // possibly-uncooperative engine — so an instant re-click can't start a
        // second concurrent download of the same weights.
        guard asrDownloadTask == nil, let entry = ASRModelCatalog.entry(for: id) else { return }
        model.asrDownloading = id
        model.asrDownloadError = ""
        model.asrDownloadFraction = nil
        model.asrPreparing = false
        asrDownloadTask = Task { @MainActor in
            let failure = await Self.prepareASR(
                entry,
                onProgress: { fraction in Task { @MainActor in self.model.asrDownloadFraction = fraction } },
                onLoading: { loading in Task { @MainActor in self.model.asrPreparing = loading } }
            )
            self.asrDownloadTask = nil
            // A cancel already cleared the pane and released the throwaway engine,
            // so don't resurrect an error or mark the model downloaded on the way out.
            if Task.isCancelled { return }
            self.clearASRDownloadUI()
            if let message = ASRModelCatalog.downloadError(for: entry, failure: failure) {
                self.model.asrDownloadError = message
            } else {
                self.model.asrDownloaded.insert(id)
            }
        }
    }

    /// Abort an in-flight ASR download/prepare and clear the pane at once, so a
    /// slow or stalled fetch — or the post-100% compile phase — can be escaped
    /// without waiting for it to unwind. Cancelling the task cooperatively cancels
    /// the engine's load (see `WhisperTranscriber.prepare`); `asrDownloadTask` is
    /// left set until that unwind completes so a re-click can't race a second
    /// download, and the task's completion nils it and no-ops via `Task.isCancelled`.
    private func cancelASRDownload() {
        asrDownloadTask?.cancel()
        clearASRDownloadUI()
    }

    /// Clear the Speech pane's downloading/fraction/preparing flags together,
    /// returning the row to its pre-download look.
    private func clearASRDownloadUI() {
        model.asrDownloading = nil
        model.asrDownloadFraction = nil
        model.asrPreparing = false
    }

    /// Build the entry's engine and load — downloading on first use — its
    /// weights, reporting a 0…1 fraction through `onProgress` (Whisper only; #93)
    /// and the trailing compile-onto-the-ANE phase through `onLoading`, returning
    /// a failure string or nil. The throwaway engine is released when this
    /// returns, so selecting the model later reloads it from the on-disk cache
    /// without ever holding two Whisper models resident.
    private static func prepareASR(
        _ entry: ASRModelCatalog.Entry,
        onProgress: @escaping (Double) -> Void,
        onLoading: @escaping (Bool) -> Void
    ) async -> String? {
        let engine = TranscriberDispatcher.buildEngine(entry.engine)
        engine.onDownloadProgress = onProgress
        engine.onLoading = onLoading
        do {
            try await engine.prepare()
            return nil
        } catch {
            return "\(error)"
        }
    }

    /// Delete a downloaded model's on-disk weights (#95). Single-flight and
    /// blocked while a download runs, so the app is only ever in one
    /// ASR-mutating state at a time; the built-in default (Parakeet v3) is never
    /// deletable — it re-downloads at launch and is the fallback. Deleting the
    /// active model re-selects the default via `commit`, which fires the
    /// dispatcher's drop-before-load swap so dictation falls back to Parakeet.
    private func deleteASRModel(_ id: String) {
        guard model.asrDeleting == nil, model.asrDownloading == nil,
              id != ASRModelCatalog.defaultID,
              let entry = ASRModelCatalog.entry(for: id) else { return }
        model.asrDeleting = id
        model.asrDeleteError = ""
        Task { @MainActor in
            let failure = await Task.detached { ASRModelStore.delete(entry.engine) }.value
            self.model.asrDeleting = nil
            if let failure {
                self.model.asrDeleteError = "Couldn't delete \(entry.name): \(failure)"
                return
            }
            self.model.asrDownloaded.remove(id)
            if ASRModelCatalog.deleteOutcome(for: entry, isActive: self.model.asrModel == id)
                .fallsBackToDefault {
                self.model.asrModel = ASRModelCatalog.defaultID
                self.workflow.commit()
            }
        }
    }

    // MARK: - history row actions

    /// Prepend a just-appended dictation while the pane is open (PRD #78). A
    /// full reload (`populate`, flag/delete/re-run) replaces the whole list, so
    /// this guards by id to stay idempotent if a reload and this callback race.
    private func prependHistory(_ entry: HistoryEntry) {
        guard !model.historyEntries.contains(where: { $0.id == entry.id }) else { return }
        model.historyEntries.insert(entry, at: 0)
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Toggle the row's local bookmark and persist it. Purely local — no
    /// network activity — then re-read so the pane reflects what persisted.
    private func flagHistory(_ entry: HistoryEntry) {
        var toggled = entry
        toggled.flagged.toggle()
        historyStore.update(toggled)
        model.historyEntries = historyStore.load()
    }

    /// Re-run Polish on a stored dictation under the Mode the user picked, then
    /// re-read so the row shows the reshaped text. The reprocessor works on the
    /// entry's stored `rawText` — no audio — and overwrites text/isPolished/
    /// modeName, persisting the change before we reload.
    private func rerunPolish(_ entry: HistoryEntry, modeName: String) {
        guard let mode = config.modes[modeName] else { return }
        Task { @MainActor in
            await self.reprocessor.rerunPolish(entry, mode: mode)
            self.model.historyEntries = self.historyStore.load()
        }
    }

    /// Delete and clear-all go through the store, then re-read it so the pane's
    /// list reflects what actually persisted.
    private func deleteHistory(_ entry: HistoryEntry) {
        historyStore.delete(id: entry.id)
        model.historyEntries = historyStore.load()
    }

    /// The single clear funnel behind both "Clear all history" and the
    /// delete-on-turn-off prompt (PRD #97): a deliberate wipe resets the streak
    /// too, so a bragging count can't outlive the data it counted. The retention
    /// sweep and per-row delete deliberately do NOT reset it — that preserves the
    /// one distinction that matters: a rolling window (streak survives) versus
    /// erasing your data (streak goes too).
    private func clearHistory() {
        historyStore.clearAll()
        statsStore.reset()
        model.historyEntries = historyStore.load()
        refreshStreak()
    }

    /// Re-read the streak from the store through the pure display rule, so the
    /// pane shows the current run (or "No active streak" when it has lapsed or
    /// never started) as of now.
    private func refreshStreak() {
        model.currentStreak = StreakRules.display(statsStore.load(), now: Date(), calendar: .current)
    }

    // MARK: - key recording

    private func startRecording(_ field: SettingsModel.RecordingField) {
        stopKeyMonitor()
        workflow.beginRecording(field)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            var name: String?
            if event.type == .flagsChanged {
                // Capture modifiers on press only (flag bit present).
                let keycode = CGKeyCode(event.keyCode)
                let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
                guard KeyMap.isModifierDown(keycode: keycode, flags: flags) == true else {
                    return nil
                }
                name = KeyMap.codeToName[keycode]
            } else {
                name = KeyMap.codeToName[CGKeyCode(event.keyCode)]
                    ?? event.charactersIgnoringModifiers?.lowercased()
            }
            workflow.finishRecording(with: name)
            stopKeyMonitor()
            return nil // swallow the keystroke
        }
    }

    private func stopKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func scheduleStatusClear(_ clear: (@MainActor () -> Void)?) {
        statusClearTask?.cancel()
        guard let clear else { return }
        statusClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            clear()
        }
    }
}
