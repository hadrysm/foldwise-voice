import AppKit

@MainActor
enum ModePresentationFactory {
    static func projection(
        modes: [Mode],
        selection: DictationSelection
    ) -> ModeSelectionProjection {
        ModeSelectionProjection(
            modes: modes,
            selection: selection,
            iconIsAvailable: {
                NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
            }
        )
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
}
