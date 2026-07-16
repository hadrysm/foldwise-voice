import Foundation

final class ShortcutCaptureGate {
    var isCapturing = false
}

enum ShortcutCommand: Hashable {
    case pushToTalk
    case toggleRecording
    case modeCycle

    static let precedence: [ShortcutCommand] = [
        .pushToTalk,
        .toggleRecording,
        .modeCycle,
    ]

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

enum ShortcutAssignmentError: LocalizedError, Equatable {
    case latchingModifierCannotPushToTalk

    var errorDescription: String? {
        switch self {
        case .latchingModifierCannotPushToTalk:
            "Push to Talk requires a key with distinct press and release events."
        }
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

    func validateAssignment(for command: ShortcutCommand) throws {
        guard let assignedValue = value(for: command) else { return }
        let identity = try Self.validatedIdentity(assignedValue, for: command)
        for owner in ShortcutCommand.precedence where owner != command {
            guard let other = value(for: owner) else { continue }
            if try KeyMap.effectiveIdentity(other) == identity {
                throw ShortcutCollisionError(owner: owner)
            }
        }
    }

    var effectiveCommands: [ShortcutCommand: KeySpec] {
        get throws {
            var result: [ShortcutCommand: KeySpec] = [:]
            var claimed: Set<KeySpec> = []
            for command in ShortcutCommand.precedence {
                guard let value = value(for: command) else { continue }
                let identity = try Self.validatedIdentity(value, for: command)
                guard claimed.insert(identity).inserted else { continue }
                result[command] = identity
            }
            return result
        }
    }

    private static func validatedIdentity(
        _ value: String,
        for command: ShortcutCommand
    ) throws -> KeySpec {
        let identity = try KeyMap.effectiveIdentity(value)
        try validateSupport(identity, for: command)
        return identity
    }

    private static func validateSupport(_ spec: KeySpec, for command: ShortcutCommand) throws {
        guard command == .pushToTalk,
              case let .keycode(keycode) = spec,
              KeyMap.isLatchingModifier(keycode: keycode)
        else { return }
        throw ShortcutAssignmentError.latchingModifierCannotPushToTalk
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
