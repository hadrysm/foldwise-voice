// Menu-bar status item: SF Symbol mic icon (red while listening, waveform
// while working), mode switcher, Settings, Quit.

import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let config: Config
    private let onModeChanged: () -> Void
    private let onSettings: () -> Void
    private let onQuit: () -> Void

    private var statusItem: NSStatusItem!
    private var modeItems: [NSMenuItem] = []

    init(
        config: Config,
        onModeChanged: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.config = config
        self.onModeChanged = onModeChanged
        self.onSettings = onSettings
        self.onQuit = onQuit
        super.init()
        build()
    }

    enum Icon { case idle, listening, working }

    func setIcon(_ icon: Icon) {
        guard let button = statusItem.button else { return }
        let (symbol, tint): (String, NSColor?) =
            switch icon {
            case .idle: ("mic", nil)
            case .listening: ("mic.fill", .systemRed)
            case .working: ("waveform", .systemOrange)
            }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "FoldWise Voice")?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        button.contentTintColor = tint
    }

    func refreshModeChecks() {
        for item in modeItems {
            item.state = item.title == config.activeMode ? .on : .off
        }
    }

    private func build() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIcon(.idle)

        let menu = NSMenu()
        menu.autoenablesItems = false

        let header = NSMenuItem(title: "FoldWise Voice", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        modeItems = []
        for name in config.modeOrder {
            let item = NSMenuItem(
                title: name, action: #selector(switchMode(_:)), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            modeItems.append(item)
        }

        menu.addItem(.separator())
        let settings = NSMenuItem(
            title: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit FoldWise Voice", action: #selector(quitApp(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        refreshModeChecks()
    }

    @objc private func switchMode(_ sender: NSMenuItem) {
        config.setActiveMode(sender.title)
        try? config.save()
        refreshModeChecks()
        onModeChanged()
    }

    @objc private func openSettings(_ sender: Any?) {
        onSettings()
    }

    @objc private func quitApp(_ sender: Any?) {
        onQuit()
    }
}
