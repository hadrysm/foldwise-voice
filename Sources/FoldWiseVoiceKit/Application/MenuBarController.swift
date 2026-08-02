// Menu-bar status item: SF Symbol waveform icon (red while listening, orange
// while working), mode switcher, Settings, Quit.

import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let config: Config
    private let onSettings: () -> Void
    private let onCheckForUpdates: () -> Void
    private let onModeSelectionError: () -> Void
    private let onQuit: () -> Void

    private let statusItem: NSStatusItem
    private let checkUpdatesItem = NSMenuItem(
        title: "Check for Updates…",
        action: #selector(MenuBarController.checkForUpdates(_:)),
        keyEquivalent: ""
    )
    private var modeItems: [NSMenuItem] = []
    private let modeEndSeparator: NSMenuItem = .separator()

    init(
        config: Config,
        onSettings: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void,
        canCheckForUpdates: Bool = true,
        onModeSelectionError: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        menu: NSMenu? = nil,
        statusItem: NSStatusItem? = nil
    ) {
        self.config = config
        self.onSettings = onSettings
        self.onCheckForUpdates = onCheckForUpdates
        self.onModeSelectionError = onModeSelectionError
        self.onQuit = onQuit
        self.statusItem = statusItem
            ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        build(menu ?? NSMenu())
        checkUpdatesItem.isEnabled = canCheckForUpdates
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
        // One shape across all three states — the tint carries the state, the
        // way the Badge's accent does. Untinted it stays a template image, so
        // macOS inverts it for a Light menu bar.
        let tint: NSColor? =
            switch icon {
            case .idle: nil
            case .listening: .systemRed
            case .working: .systemOrange
            }
        let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "FoldWise Voice")?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = tint
    }

    func setCanCheckForUpdates(_ canCheckForUpdates: Bool) {
        checkUpdatesItem.isEnabled = canCheckForUpdates
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

        menu.addItem(modeEndSeparator)
        let settings = NSMenuItem(
            title: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        checkUpdatesItem.target = self
        menu.addItem(checkUpdatesItem)

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
