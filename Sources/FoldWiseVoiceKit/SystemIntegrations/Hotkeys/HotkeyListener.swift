// Global hotkey listener: push-to-talk (hold) plus an optional tap-to-toggle
// key. Uses a listen-only CGEventTap (like pynput); needs the Accessibility /
// Input Monitoring permission. Callbacks fire on the main thread and must
// return fast — the pipeline does its heavy work elsewhere.

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import os

@MainActor
final class HotkeyListener: HotkeyListening {
    private final class HealthEffects: HotkeyListenerHealthEffects {
        weak var listener: HotkeyListener?

        init(listener: HotkeyListener) {
            self.listener = listener
        }

        func acquireGlobal() -> Bool {
            listener?.createTap() ?? false
        }

        func isGlobalHealthy() -> Bool {
            guard let tap = listener?.tap else { return false }
            return CGEvent.tapIsEnabled(tap: tap)
        }

        func releaseGlobal() {
            listener?.destroyTap()
        }

        func installFocusedAppOnly() {
            listener?.installMonitors()
        }

        func removeFocusedAppOnly() {
            listener?.removeMonitors()
        }
    }

    private let dispatcher: HotkeyDispatcher
    var onHealthChange: ((ShortcutListenerHealth) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var monitors: [Any] = []
    private var retryTimer: Timer?
    private lazy var health = HotkeyListenerHealthCoordinator(
        effects: HealthEffects(listener: self),
        onHealthChange: { [weak self] health in self?.onHealthChange?(health) }
    )

    init(
        pttKey: String, toggleKey: String?, cycleKey: String? = nil,
        isSuspended: @escaping () -> Bool = { false },
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void,
        onToggle: @escaping () -> Void,
        onCycle: @escaping () -> Void = {}
    ) throws {
        dispatcher = try HotkeyDispatcher(
            pttKey: pttKey,
            toggleKey: toggleKey,
            cycleKey: cycleKey,
            isSuspended: isSuspended,
            onPress: onPress,
            onRelease: onRelease,
            onToggle: onToggle,
            onCycle: onCycle
        )
    }

    init(dispatcher: HotkeyDispatcher) {
        self.dispatcher = dispatcher
    }

    func start() throws {
        if health.start() == .becameFocusedAppOnly {
            // No effective Input Monitoring / Accessibility grant for the
            // event tap yet. Fall back to NSEvent monitors so the hotkey at
            // least works while the app is frontmost (the global monitor is
            // equally gated, so background keystrokes stay invisible).
            Log.hotkey.warning("CGEventTap unavailable — falling back to NSEvent monitors, will retry")
        }
        // Watchdog, both directions: a grant made in System Settings never
        // revives an already-failed tap (so retry until one succeeds), and a
        // grant lost while running — revoked, or invalidated by an app update
        // re-signing the binary — leaves a tap that exists but is permanently
        // disabled (so drop back to monitors and keep retrying).
        retryTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkTapHealth() }
        }
    }

    func stop() {
        dispatcher.releaseActivePushToTalkHold()
        retryTimer?.invalidate()
        retryTimer = nil
        health.stop()
    }

    private func checkTapHealth() {
        switch health.check() {
        case .becameFocusedAppOnly:
            Log.hotkey.warning("CGEventTap lost — falling back to NSEvent monitors, will retry")
        case .becameGlobal:
            Log.hotkey.info("CGEventTap acquired — hotkey now works in the background")
        case .unchanged:
            break
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
                matching: [.keyDown, .keyUp, .flagsChanged], handler: handler
            ) as Any
        )
        monitors.append(
            NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) {
                handler($0)
                return $0
            } as Any
        )
    }

    private func removeMonitors() {
        for m in monitors {
            NSEvent.removeMonitor(m)
        }
        monitors = []
    }

    // MARK: - event handling

    private func handle(type: CGEventType, event: CGEvent) {
        let keycode = { CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)) }
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            dispatcher.process(.flagsChanged(keycode: keycode(), flags: event.flags))
        case .keyDown:
            dispatcher.process(.key(
                keycode: keycode(), character: character(of: event), down: true,
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            ))
        case .keyUp:
            dispatcher.process(.key(
                keycode: keycode(), character: character(of: event), down: false, isRepeat: false
            ))
        default:
            break
        }
    }

    private func handle(nsEvent event: NSEvent) {
        let character = { event.charactersIgnoringModifiers?.lowercased() }
        switch event.type {
        case .flagsChanged:
            dispatcher.process(.flagsChanged(
                keycode: CGKeyCode(event.keyCode),
                flags: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
            ))
        case .keyDown:
            dispatcher.process(.key(
                keycode: CGKeyCode(event.keyCode), character: character(), down: true,
                isRepeat: event.isARepeat
            ))
        case .keyUp:
            dispatcher.process(.key(
                keycode: CGKeyCode(event.keyCode), character: character(), down: false,
                isRepeat: false
            ))
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
}
