// Global hotkey listener: push-to-talk (hold) plus an optional tap-to-toggle
// key. Uses a listen-only CGEventTap (like pynput); needs the Accessibility /
// Input Monitoring permission. Callbacks fire on the main thread and must
// return fast — the pipeline does its heavy work elsewhere.

import AppKit
import CoreGraphics
import Foundation

final class HotkeyListener {
    private let ptt: KeySpec
    private let toggle: KeySpec?
    private let onPress: () -> Void
    private let onRelease: () -> Void
    private let onToggle: () -> Void

    private var pttDown = false
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var monitors: [Any] = []

    init(
        pttKey: String, toggleKey: String?,
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void,
        onToggle: @escaping () -> Void
    ) throws {
        self.ptt = try KeyMap.parse(pttKey)
        self.toggle = try toggleKey.map { try KeyMap.parse($0) }
        self.onPress = onPress
        self.onRelease = onRelease
        self.onToggle = onToggle
    }

    func start() {
        let mask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            let listener = Unmanaged<HotkeyListener>.fromOpaque(userInfo!).takeUnretainedValue()
            listener.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        if let tap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        } else {
            // No Input Monitoring permission for the event tap — fall back to
            // NSEvent global monitors (they need Accessibility instead).
            NSLog("CGEventTap unavailable — falling back to NSEvent monitors")
            let handler: (NSEvent) -> Void = { [weak self] event in self?.handle(nsEvent: event) }
            monitors.append(
                NSEvent.addGlobalMonitorForEvents(
                    matching: [.keyDown, .keyUp, .flagsChanged], handler: handler) as Any)
            monitors.append(
                NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) {
                    handler($0)
                    return $0
                } as Any)
        }
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
        }
        tap = nil
        runLoopSource = nil
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors = []
    }

    // MARK: - event handling

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            let keycode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            let down = KeyMap.isModifierDown(keycode: keycode, flags: event.flags) ?? false
            dispatch(keycode: keycode, character: nil, down: down)
        case .keyDown:
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return }
            let keycode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            dispatch(keycode: keycode, character: character(of: event), down: true)
        case .keyUp:
            let keycode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            dispatch(keycode: keycode, character: character(of: event), down: false)
        default:
            break
        }
    }

    private func handle(nsEvent event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            let keycode = CGKeyCode(event.keyCode)
            let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
            let down = KeyMap.isModifierDown(keycode: keycode, flags: flags) ?? false
            dispatch(keycode: keycode, character: nil, down: down)
        case .keyDown:
            if event.isARepeat { return }
            dispatch(
                keycode: CGKeyCode(event.keyCode),
                character: event.charactersIgnoringModifiers?.lowercased(), down: true)
        case .keyUp:
            dispatch(
                keycode: CGKeyCode(event.keyCode),
                character: event.charactersIgnoringModifiers?.lowercased(), down: false)
        default:
            break
        }
    }

    private func character(of event: CGEvent) -> String? {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        guard length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length).lowercased()
    }

    private func matches(_ spec: KeySpec, keycode: CGKeyCode, character: String?) -> Bool {
        switch spec {
        case .keycode(let code): return code == keycode
        case .character(let c): return c == character
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
}
