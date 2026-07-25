import XCTest
@testable import FoldWiseVoiceKit

final class PermissionRecoveryWorkflowTests: XCTestCase {
    func testPermissionMetadataMatchesMacOSAndAccessibilityContracts() {
        let permissions: [PermissionKind] = [
            .microphone,
            .accessibility,
            .inputMonitoring,
        ]

        XCTAssertEqual(
            permissions.map {
                [$0.identifier, $0.displayName, $0.systemSettingsPane]
            },
            [
                ["microphone", "Microphone", "Privacy_Microphone"],
                ["accessibility", "Accessibility", "Privacy_Accessibility"],
                ["input-monitoring", "Input Monitoring", "Privacy_ListenEvent"],
            ]
        )
    }

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

    func testLivePermissionLossPresentsGuideAfterHealthyLaunch() {
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

        PermissionRecoveryWorkflow.reduce(
            state: &state,
            action: .refresh(
                snapshot(
                    microphone: .denied,
                    accessibility: true,
                    inputMonitoring: false
                )
            )
        )

        XCTAssertTrue(state.isPresented)
    }

    func testInputMonitoringStaysHiddenUntilUserChoosesShortcutFallback() {
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
        let initiallyVisible = state.showsShortcutFallback

        PermissionRecoveryWorkflow.reduce(
            state: &state,
            action: .revealShortcutFallback
        )

        XCTAssertEqual([initiallyVisible, state.showsShortcutFallback], [false, true])
    }

    func testLiveInputMonitoringGrantRevealsChosenShortcutFallback() {
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
                    accessibility: false,
                    inputMonitoring: true
                )
            )
        )

        XCTAssertTrue(state.showsShortcutFallback)
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

    func testStaleGuidanceAppearsOnlyAfterReturningFromFailedSettingsAttempt() {
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
        let visibleDuringSettings = state.staleGuidance.contains(.accessibility)
        PermissionRecoveryWorkflow.reduce(
            state: &state,
            action: .returnedFromSystemSettings(missingAccessibility)
        )
        XCTAssertEqual(
            [
                initiallyVisible,
                visibleBeforeRefresh,
                visibleDuringSettings,
                state.staleGuidance.contains(.accessibility),
            ],
            [false, false, false, true]
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
            action: .returnedFromSystemSettings(missingAccessibility)
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
