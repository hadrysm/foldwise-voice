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
    private let inputDevices: (any AudioInputStateProviding)?
    let model = SettingsModel()
    private lazy var workflow = SettingsWorkflow(
        config: config,
        model: model,
        historyStore: historyStore,
        persist: { [config] in try config.saveAndNotify() },
        now: Date.init,
        scheduleStatusClear: { [weak self] clear in self?.scheduleStatusClear(clear) },
        copy: Self.copyToPasteboard,
        statsStore: statsStore,
        reportUpdate: { [weak self] version in self?.onUpdateAvailable?(version) }
    )
    private var window: NSWindow?
    private var keyMonitor: Any?
    private var statusClearTask: Task<Void, Never>?
    private var closeObserver: NSObjectProtocol?

    /// Wired by AppDelegate so a manual check here also lights up the
    /// menu-bar "Update Available" item.
    var onUpdateAvailable: ((String) -> Void)?

    init(
        config: Config, historyStore: HistoryStore, statsStore: StatsStore,
        inputDevices: (any AudioInputStateProviding)? = nil
    ) {
        self.config = config
        self.historyStore = historyStore
        self.statsStore = statsStore
        self.inputDevices = inputDevices
        if let inputDevices {
            model.inputState = inputDevices.inputState
            inputDevices.onInputStateChange = { [weak self] state in
                Task { @MainActor in self?.model.inputState = state }
            }
        }
        wire()
        workflow.observeHistoryAppends()
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
        model.onSelectInputDevice = { [weak self] uid in
            self?.workflow.selectInputDevice(uid)
        }
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
        model.onCheckUpdates = { [weak self] in self?.workflow.checkForUpdates() }
        model.onCopyHistory = { [weak self] entry in self?.workflow.copyHistory(entry) }
        model.onCopyRawHistory = { [weak self] entry in self?.workflow.copyRawHistory(entry) }
        model.onFlagHistory = { [weak self] entry in self?.workflow.flagHistory(entry) }
        model.onRerunPolish = { [weak self] entry, modeName in
            Task { @MainActor in
                await self?.workflow.rerunPolish(entry, modeName: modeName)
            }
        }
        model.onDeleteHistory = { [weak self] entry in self?.workflow.deleteHistory(entry) }
        model.onClearHistory = { [weak self] in self?.workflow.clearHistory() }
    }

    private func build() {
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        let win = Self.makeMainWindow(contentViewController: hosting)
        win.center()
        win.setFrameAutosaveName("FoldWiseMainWindow")
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: win, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stopKeyMonitor()
                // Back to menu-bar-only once settings closes.
                NSApp.setActivationPolicy(.accessory)
            }
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
        if let inputDevices { model.inputState = inputDevices.inputState }
        model.axTrusted = TextInserter.accessibilityTrusted()
        workflow.populateHistory()
        workflow.refreshLLMModels()
        workflow.checkForUpdates()
    }

    private static func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
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
