import Foundation

enum ShortcutListenerHealth: Equatable {
    case global
    case focusedAppOnly
}

@MainActor
protocol HotkeyListening: AnyObject {
    var onHealthChange: ((ShortcutListenerHealth) -> Void)? { get set }
    func start() throws
    func stop()
}

struct HotkeyCallbacks {
    let isSuspended: () -> Bool
    let onPress: () -> Void
    let onRelease: () -> Void
    let onToggle: () -> Void
    let onCycle: () -> Void
    let onHealthChange: (ShortcutListenerHealth) -> Void
}

@MainActor
final class HotkeyBindingCoordinator {
    typealias Prepare = (ShortcutBindings, HotkeyCallbacks) throws -> any HotkeyListening

    private final class DispatchGate {
        var isActive: Bool
        private var pendingHealth: ShortcutListenerHealth?

        init(isActive: Bool) {
            self.isActive = isActive
        }

        func receiveHealth(
            _ health: ShortcutListenerHealth,
            publish: (ShortcutListenerHealth) -> Void
        ) {
            guard isActive else {
                pendingHealth = health
                return
            }
            publish(health)
        }

        func activate(publishHealth: (ShortcutListenerHealth) -> Void) {
            isActive = true
            guard let pendingHealth else { return }
            self.pendingHealth = nil
            publishHealth(pendingHealth)
        }
    }

    private struct ListenerSession {
        let listener: any HotkeyListening
        let dispatchGate: DispatchGate
    }

    private let config: Config
    private let callbacks: HotkeyCallbacks
    private let prepare: Prepare
    private var active: ListenerSession?

    init(
        config: Config,
        callbacks: HotkeyCallbacks,
        prepare: @escaping Prepare
    ) {
        self.config = config
        self.callbacks = callbacks
        self.prepare = prepare
    }

    var bindings: ShortcutBindings {
        ShortcutBindings(
            pushToTalk: config.hotkey,
            toggleRecording: config.toggleHotkey,
            modeCycle: config.modeCycleHotkey
        )
    }

    func start() throws {
        let session = try makeSession(for: bindings, initiallyActive: true)
        do {
            try session.listener.start()
            active = session
        } catch {
            session.dispatchGate.isActive = false
            session.listener.stop()
            throw error
        }
    }

    func stop() {
        active?.dispatchGate.isActive = false
        active?.listener.stop()
        active = nil
    }

    func update(_ candidateBindings: ShortcutBindings) throws {
        guard candidateBindings != bindings else { return }
        let candidate = try makeSession(for: candidateBindings, initiallyActive: false)
        do {
            // Starting can fail, so fully arm the candidate while its dispatch
            // gate is closed and the committed listener remains authoritative.
            try candidate.listener.start()
        } catch {
            candidate.listener.stop()
            throw error
        }
        do {
            try config.setShortcutBindings(candidateBindings) { [self] in
                active?.dispatchGate.isActive = false
                active?.listener.stop()
                candidate.dispatchGate.activate(publishHealth: callbacks.onHealthChange)
            }
            active = candidate
        } catch {
            candidate.listener.stop()
            throw error
        }
    }

    private func makeSession(
        for bindings: ShortcutBindings,
        initiallyActive: Bool
    ) throws -> ListenerSession {
        let dispatchGate = DispatchGate(isActive: initiallyActive)
        let gatedCallbacks = HotkeyCallbacks(
            isSuspended: { [callbacks] in
                !dispatchGate.isActive || callbacks.isSuspended()
            },
            onPress: callbacks.onPress,
            onRelease: callbacks.onRelease,
            onToggle: callbacks.onToggle,
            onCycle: callbacks.onCycle,
            onHealthChange: { [callbacks] health in
                dispatchGate.receiveHealth(health, publish: callbacks.onHealthChange)
            }
        )
        return try ListenerSession(
            listener: prepare(bindings, gatedCallbacks),
            dispatchGate: dispatchGate
        )
    }
}
