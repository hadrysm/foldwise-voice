enum HotkeyListenerHealthTransition: Equatable {
    case unchanged
    case becameGlobal
    case becameFocusedAppOnly
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

    private let acquireGlobal: () -> Bool
    private let isGlobalHealthy: () -> Bool
    private let releaseGlobal: () -> Void
    private let installFocusedAppOnly: () -> Void
    private let removeFocusedAppOnly: () -> Void
    private let onHealthChange: (ShortcutListenerHealth) -> Void
    private var state = State.stopped

    init(
        acquireGlobal: @escaping () -> Bool,
        isGlobalHealthy: @escaping () -> Bool,
        releaseGlobal: @escaping () -> Void,
        installFocusedAppOnly: @escaping () -> Void,
        removeFocusedAppOnly: @escaping () -> Void,
        onHealthChange: @escaping (ShortcutListenerHealth) -> Void
    ) {
        self.acquireGlobal = acquireGlobal
        self.isGlobalHealthy = isGlobalHealthy
        self.releaseGlobal = releaseGlobal
        self.installFocusedAppOnly = installFocusedAppOnly
        self.removeFocusedAppOnly = removeFocusedAppOnly
        self.onHealthChange = onHealthChange
    }

    @discardableResult
    func start() -> HotkeyListenerHealthTransition {
        guard case .stopped = state else { return .unchanged }
        if acquireGlobal() {
            state = .global
            onHealthChange(.global)
            return .becameGlobal
        }
        installFocusedAppOnly()
        state = .focusedAppOnly
        onHealthChange(.focusedAppOnly)
        return .becameFocusedAppOnly
    }

    @discardableResult
    func check() -> HotkeyListenerHealthTransition {
        switch state {
        case .stopped:
            return .unchanged
        case .global where isGlobalHealthy():
            return .unchanged
        case .global:
            releaseGlobal()
            installFocusedAppOnly()
            state = .focusedAppOnly
            onHealthChange(.focusedAppOnly)
            return .becameFocusedAppOnly
        case .focusedAppOnly where acquireGlobal():
            removeFocusedAppOnly()
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
            releaseGlobal()
        case .focusedAppOnly:
            removeFocusedAppOnly()
        }
        state = .stopped
    }
}
