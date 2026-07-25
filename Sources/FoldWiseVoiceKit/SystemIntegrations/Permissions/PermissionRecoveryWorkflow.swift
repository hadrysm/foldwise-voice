enum PermissionKind: String, CaseIterable, Hashable {
    case microphone
    case accessibility
    case inputMonitoring
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
        var staleGuidance: Set<PermissionKind> = []
        fileprivate var settingsAttempts: Set<PermissionKind> = []
    }

    enum Action {
        case launch(PermissionRecoverySnapshot)
        case refresh(PermissionRecoverySnapshot)
        case dismiss
        case reopen
        case openedSystemSettings(PermissionKind)
    }

    static func reduce(state: inout State, action: Action) {
        switch action {
        case let .launch(snapshot):
            state.snapshot = snapshot
            state.isPresented = !snapshot.hasFullRecovery
            state.settingsAttempts = []
            state.staleGuidance = []

        case let .refresh(snapshot):
            state.snapshot = snapshot
            state.settingsAttempts = Set(
                state.settingsAttempts.filter { !snapshot.isGranted($0) }
            )
            state.staleGuidance = state.settingsAttempts
            if snapshot.hasFullRecovery {
                state.isPresented = false
            }

        case .dismiss:
            state.isPresented = false

        case .reopen:
            state.isPresented = !state.snapshot.hasFullRecovery

        case let .openedSystemSettings(permission):
            guard !state.snapshot.isGranted(permission) else { return }
            state.settingsAttempts.insert(permission)
        }
    }
}
