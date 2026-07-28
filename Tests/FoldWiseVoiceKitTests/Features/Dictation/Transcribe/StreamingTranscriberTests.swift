import XCTest
@testable import FoldWiseVoiceKit

/// A Streaming ASR model's engine: one resident manager, one attempt at a time,
/// and a batch call that re-feeds rather than running a second authority.
final class StreamingTranscriberTests: XCTestCase {
    private var manager = FakeStreamingASRManager()
    private var clock = TestMonotonicClock()

    override func setUp() {
        super.setUp()
        manager = FakeStreamingASRManager()
        clock = TestMonotonicClock()
    }

    func testPrepareLoadsTheModelOnce() async throws {
        let engine = makeEngine()

        try await engine.prepare()
        try await engine.prepare()

        XCTAssertEqual(manager.loadCount, 1)
    }

    func testFailedPreparationCanBeRetried() async throws {
        manager.loadError = StreamingEngineFailure()
        let engine = makeEngine()
        try? await engine.prepare()
        manager.loadError = nil

        try await engine.prepare()

        XCTAssertEqual(manager.loadCount, 2)
    }

    func testPreparationFailurePropagates() async {
        manager.loadError = StreamingEngineFailure()
        let engine = makeEngine()

        do {
            try await engine.prepare()
            XCTFail("An engine that cannot load must not report readiness.")
        } catch {
            XCTAssertTrue(error is StreamingEngineFailure)
        }
    }

    func testAttemptStartsFromAResetEngine() async throws {
        let engine = makeEngine()

        _ = try await engine.makeStream()

        XCTAssertEqual(manager.events, [.load, .reset, .observe])
    }

    func testAttemptsShareTheLoadedModel() async throws {
        let engine = makeEngine()

        _ = try await engine.makeStream()
        _ = try await engine.makeStream()

        XCTAssertEqual(manager.loadCount, 1)
    }

    func testNewAttemptAbandonsTheOpenOne() async throws {
        let engine = makeEngine()
        let first = try await engine.makeStream()

        _ = try await engine.makeStream()

        do {
            _ = try await first.finish()
            XCTFail("An abandoned attempt must not finalize.")
        } catch {
            XCTAssertEqual(error as? TranscriptStreamError, .streamClosed)
        }
    }

    func testStreamPublishesTheEnginesReports() async throws {
        let collected = SnapshotCollector()
        let engine = makeEngine()
        let stream = try await engine.makeStream()
        stream.deliverSnapshots(to: { collected.append($0) })

        manager.reportTentative("the quick brown")

        XCTAssertEqual(collected.snapshots.map(\.text), ["the quick brown"])
    }

    func testBatchTranscribeRefeedsTheWholeBufferThroughAFreshAttempt() async throws {
        manager.finishResult = .success("The quick brown fox.")
        let engine = makeEngine()

        let text = try await engine.transcribe([0.1, 0.2, 0.3])

        XCTAssertEqual(text, "The quick brown fox.")
    }

    func testBatchTranscribeFeedsTheWholeBufferInOneGo() async throws {
        let engine = makeEngine()

        _ = try await engine.transcribe([0.1, 0.2, 0.3])

        XCTAssertEqual(manager.appended, [[0.1, 0.2, 0.3]])
    }

    func testEngineStaysUsableAfterAFailedRefeed() async throws {
        manager.appendError = StreamingEngineFailure()
        manager.finishResult = .success("The quick brown fox.")
        let engine = makeEngine()
        _ = try? await engine.transcribe([0.1])
        manager.appendError = nil

        let text = try await engine.transcribe([0.1])

        XCTAssertEqual(text, "The quick brown fox.")
    }

    func testBatchTranscribeFailurePropagates() async {
        manager.finishResult = .failure(StreamingEngineFailure())
        let engine = makeEngine()

        do {
            _ = try await engine.transcribe([0.1])
            XCTFail("A failed re-feed must not report a transcript.")
        } catch {
            XCTAssertTrue(error is StreamingEngineFailure)
        }
    }

    func testEngineDeclaresItsStreamingCapabilityInItsType() {
        XCTAssertTrue(makeEngine() as any Transcribing is any StreamCapableTranscribing)
    }

    private func makeEngine() -> StreamingTranscriber {
        let manager = manager
        return StreamingTranscriber(makeManager: { manager }, monotonicNow: clock.now)
    }
}

private struct StreamingEngineFailure: Error {}
