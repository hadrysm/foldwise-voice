import XCTest
@testable import FoldWiseVoiceKit

final class AudioCaptureRecoveryCoordinatorTests: XCTestCase {
    private enum StubError: Error {
        case failed
    }

    func testRepeatedConfigurationChangeWhileRecoveringIsCoalesced() {
        let recoveryEntered = expectation(description: "recovery entered")
        let recoveryFinished = expectation(description: "recovery finished")
        let duplicateRecovery = expectation(description: "duplicate recovery")
        duplicateRecovery.isInverted = true
        let releaseRecovery = DispatchSemaphore(value: 0)
        let coordinator = AudioCaptureRecoveryCoordinator()

        coordinator.configurationChanged(
            recover: {
                recoveryEntered.fulfill()
                releaseRecovery.wait()
                recoveryFinished.fulfill()
            },
            onFailure: {}
        )
        wait(for: [recoveryEntered], timeout: 0.2)

        coordinator.configurationChanged(
            recover: { duplicateRecovery.fulfill() }, onFailure: {}
        )
        releaseRecovery.signal()
        wait(for: [recoveryFinished, duplicateRecovery], timeout: 0.1)
    }

    func testFailedRecoveryReportsFailureOnce() {
        let failed = expectation(description: "capture failed")
        let duplicateRecovery = expectation(description: "duplicate recovery")
        duplicateRecovery.isInverted = true
        let duplicateFailure = expectation(description: "duplicate failure")
        duplicateFailure.isInverted = true
        let coordinator = AudioCaptureRecoveryCoordinator()

        coordinator.configurationChanged(
            recover: { throw StubError.failed },
            onFailure: { failed.fulfill() }
        )
        wait(for: [failed], timeout: 0.2)

        coordinator.configurationChanged(
            recover: { duplicateRecovery.fulfill() },
            onFailure: { duplicateFailure.fulfill() }
        )
        wait(for: [duplicateRecovery, duplicateFailure], timeout: 0.1)
    }

    func testFailedStartupCancelsQueuedRecovery() {
        let startupEntered = expectation(description: "startup entered")
        let startupFinished = expectation(description: "startup finished")
        let recovery = expectation(description: "capture recovery")
        recovery.isInverted = true
        let releaseStartup = DispatchSemaphore(value: 0)
        let coordinator = AudioCaptureRecoveryCoordinator()

        DispatchQueue.global().async {
            do {
                try coordinator.start {
                    startupEntered.fulfill()
                    releaseStartup.wait()
                    throw StubError.failed
                }
                XCTFail("startup should fail")
            } catch {}
            startupFinished.fulfill()
        }
        wait(for: [startupEntered], timeout: 0.2)

        coordinator.configurationChanged(
            recover: { recovery.fulfill() }, onFailure: {}
        )
        releaseStartup.signal()
        wait(for: [startupFinished, recovery], timeout: 0.1)
    }

    func testStopWaitsForRecoveryThenShutsDownAndIgnoresLaterChanges() {
        let recoveryEntered = expectation(description: "recovery entered")
        let stopped = expectation(description: "capture stopped")
        let laterRecovery = expectation(description: "later recovery")
        laterRecovery.isInverted = true
        let releaseRecovery = DispatchSemaphore(value: 0)
        let orderLock = NSLock()
        var order: [String] = []
        let coordinator = AudioCaptureRecoveryCoordinator()

        coordinator.configurationChanged(
            recover: {
                orderLock.withLock { order.append("recover") }
                recoveryEntered.fulfill()
                releaseRecovery.wait()
                orderLock.withLock { order.append("recovered") }
            },
            onFailure: {}
        )
        wait(for: [recoveryEntered], timeout: 0.2)

        DispatchQueue.global().async {
            coordinator.stop {
                orderLock.withLock { order.append("shutdown") }
                stopped.fulfill()
            }
        }
        releaseRecovery.signal()
        wait(for: [stopped], timeout: 0.2)
        coordinator.configurationChanged(
            recover: { laterRecovery.fulfill() }, onFailure: {}
        )
        wait(for: [laterRecovery], timeout: 0.1)

        XCTAssertEqual(
            orderLock.withLock { order }, ["recover", "recovered", "shutdown"]
        )
    }

    func testConfigurationRecoveryWaitsForStartupToFinish() {
        let startupEntered = expectation(description: "startup entered")
        let recovered = expectation(description: "capture recovered")
        let releaseStartup = DispatchSemaphore(value: 0)
        let orderLock = NSLock()
        var order: [String] = []
        let coordinator = AudioCaptureRecoveryCoordinator()

        DispatchQueue.global().async {
            try? coordinator.start {
                orderLock.withLock { order.append("start") }
                startupEntered.fulfill()
                releaseStartup.wait()
                orderLock.withLock { order.append("started") }
            }
        }
        wait(for: [startupEntered], timeout: 0.2)

        coordinator.configurationChanged(
            recover: {
                orderLock.withLock { order.append("recover") }
                recovered.fulfill()
            },
            onFailure: {}
        )
        releaseStartup.signal()
        wait(for: [recovered], timeout: 0.2)

        XCTAssertEqual(orderLock.withLock { order }, ["start", "started", "recover"])
    }

    func testConfigurationChangeRecoversWithoutReportingFailure() {
        let recovered = expectation(description: "capture recovered")
        let failed = expectation(description: "capture failed")
        failed.isInverted = true
        let coordinator = AudioCaptureRecoveryCoordinator()

        coordinator.configurationChanged(
            recover: { recovered.fulfill() },
            onFailure: { failed.fulfill() }
        )

        wait(for: [recovered, failed], timeout: 0.2)
    }
}

private extension NSLocking {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
