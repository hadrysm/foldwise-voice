// FoldWise Voice — native Swift implementation.
// Menu-bar dictation app: hold a hotkey, speak, release; Parakeet (Neural
// Engine) transcribes on-device, Ollama optionally polishes, and the text is
// pasted into the focused app.

import AppKit
import Carbon
import Darwin
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
    #if FOLDWISE_UPDATE_ACCEPTANCE
        private var updateRuntimeAcceptance: UpdateRuntimeAcceptanceController?
    #endif

    init(configPath: String?, showSettingsOnLaunch: Bool) {
        self.configPath = configPath
        self.showSettingsOnLaunch = showSettingsOnLaunch
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if FOLDWISE_UPDATE_ACCEPTANCE
            if let updateRuntimeAcceptance = UpdateRuntimeAcceptanceController() {
                self.updateRuntimeAcceptance = updateRuntimeAcceptance
                updateRuntimeAcceptance.start()
                return
            }
        #endif

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
        pipeline.onSessionEvent = ApplicationRunLoop.handler { [weak self] event in
            self?.lifecycleCoordinator?.sessionDidChange(event)
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
        #if FOLDWISE_UPDATE_ACCEPTANCE
            if let updateRuntimeAcceptance {
                return updateRuntimeAcceptance.applicationShouldTerminate(sender)
            }
        #endif
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
        #if FOLDWISE_UPDATE_ACCEPTANCE
            if let updateRuntimeAcceptance {
                return updateRuntimeAcceptance.shouldPostponeRelaunch(
                    untilInvoking: installHandler
                )
            }
        #endif
        return lifecycleCoordinator?.shouldPostponeRelaunch(
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

#if FOLDWISE_UPDATE_ACCEPTANCE
    @MainActor
    final class UpdateRuntimeAcceptanceController: NSObject, SPUUpdaterDelegate {
        private enum Role: String {
            case source
            case target
        }

        private final class AcceptanceGlobalHotkeyListener: HotkeyListening {
            var onHealthChange: ((ShortcutListenerHealth) -> Void)?
            private var hotkey: EventHotKeyRef?

            func start() throws {
                let identifier = EventHotKeyID(signature: 0x4657_5541, id: 1)
                let status = RegisterEventHotKey(
                    UInt32(kVK_F19),
                    UInt32(controlKey | optionKey),
                    identifier,
                    GetApplicationEventTarget(),
                    0,
                    &hotkey
                )
                guard status == noErr, hotkey != nil else {
                    throw AcceptanceError.contract(
                        "global hotkey registration failed with OSStatus \(status)"
                    )
                }
                onHealthChange?(.global)
            }

            func stop() {
                guard let hotkey else { return }
                let status = UnregisterEventHotKey(hotkey)
                if status != noErr {
                    Log.hotkey.error(
                        "Acceptance hotkey cleanup failed with OSStatus \(status)"
                    )
                }
                self.hotkey = nil
            }
        }

        private final class AcceptanceRecorder: AudioRecording {
            var onFailure: ((AudioCaptureError) -> Void)?

            func start() throws {}

            func stop() -> [Float] {
                [Float](
                    repeating: 0.1,
                    count: Int(AudioRecorder.sampleRate)
                )
            }

            func close() {}
        }

        private final class AcceptanceASRSessionProvider: ASRSessionHandleProviding {
            var isDictationBlocked: Bool {
                false
            }

            func captureSession() throws -> any ASRSessionHandle {
                AcceptanceASRSession()
            }
        }

        private final class AcceptanceASRSession: ASRSessionHandle {
            func transcribe(_: [Float]) async throws -> String {
                "FoldWise runtime acceptance transcript"
            }

            func release() {}
        }

        private final class AcceptanceAudioDucker: AudioDucking {
            func duck() {}
            func restore() {}
        }

        private let directory: URL
        private let role: Role
        private let version: String
        private let config: Config
        private let insertionGate = UpdateRuntimeAcceptanceInsertionGate()
        private var badge: BadgeController?
        private var hotkeys: HotkeyBindingCoordinator?
        private var pipeline: Pipeline?
        private var hotkeyHealth: ShortcutListenerHealth?
        private var updaterController: SPUStandardUpdaterController?
        private var signalMonitor: UpdateRuntimeAcceptanceSignalMonitor?
        private var didRequestTermination = false
        private var didRecordTerminationDeferral = false
        private lazy var lifecycleCoordinator = DictationLifecycleCoordinator { [weak self] in
            self?.tearDown()
        }

        init?(environment: [String: String] = ProcessInfo.processInfo.environment) {
            guard let directoryPath = environment["FOLDWISE_UPDATE_ACCEPTANCE_DIRECTORY"],
                  let roleValue = Bundle.main.object(
                      forInfoDictionaryKey: "FoldWiseUpdateAcceptanceRole"
                  ) as? String,
                  let role = Role(rawValue: roleValue),
                  let version = Bundle.main.object(
                      forInfoDictionaryKey: "CFBundleVersion"
                  ) as? String
            else {
                return nil
            }

            directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
            self.role = role
            self.version = version
            config = Config.defaultConfig(
                path: directory.appendingPathComponent("config.json")
            )
        }

        func start() {
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                try watchForHarnessSignals()
                if role == .target {
                    try record(
                        "target-started",
                        details: ["bundlePath": Bundle.main.bundleURL.path]
                    )
                }
                try startLaunchServices()
                switch role {
                case .source:
                    try startSourceUpdate()
                case .target:
                    try record(
                        "target-ready",
                        details: readinessDetails()
                    )
                }
            } catch {
                fail("acceptance startup failed: \(error.localizedDescription)")
            }
        }

        func applicationShouldTerminate(
            _ sender: NSApplication
        ) -> NSApplication.TerminateReply {
            let decision = lifecycleCoordinator.applicationShouldTerminate {
                sender.reply(toApplicationShouldTerminate: true)
            }
            switch decision {
            case .terminateNow:
                return .terminateNow
            case .terminateLater:
                if !didRecordTerminationDeferral {
                    didRecordTerminationDeferral = true
                    do {
                        try record("termination-deferred")
                    } catch {
                        fail("could not record deferred termination: \(error.localizedDescription)")
                    }
                }
                return .terminateLater
            }
        }

        func shouldPostponeRelaunch(
            untilInvoking installHandler: @escaping () -> Void
        ) -> Bool {
            lifecycleCoordinator.shouldPostponeRelaunch(untilInvoking: installHandler)
        }

        func updater(
            _ updater: SPUUpdater,
            willInstallUpdateOnQuit item: SUAppcastItem,
            immediateInstallationBlock: @escaping () -> Void
        ) -> Bool {
            guard !didRequestTermination else { return false }
            didRequestTermination = true
            do {
                try record(
                    "update-prepared",
                    details: ["targetVersion": item.versionString]
                )
            } catch {
                fail("could not record prepared update: \(error.localizedDescription)")
                return false
            }
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
            return false
        }

        func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
            fail("Sparkle aborted: \(error.localizedDescription)")
        }

        private func startLaunchServices() throws {
            let badge = BadgeController(config: config) {}
            let hotkeys = HotkeyBindingCoordinator(
                config: config,
                callbacks: HotkeyCallbacks(
                    isSuspended: { false },
                    onPress: {},
                    onRelease: {},
                    onToggle: {},
                    onCycle: {},
                    onHealthChange: { [weak self] health in
                        self?.hotkeyHealth = health
                    }
                ),
                prepare: { _, callbacks in
                    let listener = AcceptanceGlobalHotkeyListener()
                    listener.onHealthChange = callbacks.onHealthChange
                    return listener
                }
            )
            try hotkeys.start()
            badge.show()
            self.hotkeys = hotkeys
            self.badge = badge

            guard hotkeyHealth == .global else {
                throw AcceptanceError.contract("global hotkey registration did not succeed")
            }
            guard isBadgeVisible else {
                throw AcceptanceError.contract("Badge did not become visible")
            }
        }

        private func startSourceUpdate() throws {
            try record("source-ready", details: readinessDetails())
            // Keep this as an actor method reference. An inline async closure
            // created by this @MainActor controller cannot return while AppKit
            // is waiting in its deferred-termination run-loop mode.
            let pipeline = Pipeline(
                config: config,
                recorder: AcceptanceRecorder(),
                sessionProvider: AcceptanceASRSessionProvider(),
                ducker: AcceptanceAudioDucker(),
                insert: insertionGate.insert,
                record: { _ in },
                frontmostApp: { nil }
            )
            pipeline.onSessionEvent = ApplicationRunLoop.handler { [weak self] event in
                self?.receiveSessionEvent(event)
            }
            self.pipeline = pipeline
            pipeline.startRecording()
            pipeline.stopRecording()
        }

        private func startUpdater() {
            guard updaterController == nil else { return }
            let updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: self,
                userDriverDelegate: nil
            )
            self.updaterController = updaterController
            updaterController.updater.automaticallyChecksForUpdates = true
            updaterController.updater.automaticallyDownloadsUpdates = true
            DispatchQueue.main.async {
                updaterController.updater.checkForUpdatesInBackground()
            }
        }

        private func watchForHarnessSignals() throws {
            let signalName = role == .source ? "finish-dictation" : "terminate-target"
            let role = role
            let insertionGate = insertionGate
            let monitor = UpdateRuntimeAcceptanceSignalMonitor(
                directory: directory,
                signalName: signalName
            ) {
                switch role {
                case .source:
                    Task { await insertionGate.open() }
                case .target:
                    DispatchQueue.main.async {
                        NSApp.terminate(nil)
                    }
                }
            }
            monitor.start()
            signalMonitor = monitor
        }

        private func receiveSessionEvent(_ event: DictationSessionEvent) {
            do {
                switch event {
                case .started:
                    try record("dictation-started")
                    lifecycleCoordinator.sessionDidChange(event)
                    startUpdater()
                case .finished:
                    try record(
                        "dictation-finished",
                        details: [
                            "installedVersionAtCompletion": try installedBundleVersion(),
                        ]
                    )
                    lifecycleCoordinator.sessionDidChange(event)
                }
            } catch {
                fail("could not record Dictation lifecycle: \(error.localizedDescription)")
            }
        }

        private var isBadgeVisible: Bool {
            NSApp.windows.contains { window in
                window is BadgePanel && window.isVisible
            }
        }

        private func installedBundleVersion() throws -> String {
            let infoURL = Bundle.main.bundleURL.appendingPathComponent(
                "Contents/Info.plist"
            )
            let data = try Data(contentsOf: infoURL)
            guard let info = try PropertyListSerialization.propertyList(
                from: data,
                format: nil
            ) as? [String: Any],
                let version = info["CFBundleVersion"] as? String
            else {
                throw AcceptanceError.contract(
                    "installed bundle version could not be read at Dictation completion"
                )
            }
            return version
        }

        private func readinessDetails() -> [String: Any] {
            [
                "bundlePath": Bundle.main.bundleURL.path,
                "badgeVisible": isBadgeVisible,
                "hotkeyHealth": hotkeyHealth == .global ? "global" : "unavailable",
            ]
        }

        private func tearDown() {
            hotkeys?.stop()
            pipeline?.shutdown()
            badge?.hide()
            signalMonitor?.stop()
            signalMonitor = nil
        }

        private func record(
            _ event: String,
            details: [String: Any] = [:]
        ) throws {
            var payload = details
            payload["event"] = event
            payload["version"] = version
            payload["pid"] = ProcessInfo.processInfo.processIdentifier
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            let eventURL = directory.appendingPathComponent("events.jsonl")
            if !FileManager.default.fileExists(atPath: eventURL.path) {
                FileManager.default.createFile(atPath: eventURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: eventURL)
            defer {
                do {
                    try handle.close()
                } catch {
                    Log.app.error(
                        "Acceptance event log close failed: \(error.localizedDescription)"
                    )
                }
            }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data("\n".utf8))
            try handle.synchronize()
        }

        private func fail(_ message: String) {
            let payload: [String: Any] = [
                "bundlePath": Bundle.main.bundleURL.path,
                "message": message,
                "pid": ProcessInfo.processInfo.processIdentifier,
                "role": role.rawValue,
                "version": version,
            ]
            do {
                let data = try JSONSerialization.data(
                    withJSONObject: payload,
                    options: [.prettyPrinted, .sortedKeys]
                )
                try data.write(
                    to: directory.appendingPathComponent("application-failure.json"),
                    options: .atomic
                )
            } catch {
                Log.app.error(
                    "Could not preserve acceptance failure: \(error.localizedDescription)"
                )
            }
            pipeline?.shutdown()
            NSApp.terminate(nil)
        }

        private enum AcceptanceError: LocalizedError {
            case contract(String)

            var errorDescription: String? {
                switch self {
                case let .contract(message):
                    message
                }
            }
        }
    }
#endif

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
