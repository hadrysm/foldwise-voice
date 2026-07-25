// FoldWise Voice — native Swift implementation.
// Menu-bar dictation app: hold a hotkey, speak, release; Parakeet (Neural
// Engine) transcribes on-device, Ollama optionally polishes, and the text is
// pasted into the focused app.

import AppKit
import Foundation
import os
import Sparkle

final class LiveLLMModelManager: LLMModelManaging {
    func list() async -> [OllamaClient.InstalledModel] {
        await OllamaClient.listModels()
    }

    func pull(_ name: String, progress: @escaping LLMProgress) async -> String? {
        await OllamaClient.pull(model: name) { status, fraction in
            Task { @MainActor in progress(status, fraction) }
        }
    }

    func delete(_ name: String) async -> String? {
        await OllamaClient.delete(model: name)
    }
}

/// TCP port used as a single-instance mutex (shared with the Python app so
/// only one dictation app runs at a time).
private let lockPort: UInt16 = 47812

private func acquireInstanceLock(port: UInt16) -> Bool {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return true } // can't check — proceed
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
    let bound = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    if bound != 0 {
        close(fd)
        return false
    }
    return true // fd stays open (and the port bound) for the app's lifetime
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    let configPath: String?
    let showSettingsOnLaunch: Bool

    // Standard AppKit delayed-init: these exist for the app's whole life but
    // can only be built in applicationDidFinishLaunching. Optionals would
    // force unwrapping at every use for no real safety gain.
    // swiftlint:disable implicitly_unwrapped_optional
    private var config: Config!
    private var appearanceReactor: AppearanceReactor!
    private var pipeline: Pipeline!
    private var badge: BadgeController!
    private var settings: SettingsController!
    private var menuBar: MenuBarController!
    private var hotkeys: HotkeyBindingCoordinator!
    private var dictationCommands: DictationCommandQueue!
    private var modeCycleCommand: ModeCycleCommand!
    private let asrBadgePresentation = ASRBadgePresentation()
    private let shortcutCaptureGate = ShortcutCaptureGate()
    // swiftlint:enable implicitly_unwrapped_optional
    private var lifecycleCoordinator: DictationLifecycleCoordinator?
    private var updaterController: SPUStandardUpdaterController?
    private var updaterAvailabilityObservation: NSKeyValueObservation?

    init(configPath: String?, showSettingsOnLaunch: Bool) {
        self.configPath = configPath
        self.showSettingsOnLaunch = showSettingsOnLaunch
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let acquiredInstanceLock = acquireInstanceLock(port: lockPort)
        let url = Config.resolvePath(cliPath: configPath)
        config = Config.loadOrCreate(at: url)
        appearanceReactor = AppearanceReactor(config: config)

        guard acquiredInstanceLock else {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "FoldWise Voice is already running"
            alert.informativeText =
                "Look for the mic icon in the menu bar — on notched MacBooks it "
                    + "can be hidden if the bar is full (⌘-drag other icons to make room)."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        // Only visible while the settings window has promoted the app to
        // .regular, but needed then so Edit shortcuts work in text fields.
        NSApp.mainMenu = buildMainMenu()

        // Composition root: the one recorder is shared between the Pipeline
        // and the Badge's level meter, and lifecycle startup is triggered here
        // (below), not inside Pipeline.
        let recorder = AudioRecorder(config: config, hardware: CoreAudioHardware())
        let asrLifecycle = ASRModelLifecycle(
            storedSelection: config.asrModel,
            adapters: [ParakeetASRModelAdapter(), WhisperASRModelAdapter()],
            persistSelection: { [config] id in try config.setASRModel(id) }
        )
        // One store shared between the record seam and the History pane, so a
        // dictation just spoken is on disk for the pane to load (PRD #78).
        let historyStore = JSONLHistoryStore(url: JSONLHistoryStore.defaultURL)
        // A single best-effort retention sweep at launch drops entries past the
        // configured window (Forever leaves everything, PRD #78).
        historyStore.sweep(retention: config.historyRetention, now: Date())
        // The one persisted stats fact: a true lifetime streak (PRD #97). It
        // advances off the history store's existing append seam (ADR-0003), wired
        // here app-lifetime before the hotkey listener starts so no append can
        // race registration. Registered before the SettingsController's own
        // onAppend observer so the streak is advanced before that observer
        // re-reads it. Because a session only appends while "Save dictation
        // history" is on, the streak freezes with saving off for free — no
        // separate gate. Best-effort like the history store, so a stats write can
        // never break a dictation session.
        let statsStore = JSONStatsStore(url: JSONStatsStore.defaultURL)
        historyStore.onAppend { entry in
            statsStore.advance(on: entry.createdAt, calendar: .current)
        }
        pipeline = Pipeline(
            config: config, recorder: recorder, sessionProvider: asrLifecycle,
            record: { historyStore.append($0) }
        )
        dictationCommands = DictationCommandQueue(
            start: { [weak self] in self?.pipeline.startRecording() },
            stop: { [weak self] in self?.pipeline.stopRecording() },
            toggle: { [weak self] in self?.pipeline.toggleRecording() }
        )
        badge = BadgeController(config: config) { [weak self] in
            self?.settings.show()
        }
        badge.recorder = recorder
        badge.onStop = { [weak self] in self?.dictationCommands.stop() }
        badge.onRecord = { [weak self] in self?.dictationCommands.toggle() }
        modeCycleCommand = ModeCycleCommand(
            config: config,
            onCommitted: { [weak self] transition in
                self?.badge.confirmModeCycle(transition)
            },
            onFailure: { [weak self] error in
                Log.hotkey.error(
                    "Mode cycle failed: \(error.localizedDescription, privacy: .public)"
                )
                self?.badge.showModeCycleError()
            }
        )
        hotkeys = HotkeyBindingCoordinator(
            config: config,
            callbacks: HotkeyCallbacks(
                isSuspended: { [weak self] in
                    self?.shortcutCaptureGate.isCapturing ?? false
                },
                onPress: { [weak self] in self?.dictationCommands.start() },
                onRelease: { [weak self] in self?.dictationCommands.stop() },
                onToggle: { [weak self] in self?.dictationCommands.toggle() },
                onCycle: { [weak self] in self?.modeCycleCommand.perform() },
                onHealthChange: { [weak self] health in
                    self?.settings?.model.shortcutListenerHealth = health
                }
            ),
            prepare: { bindings, callbacks in
                let listener = try HotkeyListener(
                    pttKey: bindings.pushToTalk,
                    toggleKey: bindings.toggleRecording,
                    cycleKey: bindings.modeCycle,
                    isSuspended: callbacks.isSuspended,
                    onPress: callbacks.onPress,
                    onRelease: callbacks.onRelease,
                    onToggle: callbacks.onToggle,
                    onCycle: callbacks.onCycle
                )
                listener.onHealthChange = callbacks.onHealthChange
                return listener
            }
        )
        settings = SettingsController(
            config: config, historyStore: historyStore, statsStore: statsStore,
            inputDevices: recorder, hotkeys: hotkeys, captureGate: shortcutCaptureGate,
            asrLifecycle: asrLifecycle
        )
        lifecycleCoordinator = DictationLifecycleCoordinator { [weak self] in
            self?.tearDownForTermination()
        }
        if Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: self,
                userDriverDelegate: nil
            )
        }
        let canCheckForUpdates = updaterController?.updater.canCheckForUpdates ?? false
        let checkForUpdates: () -> Void = { [weak self] in
            self?.updaterController?.checkForUpdates(nil)
        }
        settings.configureUpdates(
            canCheckForUpdates: canCheckForUpdates,
            checkForUpdates: checkForUpdates
        )
        menuBar = MenuBarController(
            config: config,
            onSettings: { [weak self] in self?.settings.show() },
            onCheckForUpdates: checkForUpdates,
            canCheckForUpdates: canCheckForUpdates,
            onModeSelectionError: { [weak self] in self?.badge.showModeSelectionError() },
            onQuit: { [weak self] in self?.quit() }
        )
        updaterAvailabilityObservation = updaterController?.updater.observe(
            \.canCheckForUpdates,
            options: [.new]
        ) { [weak self] updater, _ in
            Task { @MainActor [weak self] in
                self?.applyUpdaterAvailability(updater.canCheckForUpdates)
            }
        }
        pipeline.onState = { [weak self] state in
            Task { @MainActor in self?.apply(state) }
        }
        pipeline.onSessionEvent = { [weak self] event in
            Task { @MainActor in self?.lifecycleCoordinator?.sessionDidChange(event) }
        }
        Task { [weak self] in
            for await snapshot in await asrLifecycle.snapshots() {
                guard !Task.isCancelled else { return }
                self?.applyASRLifecycle(snapshot)
            }
        }

        settings.beginPermissionRecovery()

        do {
            try hotkeys.start()
        } catch {
            Log.app.error(
                "Hotkey setup failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        Task { await asrLifecycle.start() }

        // The living idle pill is the ready signal (PRD #103); the hotkey
        // hint lives on Home, rendered from the live config.
        badge.show()
        if showSettingsOnLaunch || config.isReadOnly {
            settings.show()
        }
    }

    private func applyUpdaterAvailability(_ canCheckForUpdates: Bool) {
        settings.setCanCheckForUpdates(canCheckForUpdates)
        menuBar.setCanCheckForUpdates(canCheckForUpdates)
    }

    private func apply(_ state: PipelineState) {
        // The Badge folds the phase into its own state machine (BadgeReducer);
        // only the menu-bar icon mapping lives here.
        if let badgeState = asrBadgePresentation.pipelineDidChange(state) {
            badge.apply(badgeState)
        }
        switch state {
        case .listening:
            menuBar.setIcon(.listening)
        case .downloadingModel, .loadingModel, .switchingASRModel, .transcribing, .polishing,
             .recognitionUnavailable:
            menuBar.setIcon(.working)
        case .inserted, .clipboard, .error, .idle:
            menuBar.setIcon(.idle)
        }
    }

    private func applyASRLifecycle(_ snapshot: ASRModelLifecycleSnapshot) {
        if let state = asrBadgePresentation.lifecycleDidChange(
            operation: snapshot.operation,
            isDictationBlocked: snapshot.isDictationBlocked
        ) {
            badge.apply(state)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func tearDownForTermination() {
        hotkeys.stop()
        pipeline.shutdown()
        badge.hide()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let lifecycleCoordinator else { return .terminateNow }
        let decision = lifecycleCoordinator.applicationShouldTerminate {
            sender.reply(toApplicationShouldTerminate: true)
        }
        switch decision {
        case .terminateNow:
            return .terminateNow
        case .terminateLater:
            return .terminateLater
        }
    }

    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        lifecycleCoordinator?.shouldPostponeRelaunch(
            untilInvoking: installHandler
        ) ?? false
    }

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "About FoldWise Voice",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "Quit FoldWise Voice", action: #selector(quit), keyEquivalent: "q"
        )
        quitItem.target = self
        appMenu.addItem(quitItem)
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(
            withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"
        )
        editMenu.addItem(
            withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"
        )
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"
        )
        windowMenu.addItem(
            withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        return main
    }
}

public enum FoldWiseVoiceApp {
    public static func main() {
        let action = FoldWiseVoiceCommandLine().evaluate(arguments: CommandLine.arguments)
        let cliConfig: String?
        let showSettingsOnLaunch: Bool
        switch action {
        case let .launch(configPath, showSettings):
            cliConfig = configPath
            showSettingsOnLaunch = showSettings
        case let .terminate(result):
            if let output = result.standardOutput.data(using: .utf8) {
                FileHandle.standardOutput.write(output)
            }
            if let error = result.standardError.data(using: .utf8) {
                FileHandle.standardError.write(error)
            }
            exit(result.status)
        }

        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate(
                configPath: cliConfig,
                showSettingsOnLaunch: showSettingsOnLaunch
            )
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            app.run()
        }
    }
}
