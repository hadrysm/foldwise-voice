// FoldWise Voice — native Swift implementation.
// Menu-bar dictation app: hold a hotkey, speak, release; Parakeet (Neural
// Engine) transcribes on-device, Ollama optionally polishes, and the text is
// pasted into the focused app.

import AppKit
import Foundation

// TCP port used as a single-instance mutex (shared with the Python app so
// only one dictation app runs at a time).
private let lockPort: UInt16 = 47812

private func acquireInstanceLock(port: UInt16) -> Bool {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return true }  // can't check — proceed
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
    return true  // fd stays open (and the port bound) for the app's lifetime
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let configPath: String?
    let modeOverride: String?

    private var config: Config!
    private var pipeline: Pipeline!
    private var hud: HUDController!
    private var settings: SettingsController!
    private var menuBar: MenuBarController!
    private var listener: HotkeyListener?
    private var updateChecker: UpdateChecker!

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

        let url = Config.resolvePath(cliPath: configPath)
        config = Config.loadOrCreate(at: url)
        if let modeOverride { config.setActiveMode(modeOverride) }

        pipeline = Pipeline(config: config)
        settings = SettingsController(config: config) { [weak self] in
            self?.settingsSaved()
        }
        hud = HUDController(config: config) { [weak self] in
            self?.settings.show()
        }
        hud.recorder = pipeline.recorder
        menuBar = MenuBarController(
            config: config,
            onModeChanged: {},
            onSettings: { [weak self] in self?.settings.show() },
            onQuit: { [weak self] in self?.quit() })

        pipeline.onState = { [weak self] state in
            Task { @MainActor in self?.apply(state) }
        }

        updateChecker = UpdateChecker { [weak self] version in
            self?.menuBar.showUpdateAvailable(version)
        }
        updateChecker.start()

        Permissions.requestAtLaunch()

        startListener()
        pipeline.transcriber.warmup()

        hud.flash(
            .done,
            "FoldWise Voice ready — hold \(KeyMap.pretty(config.hotkey)) to dictate",
            seconds: 4.0)
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
                onToggle: { [weak self] in self?.pipeline.toggleRecording() })
            l.start()
            listener = l
        } catch {
            NSLog("Hotkey setup failed: \(error.localizedDescription)")
        }
    }

    private func settingsSaved() {
        startListener()
        menuBar.refreshModeChecks()
    }

    private func apply(_ state: PipelineState) {
        switch state {
        case .listening(let mode):
            menuBar.setIcon(.listening)
            hud.show(.listening, "Listening…  (\(mode))")
        case .loadingModel:
            menuBar.setIcon(.working)
            hud.show(.working, "Preparing speech model…")
        case .transcribing:
            menuBar.setIcon(.working)
            hud.show(.working, "Transcribing…")
        case .polishing(let model):
            menuBar.setIcon(.working)
            hud.show(.working, "Polishing with \(model)…")
        case .inserted:
            menuBar.setIcon(.idle)
            hud.flash(.done, "Inserted ✓")
        case .clipboard:
            menuBar.setIcon(.idle)
            hud.flash(.done, "Copied — press ⌘V to paste", seconds: 2.5)
        case .error:
            menuBar.setIcon(.idle)
            hud.flash(.error, "Something went wrong — see logs", seconds: 2.5)
        case .idle:
            menuBar.setIcon(.idle)
            hud.idle()
        }
    }

    private func quit() {
        listener?.stop()
        pipeline.shutdown()
        hud.hide()
        NSApp.terminate(nil)
    }
}

// MARK: - entry point

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
        hudPosition: config.hudPosition, modeOrder: config.modeOrder,
        modes: config.modes, path: tmp)
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
