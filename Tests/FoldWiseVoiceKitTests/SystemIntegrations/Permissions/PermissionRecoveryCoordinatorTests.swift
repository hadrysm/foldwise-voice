import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class PermissionRecoveryCoordinatorTests: XCTestCase {
    func testRefreshPublishesLivePermissionLoss() {
        var liveSnapshot = snapshot(microphone: .authorized, accessibility: true)
        let coordinator = PermissionRecoveryCoordinator(
            environment: PermissionRecoveryEnvironment(
                snapshot: { liveSnapshot },
                request: { _ in },
                openSystemSettings: { _ in }
            ),
            refreshIntervalNanoseconds: nil
        )
        var published: [PermissionRecoveryWorkflow.State] = []
        coordinator.onStateChange = { published.append($0) }
        coordinator.start()

        liveSnapshot = snapshot(microphone: .denied, accessibility: true)
        coordinator.refresh()

        XCTAssertEqual(published.map(\.isPresented), [false, true])
    }

    func testPermissionActionsRouteThroughInjectedEnvironment() {
        var requested: [PermissionKind] = []
        var opened: [PermissionKind] = []
        let coordinator = PermissionRecoveryCoordinator(
            environment: PermissionRecoveryEnvironment(
                snapshot: { self.snapshot(microphone: .authorized, accessibility: false) },
                request: { requested.append($0) },
                openSystemSettings: { opened.append($0) }
            ),
            refreshIntervalNanoseconds: nil
        )
        coordinator.start()

        coordinator.request(.accessibility)
        coordinator.openSystemSettings(.inputMonitoring)

        XCTAssertEqual(
            [requested, opened],
            [[.accessibility], [.inputMonitoring]]
        )
    }

    func testReturningFromSettingsPublishesStaleGuidanceForFailedAttempt() {
        let coordinator = PermissionRecoveryCoordinator(
            environment: PermissionRecoveryEnvironment(
                snapshot: { self.snapshot(microphone: .authorized, accessibility: false) },
                request: { _ in },
                openSystemSettings: { _ in }
            ),
            refreshIntervalNanoseconds: nil
        )
        coordinator.start()
        coordinator.openSystemSettings(.accessibility)

        coordinator.returnedFromSystemSettings()

        XCTAssertTrue(coordinator.state.staleGuidance.contains(.accessibility))
    }

    func testPresentationActionsPublishThroughCoordinatorInterface() {
        let coordinator = PermissionRecoveryCoordinator(
            environment: PermissionRecoveryEnvironment(
                snapshot: { self.snapshot(microphone: .authorized, accessibility: false) },
                request: { _ in },
                openSystemSettings: { _ in }
            ),
            refreshIntervalNanoseconds: nil
        )
        coordinator.start()

        coordinator.dismiss()
        let dismissed = coordinator.state.isPresented
        coordinator.reopen()
        let reopened = coordinator.state.isPresented
        coordinator.revealShortcutFallback()

        XCTAssertEqual(
            [dismissed, reopened, coordinator.state.showsShortcutFallback],
            [false, true, true]
        )
    }

    private func snapshot(
        microphone: MicrophonePermissionStatus,
        accessibility: Bool
    ) -> PermissionRecoverySnapshot {
        PermissionRecoverySnapshot(
            microphone: microphone,
            accessibilityGranted: accessibility,
            inputMonitoringGranted: false
        )
    }
}
