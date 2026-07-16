import Foundation

final class ShortcutCaptureGate {
    var isCapturing = false
}

enum ShortcutCommand: CaseIterable, Hashable {
    case pushToTalk
    case toggleRecording
    case modeCycle

    var title: String {
        switch self {
        case .pushToTalk: "Push to Talk"
        case .toggleRecording: "Toggle Recording"
        case .modeCycle: "Cycle Modes"
        }
    }
}

struct ShortcutCollisionError: LocalizedError, Equatable {
    let owner: ShortcutCommand

    var errorDescription: String? {
        "That key is already assigned to \(owner.title)."
    }
}

struct ShortcutBindings: Equatable {
    var pushToTalk: String
    var toggleRecording: String?
    var modeCycle: String?

    func value(for command: ShortcutCommand) -> String? {
        switch command {
        case .pushToTalk: pushToTalk
        case .toggleRecording: toggleRecording
        case .modeCycle: modeCycle
        }
    }

    func validatingAssignment(for command: ShortcutCommand) throws -> ShortcutBindings {
        guard let assignedValue = value(for: command) else { return self }
        let identity = try KeyMap.effectiveIdentity(assignedValue)
        for owner in ShortcutCommand.allCases where owner != command {
            guard let other = value(for: owner) else { continue }
            if try KeyMap.effectiveIdentity(other) == identity {
                throw ShortcutCollisionError(owner: owner)
            }
        }
        return self
    }

    var effectiveCommands: [ShortcutCommand: KeySpec] {
        get throws {
            var result: [ShortcutCommand: KeySpec] = [:]
            var claimed: Set<KeySpec> = []
            for command in ShortcutCommand.allCases {
                guard let value = value(for: command) else { continue }
                let identity = try KeyMap.effectiveIdentity(value)
                guard claimed.insert(identity).inserted else { continue }
                result[command] = identity
            }
            return result
        }
    }
}

enum ModeCyclePolicy {
    static func nextSelection(
        after selection: DictationSelection,
        orderedModeIDs: [ModeID]
    ) -> DictationSelection? {
        guard !orderedModeIDs.isEmpty else { return nil }
        switch selection {
        case .voiceToText:
            return .mode(orderedModeIDs[0])
        case let .mode(id):
            guard orderedModeIDs.count > 1,
                  let index = orderedModeIDs.firstIndex(of: id)
            else { return nil }
            let next = orderedModeIDs.index(after: index)
            return .mode(next == orderedModeIDs.endIndex ? orderedModeIDs[0] : orderedModeIDs[next])
        }
    }
}
