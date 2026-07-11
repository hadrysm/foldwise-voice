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
}

private extension Result where Failure == Error {
    var isWaiterCancellation: Bool {
        guard case let .failure(error) = self else { return false }
        guard let waitError = error as? SharedTaskValue.WaitError else { return false }
        if case .waiterCancelled = waitError { return true }
        return false
    }
}
