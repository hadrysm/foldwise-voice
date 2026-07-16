import AppKit

@MainActor
enum ModePresentationFactory {
    static func projection(
        modes: [Mode],
        selection: DictationSelection
    ) -> ModeSelectionProjection {
        do {
            return try ModeSelectionProjection(
                modes: modes,
                selection: selection,
                iconIsAvailable: {
                    NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
                }
            )
        } catch {
            Log.config.error(
                "Could not project Mode selection: \(error.localizedDescription, privacy: .public)"
            )
            return .systemOnly(selection: selection)
        }
    }

    static func menuItem(
        for presentation: ModeSelectionItem,
        target: AnyObject?,
        action: Selector
    ) -> NSMenuItem {
        let item = NSMenuItem(title: presentation.name, action: action, keyEquivalent: "")
        item.target = target
        item.representedObject = presentation.id
        item.image = NSImage(
            systemSymbolName: presentation.icon,
            accessibilityDescription: presentation.name
        )
        item.toolTip = presentation.summary
        item.state = presentation.isSelected ? .on : .off
        item.setAccessibilityLabel(presentation.accessibilityLabel)
        item.setAccessibilityValue(presentation.accessibilityValue)
        item.setAccessibilityHelp(presentation.accessibilityHint)
        return item
    }

    static func menuItems(
        for projection: ModeSelectionProjection,
        target: AnyObject?,
        action: Selector,
        isEnabled: Bool
    ) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        for (index, projectionItem) in projection.items.enumerated() {
            if index == 1 { items.append(.separator()) }
            let item = menuItem(for: projectionItem, target: target, action: action)
            item.isEnabled = isEnabled
            items.append(item)
        }
        return items
    }

    static func refreshMenuItems(
        _ items: [NSMenuItem],
        selection: DictationSelection,
        isEnabled: Bool
    ) {
        for item in items {
            guard let itemSelection = item.representedObject as? DictationSelection else { continue }
            let isSelected = itemSelection == selection
            item.state = isSelected ? .on : .off
            item.setAccessibilityValue(isSelected ? "Selected" : "Not selected")
            item.isEnabled = isEnabled
        }
    }
}
