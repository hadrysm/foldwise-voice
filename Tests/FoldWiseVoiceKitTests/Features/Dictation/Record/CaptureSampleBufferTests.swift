import XCTest
@testable import FoldWiseVoiceKit

/// Holds the deliveries a `CaptureSampleBuffer` schedules so a test can run
/// them at an exact point, standing in for the production serial queue.
private final class ManualDelivery {
    private var scheduled: [() -> Void] = []

    var schedule: (@escaping () -> Void) -> Void {
        { [self] item in scheduled.append(item) }
    }

    var isEmpty: Bool {
        scheduled.isEmpty
    }

    func run() {
        while !scheduled.isEmpty {
            scheduled.removeFirst()()
        }
    }
}

/// What a finished session hands back versus what its consumer saw, so the
/// boundary reads as one assertion.
private struct FinishBoundary: Equatable {
    let retained: [Float]?
    let delivered: [[Float]]
}

final class CaptureSampleBufferTests: XCTestCase {
    func testConsumerReceivesChunksInCaptureOrder() {
        let delivery = ManualDelivery()
        let buffer = CaptureSampleBuffer(schedule: delivery.schedule)
        var received: [[Float]] = []
        buffer.deliver(to: { received.append($0) })

        buffer.append([0.1, 0.2], level: 0.2)
        buffer.append([0.3], level: 0.3)
        delivery.run()

        XCTAssertEqual(received, [[0.1, 0.2], [0.3]])
    }

    func testDeliveredChunksConcatenateToTheRetainedBuffer() throws {
        let delivery = ManualDelivery()
        let buffer = CaptureSampleBuffer(schedule: delivery.schedule)
        var received: [[Float]] = []
        buffer.deliver(to: { received.append($0) })

        buffer.append([0.1, 0.2], level: 0.2)
        buffer.append([0.3], level: 0.3)
        buffer.append([0.4, 0.5], level: 0.5)
        delivery.run()

        XCTAssertEqual(try XCTUnwrap(buffer.finish()), received.flatMap { $0 })
    }

    func testAppendingWithoutAConsumerSchedulesNoDelivery() {
        let delivery = ManualDelivery()
        let buffer = CaptureSampleBuffer(schedule: delivery.schedule)

        buffer.append([0.1], level: 0.1)
        buffer.append([0.2], level: 0.2)

        XCTAssertTrue(delivery.isEmpty)
    }

    func testRetainedBufferIsIndependentOfIncrementalDelivery() {
        let delivery = ManualDelivery()
        let buffer = CaptureSampleBuffer(schedule: delivery.schedule)

        buffer.append([0.1], level: 0.1)
        buffer.append([0.2, 0.3], level: 0.3)

        XCTAssertEqual(buffer.finish(), [0.1, 0.2, 0.3])
    }

    func testRetainedBufferIsHandedBackOnlyOnce() {
        let buffer = CaptureSampleBuffer(schedule: ManualDelivery().schedule)
        buffer.append([0.1], level: 0.1)

        XCTAssertEqual(buffer.finish(), [0.1])
        XCTAssertNil(buffer.finish())
    }

    func testChunksAcceptedAfterTheSessionFinishesAreNeverDelivered() {
        let delivery = ManualDelivery()
        let buffer = CaptureSampleBuffer(schedule: delivery.schedule)
        var received: [[Float]] = []
        buffer.deliver(to: { received.append($0) })
        buffer.finish()

        buffer.append([0.1], level: 0.1)
        delivery.run()

        XCTAssertEqual(received, [])
    }

    func testPendingChunksAreRepresentedInTheRetainedBufferInsteadOfBeingDelivered() {
        let delivery = ManualDelivery()
        let buffer = CaptureSampleBuffer(schedule: delivery.schedule)
        var received: [[Float]] = []
        buffer.deliver(to: { received.append($0) })
        buffer.append([0.1, 0.2], level: 0.2)

        let retained = buffer.finish()
        delivery.run()

        XCTAssertEqual(
            FinishBoundary(retained: retained, delivered: received),
            FinishBoundary(retained: [0.1, 0.2], delivered: [])
        )
    }

    func testDetachingTheConsumerStopsFurtherDelivery() {
        let delivery = ManualDelivery()
        let buffer = CaptureSampleBuffer(schedule: delivery.schedule)
        var received: [[Float]] = []
        buffer.deliver(to: { received.append($0) })
        buffer.append([0.1], level: 0.1)
        delivery.run()

        buffer.deliver(to: nil)
        buffer.append([0.2], level: 0.2)
        delivery.run()

        XCTAssertEqual(received, [[0.1]])
    }

    func testLevelFollowsTheLatestChunk() {
        let buffer = CaptureSampleBuffer(schedule: ManualDelivery().schedule)

        buffer.append([0.1], level: 0.3)
        buffer.append([0.2], level: 0.5)

        XCTAssertEqual(buffer.level, 0.5)
    }

    func testLevelResetsWhenTheSessionFinishes() {
        let buffer = CaptureSampleBuffer(schedule: ManualDelivery().schedule)
        buffer.append([0.1], level: 0.5)

        buffer.finish()

        XCTAssertEqual(buffer.level, 0)
    }

    /// A configuration change replaces the engine, converter, and tap around this
    /// buffer (`AVAudioCaptureSession.rebuildAndRestartEngine`), so a chunk can be
    /// captured while no delivery is running. Recovery must neither lose it nor
    /// reorder it behind the chunks captured after the rebuild.
    func testDeliveryInterruptedByAnEngineRebuildResumesInOrder() {
        let delivery = ManualDelivery()
        let buffer = CaptureSampleBuffer(schedule: delivery.schedule)
        var received: [[Float]] = []
        buffer.deliver(to: { received.append($0) })
        buffer.append([0.1], level: 0.1)
        delivery.run()

        buffer.append([0.2], level: 0.2)
        buffer.append([0.3], level: 0.3)
        delivery.run()

        XCTAssertEqual(received, [[0.1], [0.2], [0.3]])
    }

    func testRetainedBufferSurvivesAnEngineRebuild() throws {
        let delivery = ManualDelivery()
        let buffer = CaptureSampleBuffer(schedule: delivery.schedule)
        buffer.deliver(to: { _ in })
        buffer.append([0.1], level: 0.1)
        delivery.run()

        buffer.append([0.2], level: 0.2)

        XCTAssertEqual(try XCTUnwrap(buffer.finish()), [0.1, 0.2])
    }

    func testReentrantAppendFromTheConsumerStaysOrdered() {
        let delivery = ManualDelivery()
        let buffer = CaptureSampleBuffer(schedule: delivery.schedule)
        var received: [[Float]] = []
        buffer.deliver(to: { [weak buffer] chunk in
            received.append(chunk)
            if received.count == 1 {
                buffer?.append([0.9], level: 0.9)
            }
        })

        buffer.append([0.1], level: 0.1)
        delivery.run()

        XCTAssertEqual(received, [[0.1], [0.9]])
    }

    func testConsumerReadsTheBufferWithoutDeadlockingOnDelivery() {
        let buffer = CaptureSampleBuffer(
            schedule: { DispatchQueue.global().async(execute: $0) }
        )
        let delivered = expectation(description: "chunk delivered")
        var levelInsideConsumer: Float?
        buffer.deliver(to: { [weak buffer] _ in
            levelInsideConsumer = buffer?.level
            delivered.fulfill()
        })

        buffer.append([0.4], level: 0.4)

        wait(for: [delivered], timeout: 1)
        XCTAssertEqual(levelInsideConsumer, 0.4)
    }

    func testSlowConsumerDoesNotBlockTheCaptureCallback() {
        let buffer = CaptureSampleBuffer(
            schedule: { DispatchQueue.global().async(execute: $0) }
        )
        let firstDelivery = DispatchSemaphore(value: 0)
        let releaseConsumer = DispatchSemaphore(value: 0)
        let bothDelivered = expectation(description: "both chunks delivered")
        var received: [[Float]] = []
        buffer.deliver(to: { chunk in
            received.append(chunk)
            switch received.count {
            case 1:
                firstDelivery.signal()
                releaseConsumer.wait()
            case 2:
                bothDelivered.fulfill()
            default:
                XCTFail("Unexpected chunk delivery: \(chunk)")
            }
        })

        buffer.append([0.1], level: 0.1)
        XCTAssertEqual(firstDelivery.wait(timeout: .now() + 1), .success)
        let appendReturned = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            buffer.append([0.2], level: 0.2)
            appendReturned.signal()
        }

        XCTAssertEqual(appendReturned.wait(timeout: .now() + 1), .success)
        releaseConsumer.signal()

        wait(for: [bothDelivered], timeout: 1)
        XCTAssertEqual(received, [[0.1], [0.2]])
    }
}
