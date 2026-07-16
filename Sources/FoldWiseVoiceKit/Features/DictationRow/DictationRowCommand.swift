/// User intent emitted by the shared row. The source History entry is retained
/// by the surface projection and supplied to the workflow beside this command.
enum DictationRowCommand: Equatable {
    case copyDisplayed
    case copyRaw
    case toggleFlag
    case rerunPolish(modeID: ModeID)
    case delete
}

struct DictationRowPolishMode: Equatable {
    let id: ModeID
    let name: String
}

/// Capabilities available only on History's More menu. A nil value means the
/// row is being rendered on Home and has no More action.
struct DictationRowMoreCapabilities: Equatable {
    let canCopyRaw: Bool
    let polishModes: [DictationRowPolishMode]
}

struct DictationRowActionComposition: Equatable {
    enum DirectAction: Equatable {
        case copy
        case flag
        case more
    }

    struct LabeledCommand: Equatable {
        let label: String
        let command: DictationRowCommand
        let isDestructive: Bool
    }

    enum MoreAction: Equatable {
        case command(LabeledCommand)
        case submenu(label: String, commands: [LabeledCommand])
        case separator
    }

    let directActions: [DirectAction]
    let moreActions: [MoreAction]

    static func make(
        presentation: DictationRowPresentation,
        moreCapabilities: DictationRowMoreCapabilities?
    ) -> DictationRowActionComposition {
        guard let moreCapabilities else {
            return DictationRowActionComposition(
                directActions: [.copy, .flag],
                moreActions: []
            )
        }
        var actions: [MoreAction] = [
            .command(LabeledCommand(
                label: "Copy",
                command: .copyDisplayed,
                isDestructive: false
            )),
        ]
        if moreCapabilities.canCopyRaw {
            actions.append(.command(LabeledCommand(
                label: "Copy raw",
                command: .copyRaw,
                isDestructive: false
            )))
        }
        actions.append(.command(LabeledCommand(
            label: DictationRowAccessibility.flagLabel(isFlagged: presentation.isFlagged),
            command: .toggleFlag,
            isDestructive: false
        )))
        if !moreCapabilities.polishModes.isEmpty {
            actions.append(.submenu(
                label: "Re-run Polish",
                commands: moreCapabilities.polishModes.map { mode in
                    LabeledCommand(
                        label: mode.name,
                        command: .rerunPolish(modeID: mode.id),
                        isDestructive: false
                    )
                }
            ))
        }
        actions.append(.separator)
        actions.append(.command(LabeledCommand(
            label: "Delete",
            command: .delete,
            isDestructive: true
        )))
        return DictationRowActionComposition(
            directActions: [.copy, .flag, .more],
            moreActions: actions
        )
    }
}
