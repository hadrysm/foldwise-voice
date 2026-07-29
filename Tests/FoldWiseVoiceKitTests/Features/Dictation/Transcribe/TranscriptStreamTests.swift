import XCTest
@testable import FoldWiseVoiceKit

/// One live attempt driven through the streaming-manager boundary: snapshot
/// delivery, finish authority, and what a closed attempt refuses to do.
final class TranscriptStreamTests: XCTestCase {
    private var manager = FakeStreamingASRManager()
    private var clock = TestMonotonicClock()

    override func setUp() {
        super.setUp()
        manager = FakeStreamingASRManager()
        clock = TestMonotonicClock()
    }

    func testSnapshotsArriveInReportOrder() async {
        let collected = SnapshotCollector()
        let stream = await openStream()
        stream.deliverSnapshots(to: { collected.append($0) })

        manager.reportTentative("the quick")
        manager.reportTentative("the quick brown")
        manager.reportCommitted("the quick brown")
        manager.reportTentative("the quick brown fox")

        XCTAssertEqual(collected.snapshots, [
            TranscriptSnapshot(committed: "", tentative: "the quick"),
            TranscriptSnapshot(committed: "", tentative: "the quick brown"),
            TranscriptSnapshot(committed: "the quick brown", tentative: ""),
            TranscriptSnapshot(committed: "the quick brown", tentative: " fox"),
        ])
    }

    func testLatestSnapshotIsReadableWithoutAConsumer() async {
        let stream = await openStream()

        manager.reportTentative("the quick brown")

        XCTAssertEqual(stream.snapshot, TranscriptSnapshot(committed: "", tentative: "the quick brown"))
    }

    func testDetachingTheConsumerStopsDelivery() async {
        let collected = SnapshotCollector()
        let stream = await openStream()
        stream.deliverSnapshots(to: { collected.append($0) })
        manager.reportTentative("the quick")

        stream.deliverSnapshots(to: nil)
        manager.reportTentative("the quick brown")

        XCTAssertEqual(collected.snapshots.map(\.text), ["the quick"])
    }

    func testAppendForwardsSamplesToTheEngine() async throws {
        let stream = await openStream()

        try await stream.append([0.1, 0.2])
        try await stream.append([0.3])

        XCTAssertEqual(manager.appended, [[0.1, 0.2], [0.3]])
    }

    func testFinishReturnsTheEnginesFinalAsTheTranscript() async throws {
        manager.finishResult = .success("The quick brown fox.")
        let stream = await openStream()
        manager.reportTentative("the quick brown fox")

        let final = try await stream.finish()

        XCTAssertEqual(final, "The quick brown fox.")
    }

    func testFinishLocksTheFinalAsTheWholeSnapshot() async throws {
        manager.finishResult = .success("The quick brown fox.")
        let collected = SnapshotCollector()
        let stream = await openStream()
        stream.deliverSnapshots(to: { collected.append($0) })
        manager.reportCommitted("the quick")

        _ = try await stream.finish()

        XCTAssertEqual(
            collected.snapshots.last,
            TranscriptSnapshot(committed: "The quick brown fox.", tentative: "")
        )
    }

    func testFinishDrivesTheEngineOnlyOnce() async throws {
        let stream = await openStream()

        _ = try await stream.finish()
        _ = try await stream.finish()

        XCTAssertEqual(manager.events.filter { $0 == .finish }.count, 1)
    }

    func testRepeatedFinishAnswersTheSameTranscript() async throws {
        manager.finishResult = .success("The quick brown fox.")
        let stream = await openStream()
        _ = try await stream.finish()

        let repeated = try await stream.finish()
        XCTAssertEqual(repeated, "The quick brown fox.")
    }

    /// Ending an attempt never touches the engine — the next attempt resets it —
    /// which is what lets an attempt end synchronously.
    func testFinishLeavesTheEngineToTheNextAttempt() async throws {
        let stream = await openStream()

        _ = try await stream.finish()

        XCTAssertEqual(manager.resetCount, 0)
    }

    func testAppendAfterFinishIsRefused() async throws {
        let stream = await openStream()
        _ = try await stream.finish()

        do {
            try await stream.append([0.1])
            XCTFail("A finished attempt must not accept more audio.")
        } catch {
            XCTAssertEqual(error as? TranscriptStreamError, .streamClosed)
        }
    }

    func testReportAfterFinishIsDropped() async throws {
        manager.finishResult = .success("The quick brown fox.")
        let stream = await openStream()
        _ = try await stream.finish()

        manager.reportTentative("something else entirely")

        XCTAssertEqual(stream.snapshot.text, "The quick brown fox.")
    }

    /// The invariant behind a synchronous `cancel()`: an abandoned attempt stops
    /// retaining the engine at once, so the lifecycle is free to replace the model.
    func testCancelledAttemptStopsRetainingTheEngine() async {
        weak var abandoned: FakeStreamingASRManager?
        let stream = await openStreamOverATemporaryEngine { abandoned = $0 }

        stream.cancel()

        XCTAssertNil(abandoned)
    }

    func testCancelKeepsTheConfirmedPrefix() async {
        let stream = await openStream()
        manager.reportCommitted("the quick brown")

        stream.cancel()

        XCTAssertEqual(stream.snapshot.committed, "the quick brown")
    }

    func testFinishAfterCancelIsRefused() async {
        let stream = await openStream()
        stream.cancel()

        do {
            _ = try await stream.finish()
            XCTFail("An abandoned attempt must not produce a transcript.")
        } catch {
            XCTAssertEqual(error as? TranscriptStreamError, .streamClosed)
        }
    }

    func testAppendFailurePropagates() async {
        manager.appendError = StreamFailure()
        let stream = await openStream()

        do {
            try await stream.append([0.1])
            XCTFail("A failing engine must not report success.")
        } catch {
            XCTAssertTrue(error is StreamFailure)
        }
    }

    func testFailedAttemptKeepsReportingTheSameFailure() async throws {
        manager.appendError = StreamFailure()
        let stream = await openStream()
        try? await stream.append([0.1])

        do {
            _ = try await stream.finish()
            XCTFail("A failed attempt must not finalize.")
        } catch {
            XCTAssertTrue(error is StreamFailure)
        }
    }

    func testFailedAttemptLeavesTheConfirmedPrefixForRecovery() async {
        manager.appendError = StreamFailure()
        let stream = await openStream()
        manager.reportCommitted("the quick brown")

        try? await stream.append([0.1])

        XCTAssertEqual(stream.snapshot.committed, "the quick brown")
    }

    func testFinishFailurePropagates() async {
        manager.finishResult = .failure(StreamFailure())
        let stream = await openStream()

        do {
            _ = try await stream.finish()
            XCTFail("A failing finalization must not report a transcript.")
        } catch {
            XCTAssertTrue(error is StreamFailure)
        }
    }

    func testTimingsRecordFirstFeedbackFromTheFirstSample() async throws {
        let stream = await openStream()
        clock.advance(by: .milliseconds(40))
        try await stream.append([0.1])
        clock.advance(by: .milliseconds(900))
        manager.reportTentative("the quick")

        XCTAssertEqual(stream.timings.timeToFirstSnapshot, .milliseconds(900))
    }

    func testTimingsIgnoreReportsWithNoText() async throws {
        let stream = await openStream()
        try await stream.append([0.1])
        clock.advance(by: .milliseconds(500))
        manager.reportTentative("")

        XCTAssertNil(stream.timings.firstSnapshot)
    }

    func testTimingsRecordThePostReleaseFinalizationCost() async throws {
        let clock = clock
        let stream = await openStream()
        try await stream.append([0.1])
        clock.advance(by: .milliseconds(1000))
        // Advancing from inside the engine's own finalization keeps the measured
        // window deterministic instead of racing the test against the task.
        manager.onFinish = { clock.advance(by: .milliseconds(120)) }

        _ = try await stream.finish()

        XCTAssertEqual(stream.timings.finalization, .milliseconds(120))
    }

    func testEmptyChunkIsNotAnEngineCall() async throws {
        let stream = await openStream()

        try await stream.append([])

        XCTAssertEqual(manager.appended, [])
    }

    func testEmptyChunkIsNotTheFirstSampleTheEngineSaw() async throws {
        let stream = await openStream()

        try await stream.append([])

        XCTAssertNil(stream.timings.firstAppend)
    }

    private func openStream() async -> TranscriptStream {
        await TranscriptStream.open(manager: manager, monotonicNow: clock.now)
    }

    /// Opens an attempt over an engine only the attempt retains, so a test can
    /// observe when the attempt lets go of it.
    private func openStreamOverATemporaryEngine(
        _ capture: (FakeStreamingASRManager) -> Void
    ) async -> TranscriptStream {
        let engine = FakeStreamingASRManager()
        capture(engine)
        return await TranscriptStream.open(manager: engine, monotonicNow: clock.now)
    }
}

private struct StreamFailure: Error {}
