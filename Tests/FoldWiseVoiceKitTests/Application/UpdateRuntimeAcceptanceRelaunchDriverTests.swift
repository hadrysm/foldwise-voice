import XCTest
@testable import FoldWiseVoiceKit

final class AcceptanceRelaunchDriverTests: XCTestCase {
    func testImmediateInstallationIsOwnedAndStartedAfterPreparation() throws {
        var events: [String] = []
        let driver = UpdateRuntimeAcceptanceRelaunchDriver()
        let prepare: () throws -> Void = {
            events.append("prepared")
        }

        let isHandled = try driver.beginImmediateInstallation(
            prepare: prepare,
            install: { events.append("install") }
        )

        XCTAssertTrue(isHandled)
        XCTAssertEqual(events, ["prepared", "install"])
    }

    func testRepeatedImmediateInstallationDoesNotStartTwice() {
        var installCount = 0
        let driver = UpdateRuntimeAcceptanceRelaunchDriver()

        let firstIsHandled = driver.beginImmediateInstallation(
            prepare: {},
            install: { installCount += 1 }
        )
        let secondIsHandled = driver.beginImmediateInstallation(
            prepare: {},
            install: { installCount += 1 }
        )

        XCTAssertTrue(firstIsHandled)
        XCTAssertTrue(secondIsHandled)
        XCTAssertEqual(installCount, 1)
    }

    func testTerminationIsRequestedOnlyOnceAfterRelaunchIsPostponed() {
        var requestCount = 0
        let driver = UpdateRuntimeAcceptanceRelaunchDriver()

        driver.requestTerminationOnce { requestCount += 1 }
        driver.requestTerminationOnce { requestCount += 1 }

        XCTAssertEqual(requestCount, 1)
    }

    func testImmediateRelaunchWaitsForDictationBeforeInstallationAndTermination() {
        var events: [String] = []
        let driver = UpdateRuntimeAcceptanceRelaunchDriver()
        let lifecycle = DictationLifecycleCoordinator {
            events.append("tear down")
        }
        let sessionID = UUID()
        lifecycle.sessionDidChange(.started(sessionID))

        let isHandled = driver.beginImmediateInstallation(
            prepare: { events.append("prepared") },
            install: {
                events.append("immediate install")
                let postponed = lifecycle.shouldPostponeRelaunch {
                    events.append("continue install")
                }
                if postponed {
                    driver.requestTerminationOnce {
                        events.append("request termination")
                    }
                }
            }
        )
        let termination = lifecycle.applicationShouldTerminate {
            events.append("reply")
        }

        XCTAssertTrue(isHandled)
        XCTAssertEqual(termination, .terminateLater)
        XCTAssertEqual(
            events,
            ["prepared", "immediate install", "request termination"]
        )

        lifecycle.sessionDidChange(.finished(sessionID))

        XCTAssertEqual(
            events,
            [
                "prepared",
                "immediate install",
                "request termination",
                "continue install",
                "tear down",
                "reply",
            ]
        )
    }
}
