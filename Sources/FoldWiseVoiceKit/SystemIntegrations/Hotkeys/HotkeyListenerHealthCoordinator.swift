enum HotkeyListenerHealthTransition: Equatable {
    case unchanged
    case becameGlobal
    case becameFocusedAppOnly
}

@MainActor
protocol HotkeyListenerHealthEffects: AnyObject {
    func acquireGlobal() -> Bool
    func isGlobalHealthy() -> Bool
    func releaseGlobal()
    func installFocusedAppOnly()
    func removeFocusedAppOnly()
}

/// Owns permission-dependent listener transitions independently of CGEventTap
/// and NSEvent. The production shell supplies those effects; tests can drive
/// permission loss and recovery without changing macOS privacy settings.
@MainActor
final class HotkeyListenerHealthCoordinator {
    private enum State {
        case stopped
        case global
        case focusedAppOnly
    }

    private let effects: any HotkeyListenerHealthEffects
    private let onHealthChange: (ShortcutListenerHealth) -> Void
    private var state = State.stopped

    init(
        effects: any HotkeyListenerHealthEffects,
        onHealthChange: @escaping (ShortcutListenerHealth) -> Void
    ) {
        self.effects = effects
        self.onHealthChange = onHealthChange
    }

    @discardableResult
    func start() -> HotkeyListenerHealthTransition {
        guard case .stopped = state else { return .unchanged }
        if effects.acquireGlobal() {
            state = .global
            onHealthChange(.global)
            return .becameGlobal
        }
        effects.installFocusedAppOnly()
        state = .focusedAppOnly
        onHealthChange(.focusedAppOnly)
        return .becameFocusedAppOnly
    }

    @discardableResult
    func check() -> HotkeyListenerHealthTransition {
        switch state {
        case .stopped:
            return .unchanged
        case .global where effects.isGlobalHealthy():
            return .unchanged
        case .global:
            effects.releaseGlobal()
            effects.installFocusedAppOnly()
            state = .focusedAppOnly
            onHealthChange(.focusedAppOnly)
            return .becameFocusedAppOnly
        case .focusedAppOnly where effects.acquireGlobal():
            effects.removeFocusedAppOnly()
            state = .global
            onHealthChange(.global)
            return .becameGlobal
        case .focusedAppOnly:
            return .unchanged
        }
    }

    func stop() {
        switch state {
        case .stopped:
            return
        case .global:
            effects.releaseGlobal()
        case .focusedAppOnly:
            effects.removeFocusedAppOnly()
        }
        state = .stopped
    }
}
