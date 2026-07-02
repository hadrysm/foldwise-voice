// Global hotkey listener: push-to-talk (hold) plus an optional tap-to-toggle
// key. Uses a listen-only CGEventTap (like pynput); needs the Accessibility /
// Input Monitoring permission. Callbacks fire on the main thread and must
// return fast — the pipeline does its heavy work elsewhere.

import AppKit
import ApplicationServices
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
    private var retryTimer: Timer?

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
        if !createTap() {
            // No effective Input Monitoring / Accessibility grant for the
            // event tap yet. Fall back to NSEvent monitors so the hotkey at
            // least works while the app is frontmost (the global monitor is
            // equally gated, so background keystrokes stay invisible).
            NSLog("CGEventTap unavailable — falling back to NSEvent monitors, will retry")
            installMonitors()
        }
        // Watchdog, both directions: a grant made in System Settings never
        // revives an already-failed tap (so retry until one succeeds), and a
        // grant lost while running — revoked, or invalidated by an app update
        // re-signing the binary — leaves a tap that exists but is permanently
        // disabled (so drop back to monitors and keep retrying).
        retryTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) {
            [weak self] _ in self?.checkTapHealth()
        }
    }

    func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        destroyTap()
        removeMonitors()
    }

    private func checkTapHealth() {
        if let tap {
            if CGEvent.tapIsEnabled(tap: tap) { return }
            NSLog("CGEventTap lost — falling back to NSEvent monitors, will retry")
            destroyTap()
            installMonitors()
        } else if createTap() {
            NSLog("CGEventTap acquired — hotkey now works in the background")
            removeMonitors()
        }
    }

    private func createTap() -> Bool {
        // tapCreate alone is not proof the hotkey works: with a stale TCC
        // entry (an earlier build's signature still listed in System
        // Settings) it can succeed while WindowServer never enables event
        // delivery. Preflight the actual permission, and verify the tap
        // really came up enabled.
        guard AXIsProcessTrusted() || CGPreflightListenEventAccess() else { return false }

        let mask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            let listener = Unmanaged<HotkeyListener>.fromOpaque(userInfo!).takeUnretainedValue()
            listener.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: CGEventMask(mask),
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else { return false }

        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap) else {
            destroyTap()
            return false
        }
        return true
    }

    private func destroyTap() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        // Without this the dead tap lingers in the session tap list for the
        // life of the process.
        CFMachPortInvalidate(tap)
        self.tap = nil
        runLoopSource = nil
    }

    private func installMonitors() {
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

    private func removeMonitors() {
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
