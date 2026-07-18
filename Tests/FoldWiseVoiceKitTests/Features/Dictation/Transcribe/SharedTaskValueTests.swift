import XCTest
@testable import FoldWiseVoiceKit

final class SharedTaskValueTests: XCTestCase {
    func testCancelledWaiterLeavesSharedTaskRunningForAnotherWaiter() async throws {
        let (stream, continuation) = AsyncStream.makeStream(of: Int.self)
        let shared = Task<Int, Error> {
            for await value in stream {
                return value
            }
            throw CancellationError()
        }
        let (registrationEvents, registrationContinuation) = AsyncStream.makeStream(of: Void.self)
        let cancelledWaiter = Task {
            try await SharedTaskValue.wait(for: shared) {
                registrationContinuation.yield()
            }
        }
        let remainingWaiter = Task { try await SharedTaskValue.wait(for: shared) }

        for await _ in registrationEvents {
            break
        }
        registrationContinuation.finish()
        cancelledWaiter.cancel()
        let cancelledResult = await cancelledWaiter.result
        continuation.yield(42)
        continuation.finish()

        let remainingResult = await remainingWaiter.result
        XCTAssertEqual(
            [cancelledResult.isWaiterCancellation ? "cancelled" : "completed",
             try remainingResult.get().description],
            ["cancelled", "42"]
        )
    }

    func testCancelledExclusiveWaiterWaitsForSharedTaskTeardown() async {
        let events = SharedTaskEventLog()
        let (loadLifetime, loadLifetimeContinuation) = AsyncStream.makeStream(of: Void.self)
        let (cleanupGate, cleanupContinuation) = AsyncStream.makeStream(of: Void.self)
        let (started, startedContinuation) = AsyncStream.makeStream(of: Void.self)
        let shared = Task<Int, Error> {
            startedContinuation.yield()
            startedContinuation.finish()
            for await _ in loadLifetime {}
            await events.append("load-cancelled")
            for await _ in cleanupGate {
                break
            }
            await events.append("load-released")
            throw ExclusiveLoadFailure()
        }
        for await _ in started {
            break
        }
        let waiter = Task {
            do {
                _ = try await SharedTaskValue.waitExclusively(for: shared)
            } catch is CancellationError {
                await events.append("prepare-cancelled")
            } catch {
                await events.append("prepare-failed")
            }
        }

        waiter.cancel()
        cleanupContinuation.yield()
        cleanupContinuation.finish()
        await waiter.value
        loadLifetimeContinuation.finish()
        let recordedEvents = await events.values

        XCTAssertEqual(
            recordedEvents,
            ["load-cancelled", "load-released", "prepare-cancelled"]
        )
    }
}

private struct ExclusiveLoadFailure: Error {}

private actor SharedTaskEventLog {
    private(set) var values: [String] = []

    func append(_ event: String) {
        values.append(event)
    }
}

private extension Result where Failure == Error {
    var isWaiterCancellation: Bool {
        guard case let .failure(error) = self else { return false }
        guard let waitError = error as? SharedTaskValue.WaitError else { return false }
        if case .waiterCancelled = waitError { return true }
        return false
    }
}
