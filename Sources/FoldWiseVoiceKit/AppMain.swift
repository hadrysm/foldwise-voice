// FoldWise Voice — native Swift implementation.
// Menu-bar dictation app: hold a hotkey, speak, release; Parakeet (Neural
// Engine) transcribes on-device, Ollama optionally polishes, and the text is
// pasted into the focused app.

import AppKit
import Foundation
import os

extension TranscriberDispatcher {
    /// Production-only construction for the real ASR adapters. Keeping it in
    /// the composition root leaves the dispatcher's decisions testable without
    /// initializing or downloading a CoreML model.
    static func buildEngine(_ engine: ASRModelCatalog.Engine) -> Transcribing {
        switch engine {
        case let .parakeet(version): Transcriber(version: version)
        case let .whisper(variant): WhisperTranscriber(variant: variant)
        }
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
final class AppDelegate: NSObject, NSApplicationDelegate {
    let configPath: String?
    let modeOverride: String?

    // Standard AppKit delayed-init: these exist for the app's whole life but
    // can only be built in applicationDidFinishLaunching. Optionals would
    // force unwrapping at every use for no real safety gain.
    // swiftlint:disable implicitly_unwrapped_optional
    private var config: Config!
    private var pipeline: Pipeline!
    private var badge: BadgeController!
    private var settings: SettingsController!
    private var menuBar: MenuBarController!
    private var listener: HotkeyListener?
    private var updateChecker: UpdateChecker!
    // swiftlint:enable implicitly_unwrapped_optional

    init(configPath: String?, modeOverride: String?) {
        self.configPath = configPath
        self.modeOverride = modeOverride
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard acquireInstanceLock(port: lockPort) else {
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

        let url = Config.resolvePath(cliPath: configPath)
        config = Config.loadOrCreate(at: url)
        if let modeOverride { config.setActiveMode(modeOverride) }

        // Composition root: the one recorder is shared between the Pipeline
        // and the Badge's level meter, and warmup is triggered here (below),
        // not inside Pipeline.
        let recorder = AudioRecorder()
        // The dispatcher fronts the ASR engines behind the `Transcribing` seam
        // (ADR-0005): it resolves the active engine from `config.asrModel` and
        // subscribes to `.asrModel` changes itself. The Pipeline drives it as an
        // ordinary transcriber and never learns there is more than one engine.
        let transcriber = TranscriberDispatcher(config: config)
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
            config: config, recorder: recorder, transcriber: transcriber,
            record: { historyStore.append($0) }
        )
        settings = SettingsController(config: config, historyStore: historyStore, statsStore: statsStore)
        badge = BadgeController(config: config) { [weak self] in
            self?.settings.show()
        }
        badge.recorder = recorder
        badge.onStop = { [weak self] in self?.pipeline.stopRecording() }
        badge.onRecord = { [weak self] in self?.pipeline.toggleRecording() }
        menuBar = MenuBarController(
            config: config,
            onSettings: { [weak self] in self?.settings.show() },
            onCheckForUpdates: { [weak self] in self?.checkForUpdatesManually() },
            onQuit: { [weak self] in self?.quit() }
        )
        settings.onUpdateAvailable = { [weak self] version in
            self?.menuBar.showUpdateAvailable(version)
        }
        // The other config reactors subscribe in their own inits; the hotkey
        // listener has no controller object, so its subscription lives here.
        // Rebinding tears down the TCC-sensitive event tap, so it must run
        // only when a hotkey actually changed.
        config.onChange { [weak self] changes in
            if changes.contains(.hotkeys) { self?.startListener() }
        }

        pipeline.onState = { [weak self] state in
            Task { @MainActor in self?.apply(state) }
        }

        updateChecker = UpdateChecker { [weak self] version in
            self?.menuBar.showUpdateAvailable(version)
        }
        updateChecker.start()

        Permissions.requestAtLaunch()

        startListener()
        transcriber.warmup()

        // The living idle pill is the ready signal (PRD #103); the hotkey
        // hint lives on Home, rendered from the live config.
        badge.show()
    }

    private func startListener() {
        listener?.stop()
        listener = nil
        do {
            let l = try HotkeyListener(
                pttKey: config.hotkey,
                toggleKey: config.toggleHotkey,
                onPress: { [weak self] in self?.pipeline.startRecording() },
                onRelease: { [weak self] in self?.pipeline.stopRecording() },
                onToggle: { [weak self] in self?.pipeline.toggleRecording() }
            )
            l.start()
            listener = l
        } catch {
            Log.app.error(
                "Hotkey setup failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// "Check for Updates…" from the menu bar: check immediately and always
    /// report the outcome in an alert, unlike the silent passive check.
    private func checkForUpdatesManually() {
        Task { @MainActor in
            let result = await UpdateChecker.checkNow()
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            switch result {
            case let .upToDate(current):
                alert.messageText = "You're up to date"
                alert.informativeText =
                    "FoldWise Voice \(current) is the latest version."
                alert.runModal()
            case let .updateAvailable(version, downloadURL):
                menuBar.showUpdateAvailable(version)
                alert.messageText = "Update available"
                alert.informativeText =
                    "FoldWise Voice v\(version) is available — you have "
                        + "\(UpdateChecker.currentVersion() ?? "an older version"). "
                        + "The download opens in your browser; drag the new app "
                        + "into Applications to update."
                alert.addButton(withTitle: "Download")
                alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(downloadURL ?? UpdateChecker.releasesPage)
                }
            case .failed:
                alert.messageText = "Couldn't check for updates"
                alert.informativeText = UpdateChecker.currentVersion() == nil
                    ? "This build has no version number (dev run), so there's "
                        + "nothing to compare against."
                    : "GitHub couldn't be reached. Check your connection and try again."
                alert.runModal()
            }
        }
    }

    private func apply(_ state: PipelineState) {
        // The Badge folds the phase into its own state machine (BadgeReducer);
        // only the menu-bar icon mapping lives here.
        badge.apply(state)
        switch state {
        case .listening:
            menuBar.setIcon(.listening)
        case .downloadingModel, .loadingModel, .transcribing, .polishing:
            menuBar.setIcon(.working)
        case .inserted, .clipboard, .error, .idle:
            menuBar.setIcon(.idle)
        }
    }

    @objc private func quit() {
        listener?.stop()
        pipeline.shutdown()
        badge.hide()
        NSApp.terminate(nil)
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

// MARK: - entry point

public enum FoldWiseVoiceApp {
    public static func main() {
        var cliConfig: String?
        var cliMode: String?
        var printConfig = false
        var argIterator = CommandLine.arguments.dropFirst().makeIterator()
        while let arg = argIterator.next() {
            switch arg {
            case "--config": cliConfig = argIterator.next()
            case "--mode": cliMode = argIterator.next()
            case "--print-config": printConfig = true
            default: break
            }
        }

        if printConfig {
            // Diagnostic: load the resolved config and echo it re-serialized, to
            // verify modes.json round-trips losslessly. Exits without starting the UI.
            let url = Config.resolvePath(cliPath: cliConfig)
            let config = Config.loadOrCreate(at: url)
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("foldwise-config-check.json")
            let echo = Config(
                activeMode: config.activeMode, hotkey: config.hotkey,
                toggleHotkey: config.toggleHotkey, pauseAudio: config.pauseAudio,
                saveHistory: config.saveHistory,
                historyRetention: config.historyRetention, badgePosition: config.badgePosition,
                sidebarCollapsed: config.sidebarCollapsed, modeOrder: config.modeOrder,
                modes: config.modes, path: tmp
            )
            try? echo.save()
            print("config: \(url.path)")
            print((try? String(contentsOf: tmp, encoding: .utf8)) ?? "<save failed>")
            exit(0)
        }

        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate(configPath: cliConfig, modeOverride: cliMode)
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            app.run()
        }
    }
}
