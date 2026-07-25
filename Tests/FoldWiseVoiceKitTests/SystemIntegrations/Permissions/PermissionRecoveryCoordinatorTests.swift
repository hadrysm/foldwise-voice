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
        var presentationRequests = 0
        coordinator.onStateChange = { published.append($0) }
        coordinator.onPresentationRequest = { presentationRequests += 1 }
        coordinator.start()

        liveSnapshot = snapshot(microphone: .denied, accessibility: true)
        coordinator.refresh()

        XCTAssertEqual(published.map(\.isPresented), [false, true])
        XCTAssertEqual(presentationRequests, 1)
    }

    func testStartRequestsPresentationWhenRecoveryIsAlreadyNeeded() {
        let coordinator = PermissionRecoveryCoordinator(
            environment: PermissionRecoveryEnvironment(
                snapshot: { self.snapshot(microphone: .denied, accessibility: true) },
                request: { _ in },
                openSystemSettings: { _ in }
            ),
            refreshIntervalNanoseconds: nil
        )
        var presentationRequests = 0
        coordinator.onPresentationRequest = { presentationRequests += 1 }

        coordinator.start()

        XCTAssertEqual(presentationRequests, 1)
    }

    func testPollingPublishesAndStopCancelsFurtherRefresh() async {
        var liveSnapshot = snapshot(microphone: .authorized, accessibility: true)
        let sleeper = ControlledSleeper()
        let coordinator = PermissionRecoveryCoordinator(
            environment: PermissionRecoveryEnvironment(
                snapshot: { liveSnapshot },
                request: { _ in },
                openSystemSettings: { _ in }
            ),
            refreshIntervalNanoseconds: 1,
            sleep: { _ in await sleeper.sleep() }
        )
        var published: [PermissionRecoveryWorkflow.State] = []
        coordinator.onStateChange = { published.append($0) }
        coordinator.start()
        await sleeper.waitUntilSleeping()

        liveSnapshot = snapshot(microphone: .denied, accessibility: true)
        await sleeper.resume()
        await sleeper.waitUntilSleeping()

        XCTAssertEqual(published.map(\.isPresented), [false, true])

        coordinator.stop()
        let countAfterStop = published.count
        await sleeper.resume()
        for _ in 0 ..< 3 {
            await Task.yield()
        }

        XCTAssertEqual(published.count, countAfterStop)
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

private actor ControlledSleeper {
    private var continuation: CheckedContinuation<Void, Never>?
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []

    func sleep() async {
        let waiters = arrivalWaiters
        arrivalWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilSleeping() async {
        if continuation != nil {
            return
        }
        await withCheckedContinuation { arrivalWaiters.append($0) }
    }

    func resume() {
        let pending = continuation
        continuation = nil
        pending?.resume()
    }
}
