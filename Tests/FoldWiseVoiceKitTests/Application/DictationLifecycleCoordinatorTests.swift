import XCTest
@testable import FoldWiseVoiceKit

final class DictationLifecycleCoordinatorTests: XCTestCase {
    func testQuitWithoutActiveSessionReturnsTerminateNow() {
        let coordinator = DictationLifecycleCoordinator(tearDown: {})

        let decision = coordinator.applicationShouldTerminate(reply: {})

        XCTAssertEqual(decision, .terminateNow)
    }

    func testQuitDuringActiveSessionReturnsTerminateLater() {
        let coordinator = DictationLifecycleCoordinator(tearDown: {})
        startSession(on: coordinator)

        let decision = coordinator.applicationShouldTerminate(reply: {})

        XCTAssertEqual(decision, .terminateLater)
    }

    func testDeferredQuitTearsDownAndRepliesAfterSessionFinishes() {
        var events: [String] = []
        let coordinator = DictationLifecycleCoordinator {
            events.append("tear down")
        }
        let sessionID = startSession(on: coordinator)
        _ = coordinator.applicationShouldTerminate {
            events.append("reply")
        }

        coordinator.sessionDidChange(.finished(sessionID))

        XCTAssertEqual(events, ["tear down", "reply"])
    }

    func testRelaunchDuringActiveSessionContinuesAfterSessionFinishes() {
        var events: [String] = []
        let coordinator = DictationLifecycleCoordinator(tearDown: {})
        let sessionID = startSession(on: coordinator)
        let postponed = coordinator.shouldPostponeRelaunch {
            events.append("install")
        }
        events.append(postponed ? "postponed" : "continued")

        coordinator.sessionDidChange(.finished(sessionID))

        XCTAssertEqual(events, ["postponed", "install"])
    }

    func testUnmatchedFinishWithoutPendingRequestDoesNotTearDown() {
        var tearDownCount = 0
        let coordinator = DictationLifecycleCoordinator {
            tearDownCount += 1
        }

        coordinator.sessionDidChange(.finished(UUID()))

        XCTAssertEqual(tearDownCount, 0)
    }

    func testRelaunchWithoutActiveSessionContinuesWithoutInvokingHandler() {
        var events: [String] = []
        let coordinator = DictationLifecycleCoordinator(tearDown: {})

        let postponed = coordinator.shouldPostponeRelaunch {
            events.append("install")
        }
        events.append(postponed ? "postponed" : "continued")

        XCTAssertEqual(events, ["continued"])
    }

    func testOverlappingRequestsReleaseEachActionExactlyOnce() {
        var events: [String] = []
        let coordinator = DictationLifecycleCoordinator {
            events.append("tear down")
        }
        let sessionID = startSession(on: coordinator)
        _ = coordinator.shouldPostponeRelaunch {
            events.append("install")
        }
        _ = coordinator.applicationShouldTerminate {
            events.append("reply")
        }

        coordinator.sessionDidChange(.finished(sessionID))
        coordinator.sessionDidChange(.finished(sessionID))

        XCTAssertEqual(events, ["install", "tear down", "reply"])
    }

    func testRepeatedImmediateQuitTearsDownExactlyOnce() {
        var tearDownCount = 0
        let coordinator = DictationLifecycleCoordinator {
            tearDownCount += 1
        }

        _ = coordinator.applicationShouldTerminate(reply: {})
        _ = coordinator.applicationShouldTerminate(reply: {})

        XCTAssertEqual(tearDownCount, 1)
    }

    func testQueuedSessionsReleaseQuitOnlyAfterBothFinish() {
        var events: [String] = []
        let coordinator = DictationLifecycleCoordinator {
            events.append("tear down")
        }
        let firstID = startSession(on: coordinator)
        let secondID = startSession(on: coordinator)
        _ = coordinator.applicationShouldTerminate {
            events.append("reply")
        }

        coordinator.sessionDidChange(.finished(firstID))
        events.append("first complete")
        coordinator.sessionDidChange(.finished(secondID))

        XCTAssertEqual(events, ["first complete", "tear down", "reply"])
    }

    func testRepeatedRelaunchRequestsInvokeOnlyFirstHandler() {
        var events: [String] = []
        let coordinator = DictationLifecycleCoordinator(tearDown: {})
        let sessionID = startSession(on: coordinator)
        _ = coordinator.shouldPostponeRelaunch {
            events.append("first")
        }
        _ = coordinator.shouldPostponeRelaunch {
            events.append("second")
        }

        coordinator.sessionDidChange(.finished(sessionID))

        XCTAssertEqual(events, ["first"])
    }

    func testRepeatedQuitRequestsReplyAndTearDownOnce() {
        var events: [String] = []
        let coordinator = DictationLifecycleCoordinator {
            events.append("tear down")
        }
        let sessionID = startSession(on: coordinator)
        _ = coordinator.applicationShouldTerminate {
            events.append("first reply")
        }
        _ = coordinator.applicationShouldTerminate {
            events.append("second reply")
        }

        coordinator.sessionDidChange(.finished(sessionID))

        XCTAssertEqual(events, ["tear down", "first reply"])
    }

    @discardableResult
    private func startSession(
        on coordinator: DictationLifecycleCoordinator,
        id: UUID = UUID()
    ) -> UUID {
        coordinator.sessionDidChange(.started(id))
        return id
    }
}
