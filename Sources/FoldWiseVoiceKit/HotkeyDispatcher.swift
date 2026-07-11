import CoreGraphics

final class HotkeyDispatcher {
    enum Event {
        case flagsChanged(keycode: CGKeyCode, flags: CGEventFlags)
        case key(keycode: CGKeyCode, character: String?, down: Bool, isRepeat: Bool)
    }

    private let ptt: KeySpec
    private let toggle: KeySpec?
    private let onPress: () -> Void
    private let onRelease: () -> Void
    private let onToggle: () -> Void
    private var pttDown = false

    init(
        pttKey: String,
        toggleKey: String?,
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void,
        onToggle: @escaping () -> Void
    ) throws {
        ptt = try KeyMap.parse(pttKey)
        toggle = try toggleKey.map { try KeyMap.parse($0) }
        self.onPress = onPress
        self.onRelease = onRelease
        self.onToggle = onToggle
    }

    func process(_ event: Event) {
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
        } else if down, let toggle, matches(toggle, keycode: keycode, character: character) {
            onToggle()
        }
    }

    private func matches(_ spec: KeySpec, keycode: CGKeyCode, character: String?) -> Bool {
        switch spec {
        case let .keycode(code): code == keycode
        case let .character(expected): expected == character
        }
    }
}
