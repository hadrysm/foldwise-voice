import XCTest
@testable import FoldWiseVoiceKit

final class PermissionRecoveryWorkflowTests: XCTestCase {
    func testLaunchPresentsGuideWhenFullRecoveryIsMissing() {
        var state = PermissionRecoveryWorkflow.State()

        PermissionRecoveryWorkflow.reduce(
            state: &state,
            action: .launch(
                snapshot(
                    microphone: .authorized,
                    accessibility: false,
                    inputMonitoring: true
                )
            )
        )

        XCTAssertTrue(state.isPresented)
    }

    func testLaunchDoesNotPresentGuideWhenOnlyInputMonitoringIsMissing() {
        var state = PermissionRecoveryWorkflow.State()

        PermissionRecoveryWorkflow.reduce(
            state: &state,
            action: .launch(
                snapshot(
                    microphone: .authorized,
                    accessibility: true,
                    inputMonitoring: false
                )
            )
        )

        XCTAssertFalse(state.isPresented)
    }

    func testDismissalSurvivesLiveRefreshUntilGuideIsReopened() {
        var state = PermissionRecoveryWorkflow.State()
        let missingAccessibility = snapshot(
            microphone: .authorized,
            accessibility: false,
            inputMonitoring: false
        )

        PermissionRecoveryWorkflow.reduce(
            state: &state,
            action: .launch(missingAccessibility)
        )
        PermissionRecoveryWorkflow.reduce(state: &state, action: .dismiss)
        PermissionRecoveryWorkflow.reduce(
            state: &state,
            action: .refresh(missingAccessibility)
        )
        let dismissedAfterRefresh = state.isPresented
        PermissionRecoveryWorkflow.reduce(state: &state, action: .reopen)

        XCTAssertEqual([dismissedAfterRefresh, state.isPresented], [false, true])
    }

    func testFullRecoveryClosesGuideWithoutRelaunch() {
        var state = PermissionRecoveryWorkflow.State()
        PermissionRecoveryWorkflow.reduce(
            state: &state,
            action: .launch(
                snapshot(
                    microphone: .authorized,
                    accessibility: false,
                    inputMonitoring: false
                )
            )
        )

        PermissionRecoveryWorkflow.reduce(
            state: &state,
            action: .refresh(
                snapshot(
                    microphone: .authorized,
                    accessibility: true,
                    inputMonitoring: false
                )
            )
        )

        XCTAssertFalse(state.isPresented)
    }

    func testInputMonitoringIsShortcutFallbackNotFullRecovery() {
        let permissions = snapshot(
            microphone: .authorized,
            accessibility: false,
            inputMonitoring: true
        )

        XCTAssertEqual(
            [permissions.hasFullRecovery, permissions.hasShortcutFallback],
            [false, true]
        )
    }

    func testStaleGuidanceAppearsOnlyAfterSettingsAttemptAndFailedLiveRefresh() {
        var state = PermissionRecoveryWorkflow.State()
        let missingAccessibility = snapshot(
            microphone: .authorized,
            accessibility: false,
            inputMonitoring: false
        )
        PermissionRecoveryWorkflow.reduce(
            state: &state,
            action: .launch(missingAccessibility)
        )
        let initiallyVisible = state.staleGuidance.contains(.accessibility)
        PermissionRecoveryWorkflow.reduce(
            state: &state,
            action: .openedSystemSettings(.accessibility)
        )
        let visibleBeforeRefresh = state.staleGuidance.contains(.accessibility)
        PermissionRecoveryWorkflow.reduce(
            state: &state,
            action: .refresh(missingAccessibility)
        )

        XCTAssertEqual(
            [
                initiallyVisible,
                visibleBeforeRefresh,
                state.staleGuidance.contains(.accessibility),
            ],
            [false, false, true]
        )
    }

    func testGrantRemovesStaleGuidance() {
        var state = PermissionRecoveryWorkflow.State()
        let missingAccessibility = snapshot(
            microphone: .authorized,
            accessibility: false,
            inputMonitoring: false
        )
        PermissionRecoveryWorkflow.reduce(
            state: &state,
            action: .launch(missingAccessibility)
        )
        PermissionRecoveryWorkflow.reduce(
            state: &state,
            action: .openedSystemSettings(.accessibility)
        )
        PermissionRecoveryWorkflow.reduce(
            state: &state,
            action: .refresh(missingAccessibility)
        )

        PermissionRecoveryWorkflow.reduce(
            state: &state,
            action: .refresh(
                snapshot(
                    microphone: .authorized,
                    accessibility: true,
                    inputMonitoring: false
                )
            )
        )

        XCTAssertFalse(state.staleGuidance.contains(.accessibility))
    }

    private func snapshot(
        microphone: MicrophonePermissionStatus,
        accessibility: Bool,
        inputMonitoring: Bool
    ) -> PermissionRecoverySnapshot {
        PermissionRecoverySnapshot(
            microphone: microphone,
            accessibilityGranted: accessibility,
            inputMonitoringGranted: inputMonitoring
        )
    }
}
