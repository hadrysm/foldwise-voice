import CoreGraphics

final class HotkeyDispatcher {
    enum Event {
        case flagsChanged(keycode: CGKeyCode, flags: CGEventFlags)
        case key(keycode: CGKeyCode, character: String?, down: Bool, isRepeat: Bool)
    }

    private let ptt: KeySpec
    private let toggle: KeySpec?
    private let cycle: KeySpec?
    private let isSuspended: () -> Bool
    private let onPress: () -> Void
    private let onRelease: () -> Void
    private let onToggle: () -> Void
    private let onCycle: () -> Void
    private var pttDown = false
    private var toggleDown = false
    private var cycleDown = false

    init(
        pttKey: String,
        toggleKey: String?,
        cycleKey: String? = nil,
        isSuspended: @escaping () -> Bool = { false },
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void,
        onToggle: @escaping () -> Void,
        onCycle: @escaping () -> Void = {}
    ) throws {
        let commands = try ShortcutBindings(
            pushToTalk: pttKey,
            toggleRecording: toggleKey,
            modeCycle: cycleKey
        ).effectiveCommands
        guard let ptt = commands[.pushToTalk] else {
            throw ConfigError.invalid("Push to Talk must have a key.")
        }
        self.ptt = ptt
        toggle = commands[.toggleRecording]
        cycle = commands[.modeCycle]
        self.isSuspended = isSuspended
        self.onPress = onPress
        self.onRelease = onRelease
        self.onToggle = onToggle
        self.onCycle = onCycle
    }

    func process(_ event: Event) {
        if isSuspended() {
            if pttDown {
                pttDown = false
                onRelease()
            }
            toggleDown = false
            cycleDown = false
            return
        }
        switch event {
        case let .flagsChanged(keycode, flags):
            let down = KeyMap.isModifierDown(keycode: keycode, flags: flags) ?? false
            dispatch(keycode: keycode, character: nil, down: down)
        case .key(_, _, _, isRepeat: true):
            break
        case let .key(keycode, character, down, _):
            dispatch(keycode: keycode, character: character, down: down)
        }
    }

    private func dispatch(keycode: CGKeyCode, character: String?, down: Bool) {
        if matches(ptt, keycode: keycode, character: character) {
            if down, !pttDown {
                pttDown = true
                onPress()
            } else if !down, pttDown {
                pttDown = false
                onRelease()
            }
        } else if let toggle, matches(toggle, keycode: keycode, character: character) {
            if down, !toggleDown {
                toggleDown = true
                onToggle()
            } else if !down {
                toggleDown = false
            }
        } else if let cycle, matches(cycle, keycode: keycode, character: character) {
            if down, !cycleDown {
                cycleDown = true
                onCycle()
            } else if !down {
                cycleDown = false
            }
        }
    }

    private func matches(_ spec: KeySpec, keycode: CGKeyCode, character: String?) -> Bool {
        switch spec {
        case let .keycode(code): code == keycode
        case let .character(expected): expected == character
        }
    }
}
