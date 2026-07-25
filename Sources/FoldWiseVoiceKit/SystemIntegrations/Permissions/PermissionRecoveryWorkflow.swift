enum PermissionKind: Hashable {
    case microphone
    case accessibility
    case inputMonitoring

    var identifier: String {
        switch self {
        case .microphone:
            "microphone"
        case .accessibility:
            "accessibility"
        case .inputMonitoring:
            "input-monitoring"
        }
    }

    var displayName: String {
        switch self {
        case .microphone:
            "Microphone"
        case .accessibility:
            "Accessibility"
        case .inputMonitoring:
            "Input Monitoring"
        }
    }

    var systemSettingsPane: String {
        switch self {
        case .microphone:
            "Privacy_Microphone"
        case .accessibility:
            "Privacy_Accessibility"
        case .inputMonitoring:
            "Privacy_ListenEvent"
        }
    }
}

enum MicrophonePermissionStatus: Equatable {
    case notDetermined
    case restricted
    case denied
    case authorized
}

struct PermissionRecoverySnapshot: Equatable {
    var microphone: MicrophonePermissionStatus
    var accessibilityGranted: Bool
    var inputMonitoringGranted: Bool

    static let unresolved = PermissionRecoverySnapshot(
        microphone: .notDetermined,
        accessibilityGranted: false,
        inputMonitoringGranted: false
    )

    var hasFullRecovery: Bool {
        microphone == .authorized && accessibilityGranted
    }

    var hasShortcutFallback: Bool {
        !accessibilityGranted && inputMonitoringGranted
    }

    func isGranted(_ permission: PermissionKind) -> Bool {
        switch permission {
        case .microphone:
            microphone == .authorized
        case .accessibility:
            accessibilityGranted
        case .inputMonitoring:
            inputMonitoringGranted
        }
    }
}

enum PermissionRecoveryWorkflow {
    struct State: Equatable {
        var snapshot = PermissionRecoverySnapshot.unresolved
        var isPresented = false
        var showsShortcutFallback = false
        var staleGuidance: Set<PermissionKind> = []
        fileprivate var settingsAttempts: Set<PermissionKind> = []
        fileprivate var isDismissed = false
    }

    enum Action {
        case launch(PermissionRecoverySnapshot)
        case refresh(PermissionRecoverySnapshot)
        case dismiss
        case reopen
        case revealShortcutFallback
        case openedSystemSettings(PermissionKind)
        case returnedFromSystemSettings(PermissionRecoverySnapshot)
    }

    static func reduce(state: inout State, action: Action) {
        switch action {
        case let .launch(snapshot):
            state.snapshot = snapshot
            state.isPresented = !snapshot.hasFullRecovery
            state.showsShortcutFallback = snapshot.hasShortcutFallback
            state.settingsAttempts = []
            state.staleGuidance = []
            state.isDismissed = false

        case let .refresh(snapshot):
            let lostFullRecovery = state.snapshot.hasFullRecovery && !snapshot.hasFullRecovery
            state.snapshot = snapshot
            state.settingsAttempts = Set(
                state.settingsAttempts.filter { !snapshot.isGranted($0) }
            )
            state.staleGuidance = Set(
                state.staleGuidance.filter { !snapshot.isGranted($0) }
            )
            if snapshot.hasFullRecovery {
                state.isPresented = false
                state.showsShortcutFallback = false
                state.isDismissed = false
            } else {
                if lostFullRecovery, !state.isDismissed {
                    state.isPresented = true
                }
                if snapshot.hasShortcutFallback {
                    state.showsShortcutFallback = true
                }
            }

        case .dismiss:
            state.isPresented = false
            state.isDismissed = !state.snapshot.hasFullRecovery

        case .reopen:
            state.isPresented = !state.snapshot.hasFullRecovery
            state.isDismissed = false

        case .revealShortcutFallback:
            if !state.snapshot.accessibilityGranted {
                state.showsShortcutFallback = true
            }

        case let .openedSystemSettings(permission):
            guard !state.snapshot.isGranted(permission) else { return }
            state.settingsAttempts.insert(permission)
            state.staleGuidance.remove(permission)

        case let .returnedFromSystemSettings(snapshot):
            reduce(state: &state, action: .refresh(snapshot))
            state.staleGuidance.formUnion(state.settingsAttempts)
            state.settingsAttempts = []
        }
    }
}

struct PermissionRecoveryEnvironment {
    let snapshot: @MainActor () -> PermissionRecoverySnapshot
    let request: @MainActor (PermissionKind) -> Void
    let openSystemSettings: @MainActor (PermissionKind) -> Void
}

@MainActor
final class PermissionRecoveryCoordinator {
    typealias Sleep = @Sendable (UInt64) async -> Void

    private let environment: PermissionRecoveryEnvironment
    private let refreshIntervalNanoseconds: UInt64?
    private let sleep: Sleep
    private var refreshTask: Task<Void, Never>?

    private(set) var state = PermissionRecoveryWorkflow.State()
    var onStateChange: ((PermissionRecoveryWorkflow.State) -> Void)?
    var onPresentationRequest: (() -> Void)?

    init(
        environment: PermissionRecoveryEnvironment,
        refreshIntervalNanoseconds: UInt64? = 500_000_000,
        sleep: @escaping Sleep = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.environment = environment
        self.refreshIntervalNanoseconds = refreshIntervalNanoseconds
        self.sleep = sleep
    }

    deinit {
        refreshTask?.cancel()
    }

    func start() {
        stop()
        apply(.launch(environment.snapshot()))
        guard let refreshIntervalNanoseconds else { return }
        refreshTask = Task { @MainActor [weak self, sleep] in
            while !Task.isCancelled {
                await sleep(refreshIntervalNanoseconds)
                guard !Task.isCancelled, let self else { return }
                refresh()
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() {
        apply(.refresh(environment.snapshot()))
    }

    func dismiss() {
        apply(.dismiss)
    }

    func reopen() {
        apply(.reopen)
    }

    func revealShortcutFallback() {
        apply(.revealShortcutFallback)
    }

    func request(_ permission: PermissionKind) {
        environment.request(permission)
    }

    func openSystemSettings(_ permission: PermissionKind) {
        apply(.openedSystemSettings(permission))
        environment.openSystemSettings(permission)
    }

    func returnedFromSystemSettings() {
        apply(.returnedFromSystemSettings(environment.snapshot()))
    }

    private func apply(_ action: PermissionRecoveryWorkflow.Action) {
        let wasPresented = state.isPresented
        PermissionRecoveryWorkflow.reduce(state: &state, action: action)
        onStateChange?(state)
        if !wasPresented, state.isPresented {
            onPresentationRequest?()
        }
    }
}
