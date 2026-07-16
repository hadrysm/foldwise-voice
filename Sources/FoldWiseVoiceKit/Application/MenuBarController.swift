// Menu-bar status item: SF Symbol mic icon (red while listening, waveform
// while working), mode switcher, Settings, Quit.

import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let config: Config
    private let onSettings: () -> Void
    private let onCheckForUpdates: () -> Void
    private let onModeSelectionError: () -> Void
    private let onQuit: () -> Void

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var modeItems: [NSMenuItem] = []
    private let modeEndSeparator: NSMenuItem = .separator()
    /// Hidden until UpdateChecker reports a newer release.
    private let updateItem = NSMenuItem(
        title: "Update Available…",
        action: #selector(MenuBarController.openReleasePage(_:)),
        keyEquivalent: ""
    )
    private let updateSeparator: NSMenuItem = .separator()

    init(
        config: Config,
        onSettings: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void,
        onModeSelectionError: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        menu: NSMenu? = nil
    ) {
        self.config = config
        self.onSettings = onSettings
        self.onCheckForUpdates = onCheckForUpdates
        self.onModeSelectionError = onModeSelectionError
        self.onQuit = onQuit
        super.init()
        build(menu ?? NSMenu())
        // Wherever the active mode is changed — here, the Badge's mode menu,
        // or Settings — the checkmarks follow.
        config.onChange { [weak self] changes in
            if changes.contains(.modeLibrary) {
                self?.rebuildModeItems()
            } else if changes.contains(.selection) {
                self?.refreshModeChecks()
            }
        }
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

    func showUpdateAvailable(_ version: String) {
        updateItem.title = "Update Available: v\(version)…"
        updateItem.isHidden = false
        updateSeparator.isHidden = false
    }

    private func refreshModeChecks() {
        ModePresentationFactory.refreshMenuItems(
            modeItems,
            selection: config.selection,
            isEnabled: !config.isReadOnly
        )
    }

    private func rebuildModeItems() {
        guard let menu = statusItem.menu else { return }
        for item in modeItems {
            menu.removeItem(item)
        }
        modeItems = []
        let insertionIndex = menu.index(of: modeEndSeparator)
        guard insertionIndex >= 0 else { return }

        let projection = ModePresentationFactory.projection(
            modes: config.orderedModes,
            selection: config.selection
        )
        let rebuiltItems = ModePresentationFactory.menuItems(
            for: projection,
            target: self,
            action: #selector(switchMode(_:)),
            isEnabled: !config.isReadOnly
        )
        var nextIndex = insertionIndex
        for item in rebuiltItems {
            menu.insertItem(item, at: nextIndex)
            nextIndex += 1
        }
        modeItems = rebuiltItems
    }

    private func build(_ menu: NSMenu) {
        setIcon(.idle)

        menu.autoenablesItems = false

        let header = NSMenuItem(title: "FoldWise Voice", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        updateItem.target = self
        updateItem.isHidden = true
        updateItem.image = NSImage(
            systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil
        )
        menu.addItem(updateItem)
        updateSeparator.isHidden = true
        menu.addItem(updateSeparator)

        menu.addItem(modeEndSeparator)
        let settings = NSMenuItem(
            title: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        let checkUpdates = NSMenuItem(
            title: "Check for Updates…", action: #selector(checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkUpdates.target = self
        menu.addItem(checkUpdates)

        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit FoldWise Voice", action: #selector(quitApp(_:)), keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        rebuildModeItems()
    }

    @objc private func switchMode(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? DictationSelection else { return }
        do {
            try config.select(selection)
        } catch {
            onModeSelectionError()
            Log.config.error(
                "Could not select Mode from the menu bar: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    @objc private func openReleasePage(_ sender: Any?) {
        NSWorkspace.shared.open(UpdateChecker.releasesPage)
    }

    @objc private func openSettings(_ sender: Any?) {
        onSettings()
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        onCheckForUpdates()
    }

    @objc private func quitApp(_ sender: Any?) {
        onQuit()
    }
}
