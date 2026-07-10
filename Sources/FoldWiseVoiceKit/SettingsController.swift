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
        model.onSelectModel = { [weak self] name in self?.workflow.selectLLMModel(name) }
        model.onInstallModel = { [weak self] name in self?.workflow.installLLMModel(name) }
        model.onDeleteModel = { [weak self] name in self?.workflow.deleteLLMModel(name) }
        model.onRefreshModels = { [weak self] in self?.workflow.refreshLLMModels() }
        model.onSelectASRModel = { [weak self] id in self?.workflow.selectASRModel(id) }
        model.onDownloadASRModel = { [weak self] id in self?.workflow.downloadASRModel(id) }
        model.onCancelASRDownload = { [weak self] in self?.workflow.cancelASRDownload() }
        model.onDeleteASRModel = { [weak self] id in self?.workflow.deleteASRModel(id) }
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
        workflow.refreshLLMModels()
        checkForUpdates()
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
