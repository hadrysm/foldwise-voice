// Owns the settings NSWindow and mediates between SettingsModel (UI state)
// and Config/OllamaClient/UpdateChecker. Preferences commit immediately;
// Mode drafts commit only through the editor's Save action.

import AppKit
import SwiftUI

@MainActor
final class SettingsController {
    private let config: Config
    private let historyStore: HistoryStore
    private let statsStore: StatsStore
    private let inputDevices: (any AudioInputStateProviding)?
    private let hotkeys: HotkeyBindingCoordinator?
    private let captureGate: ShortcutCaptureGate
    let model = SettingsModel()
    private lazy var workflow = SettingsWorkflow(
        config: config,
        model: model,
        historyStore: historyStore,
        now: Date.init,
        scheduleStatusClear: { [weak self] clear in self?.scheduleStatusClear(clear) },
        copy: Self.copyToPasteboard,
        statsStore: statsStore,
        reportUpdate: { [weak self] version in self?.onUpdateAvailable?(version) },
        updateHotkeys: { [weak self] bindings in
            if let hotkeys = self?.hotkeys {
                try hotkeys.update(bindings)
            } else {
                try self?.config.setShortcutBindings(bindings)
            }
        },
        captureGate: captureGate
    )
    private var window: NSWindow?
    private var keyMonitor: Any?
    private var statusClearTask: Task<Void, Never>?
    private var closeObserver: NSObjectProtocol?
    private var resignObserver: NSObjectProtocol?

    /// Wired by AppDelegate so a manual check here also lights up the
    /// menu-bar "Update Available" item.
    var onUpdateAvailable: ((String) -> Void)?

    init(
        config: Config, historyStore: HistoryStore, statsStore: StatsStore,
        inputDevices: (any AudioInputStateProviding)? = nil,
        hotkeys: HotkeyBindingCoordinator? = nil,
        captureGate: ShortcutCaptureGate = ShortcutCaptureGate()
    ) {
        self.config = config
        self.historyStore = historyStore
        self.statsStore = statsStore
        self.inputDevices = inputDevices
        self.hotkeys = hotkeys
        self.captureGate = captureGate
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
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
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
        model.onCancelRecording = { [weak self] in self?.cancelRecording() }
        model.onOpenShortcutPermissions = { Self.openShortcutPermissions() }
        model.onSelectMode = { [weak self] selection in self?.workflow.selectMode(selection) }
        model.onAddMode = { [weak self] in self?.workflow.beginAddMode() }
        model.onEditMode = { [weak self] id in self?.workflow.beginEditMode(id) }
        model.onDuplicateMode = { [weak self] id in self?.workflow.beginDuplicateMode(id) }
        model.onMoveMode = { [weak self] id, direction in
            self?.workflow.moveMode(id, direction: direction)
        }
        model.onRequestModeDeletion = { [weak self] id in
            self?.workflow.requestModeDeletion(id)
        }
        model.onConfirmModeDeletion = { [weak self] in self?.workflow.confirmModeDeletion() }
        model.onCancelModeDeletion = { [weak self] in self?.workflow.cancelModeDeletion() }
        model.onSaveModeEditor = { [weak self] in self?.workflow.saveModeEditor() }
        model.onCancelModeEditor = { [weak self] in self?.workflow.cancelModeEditor() }
        model.onInstallModel = { [weak self] name in self?.workflow.installLLMModel(name) }
        model.onDeleteModel = { [weak self] name in self?.workflow.deleteLLMModel(name) }
        model.onRefreshModels = { [weak self] in self?.workflow.refreshLLMModels() }
        model.onSelectASRModel = { [weak self] id in self?.workflow.selectASRModel(id) }
        model.onDownloadASRModel = { [weak self] id in self?.workflow.downloadASRModel(id) }
        model.onCancelASRDownload = { [weak self] in self?.workflow.cancelASRDownload() }
        model.onDeleteASRModel = { [weak self] id in self?.workflow.deleteASRModel(id) }
        model.onCheckUpdates = { [weak self] in self?.workflow.checkForUpdates() }
        model.onHistoryCommand = { [weak self] entry, command in
            self?.workflow.performHistoryCommand(command, for: entry)
        }
        model.onClearHistory = { [weak self] in self?.workflow.clearHistory() }
        model.onResetConfiguration = { [weak self] in self?.resetConfiguration() }
        model.onQuitRecovery = { NSApp.terminate(nil) }
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
                self?.cancelRecording()
                // Back to menu-bar-only once settings closes.
                NSApp.setActivationPolicy(.accessory)
            }
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: win, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelRecording() }
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

    private func resetConfiguration() {
        do {
            let backup = try config.resetRecovery()
            populate()
            model.status = "Reset complete. Backup: \(backup.lastPathComponent)"
            model.statusIsError = false
        } catch {
            model.status = "Reset failed: \(error.localizedDescription)"
            model.statusIsError = true
        }
    }

    private static func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - key recording

    private func startRecording(_ field: SettingsModel.RecordingField) {
        if model.recordingField == field {
            cancelRecording()
            return
        }
        stopKeyMonitor()
        workflow.beginRecording(field)
        keyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged, .leftMouseUp, .rightMouseUp]
        ) { [weak self] event in
            guard let self else { return event }
            if event.type == .leftMouseUp || event.type == .rightMouseUp {
                // A SwiftUI Button handles this same mouse-up before the queued
                // task runs. The active chip therefore observes and cancels its
                // own capture, while every other completed click cancels after
                // its action without timing thresholds.
                Task { @MainActor [weak self] in self?.cancelRecording() }
                return event
            }
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

    private func cancelRecording() {
        stopKeyMonitor()
        workflow.cancelRecording()
    }

    private static func openShortcutPermissions() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ) else {
            Log.hotkey.error("Could not construct the shortcut permission settings URL")
            return
        }
        NSWorkspace.shared.open(url)
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
