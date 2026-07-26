import AppKit
import XCTest
@testable import FoldWiseVoiceKit

final class ApplicationRunLoopTests: XCTestCase {
    @MainActor
    func testHandlerCompletesDeferredTerminationWhileModalPanelModeIsRunning() {
        var events: [String] = []
        let coordinator = DictationLifecycleCoordinator {
            events.append("tear down")
        }
        let sessionID = UUID()
        coordinator.sessionDidChange(.started(sessionID))
        _ = coordinator.applicationShouldTerminate {
            events.append("reply")
        }
        let handleSessionEvent = ApplicationRunLoop.handler {
            coordinator.sessionDidChange($0)
            CFRunLoopStop(CFRunLoopGetMain())
        }
        let didSchedule = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            handleSessionEvent(.finished(sessionID))
            didSchedule.signal()
        }
        XCTAssertEqual(didSchedule.wait(timeout: .now() + 1), .success)

        _ = RunLoop.main.run(
            mode: .modalPanel,
            before: Date(timeIntervalSinceNow: 1)
        )

        XCTAssertEqual(events, ["tear down", "reply"])
    }
}
