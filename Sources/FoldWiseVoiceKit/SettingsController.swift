// Owns the settings NSWindow and mediates between SettingsModel (UI state)
// and Config/OllamaClient/UpdateChecker. Every change commits straight to
// modes.json; there is no Save button.

import AppKit
import SwiftUI

@MainActor
final class SettingsController {
    private let config: Config
    private let historyStore: HistoryStore
    private let model = SettingsModel()
    private var window: NSWindow?
    private var keyMonitor: Any?
    private var statusClearTask: Task<Void, Never>?
    private var closeObserver: NSObjectProtocol?

    /// Wired by AppDelegate so a manual check here also lights up the
    /// menu-bar "Update Available" item.
    var onUpdateAvailable: ((String) -> Void)?

    init(config: Config, historyStore: HistoryStore) {
        self.config = config
        self.historyStore = historyStore
        wire()
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
        model.onCommit = { [weak self] in self?.commit() }
        model.onRecord = { [weak self] field in self?.startRecording(field) }
        model.onSelectModel = { [weak self] name in self?.selectModel(name) }
        model.onInstallModel = { [weak self] name in self?.installModel(name) }
        model.onDeleteModel = { [weak self] name in self?.deleteModel(name) }
        model.onRefreshModels = { [weak self] in self?.refreshModels() }
        model.onEditFile = { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.open(config.path)
        }
        model.onCheckUpdates = { [weak self] in self?.checkForUpdates() }
        model.onCopyHistory = { [weak self] entry in self?.copyToPasteboard(entry.text) }
        model.onDeleteHistory = { [weak self] entry in self?.deleteHistory(entry) }
        model.onClearHistory = { [weak self] in self?.clearHistory() }
    }

    private func build() {
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        let win = NSWindow(contentViewController: hosting)
        win.title = "FoldWise Voice Settings"
        win.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.center()
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: win, queue: .main
        ) { _ in
            // Back to menu-bar-only once settings closes.
            Task { @MainActor in NSApp.setActivationPolicy(.accessory) }
        }
        window = win
    }

    private func populate() {
        model.modeNames = config.modeOrder
        model.llmModes = Set(config.modeOrder.filter { config.modes[$0]?.usesLLM == true })
        model.activeMode = config.activeMode
        model.selectedModel = config.llmModel ?? ""
        model.pttKey = config.hotkey
        model.toggleKey = config.toggleHotkey ?? ""
        model.pauseAudio = config.pauseAudio
        model.saveHistory = config.saveHistory
        model.hudStyle = (HUDStyle(rawValue: config.hudStyle) ?? .classic).rawValue
        model.axTrusted = TextInserter.accessibilityTrusted()
        model.historyEntries = historyStore.load()
        model.status = ""
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
        commit()
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
                self.commit()
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

    // MARK: - history row actions

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Delete and clear-all go through the store, then re-read it so the pane's
    /// list reflects what actually persisted.
    private func deleteHistory(_ entry: HistoryEntry) {
        historyStore.delete(id: entry.id)
        model.historyEntries = historyStore.load()
    }

    private func clearHistory() {
        historyStore.clearAll()
        model.historyEntries = historyStore.load()
    }

    // MARK: - key recording

    private func startRecording(_ field: SettingsModel.RecordingField) {
        stopRecording()
        model.recordingField = field
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
            if let name, !name.isEmpty {
                switch field {
                case .ptt: model.pttKey = name
                case .toggle: model.toggleKey = name
                }
                commit()
            }
            stopRecording()
            return nil // swallow the keystroke
        }
    }

    private func stopRecording() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        model.recordingField = nil
    }

    // MARK: - save (called on every change — there is no Save button)

    private func commit() {
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
        config.setActiveMode(model.activeMode)
        config.hotkey = ptt
        config.toggleHotkey = toggle.isEmpty ? nil : toggle
        config.pauseAudio = model.pauseAudio
        config.saveHistory = model.saveHistory
        config.hudStyle = model.hudStyle
        do {
            try config.saveAndNotify()
        } catch {
            setStatus("⚠️ save failed: \(error.localizedDescription)", isError: true)
            return
        }
        setStatus("Saved ✓", isError: false, clearAfter: 2)
    }

    private func setStatus(_ text: String, isError: Bool, clearAfter seconds: Double? = nil) {
        statusClearTask?.cancel()
        model.status = text
        model.statusIsError = isError
        guard let seconds else { return }
        statusClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.model.status = ""
        }
    }
}
