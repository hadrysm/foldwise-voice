// A Dictation session whose Effective ASR model streams (ADR-0009): the stream's
// own final is the raw transcript Polish, History, and the single insertion
// consume, and a broken stream recovers from the buffer the recorder retained.
//
// Only the FluidAudio streaming manager is faked. The ASR lifecycle, the captured
// session handle, and the live attempt are the real ones, so what these tests pin
// is the path a shipped Streaming ASR model will take.

import XCTest
@testable import FoldWiseVoiceKit

private struct StreamFailure: Error {}

private struct EngineCallCounts: Equatable {
    let resets: Int
    let finishes: Int
}

final class PipelineStreamingSessionTests: XCTestCase {
    private let polishMode = Mode(
        name: "Clean",
        asrModel: "",
        llmModel: "qwen2.5:3b",
        systemPrompt: nil,
        vocab: []
    )
    private let longEnoughToPolish =
        "this transcript is unquestionably longer than the forty character polish threshold"

    // MARK: - the stream is the authority

    func testStreamingSessionInsertsTheFinalFromItsOwnStream() async throws {
        let harness = await makeHarness()
        harness.manager.finishResult = .success("the quick brown fox")

        try await harness.record(chunks: [FakeRecorder.speech(seconds: 0.5)])

        XCTAssertEqual(harness.inserted.texts, ["the quick brown fox"])
    }

    func testHealthyStreamingSessionTranscribesTheBufferOnlyOnce() async throws {
        let harness = await makeHarness()
        harness.manager.finishResult = .success("the quick brown fox")

        try await harness.record(chunks: [FakeRecorder.speech(seconds: 0.5)])

        XCTAssertEqual(
            EngineCallCounts(
                resets: harness.manager.resetCount,
                finishes: harness.manager.finishCount
            ),
            EngineCallCounts(resets: 1, finishes: 1)
        )
    }

    func testStreamingSessionAppendsCapturedChunksInOrder() async throws {
        let harness = await makeHarness()
        let first = FakeRecorder.speech(seconds: 0.2, amplitude: 0.1)
        let second = FakeRecorder.speech(seconds: 0.2, amplitude: 0.2)

        try await harness.record(chunks: [first, second])

        XCTAssertEqual(harness.manager.appended, [first, second])
    }

    func testStreamingSessionPolishesItsStreamFinal() async throws {
        let harness = await makeHarness(mode: polishMode)
        harness.manager.finishResult = .success(longEnoughToPolish)

        try await harness.record(chunks: [FakeRecorder.speech(seconds: 0.5)])

        XCTAssertEqual(harness.inserted.texts, ["polished: \(longEnoughToPolish)"])
    }

    func testStreamingSessionRecordsItsStreamFinalAsTheRawTranscript() async throws {
        let harness = await makeHarness(mode: polishMode)
        harness.manager.finishResult = .success(longEnoughToPolish)

        try await harness.record(chunks: [FakeRecorder.speech(seconds: 0.5)])

        XCTAssertEqual(harness.recorded.entries.map(\.rawText), [longEnoughToPolish])
    }

    func testStreamingSessionEmitsTheUnchangedProgressStateSequence() async throws {
        let harness = await makeHarness()
        harness.manager.finishResult = .success("the quick brown fox")

        try await harness.record(chunks: [FakeRecorder.speech(seconds: 0.5)]) { manager in
            for word in ["the", "the quick", "the quick brown", "the quick brown fox"] {
                manager.reportTentative(word)
            }
        }

        XCTAssertEqual(
            harness.states.states,
            [.listening(mode: "Voice to Text"), .transcribing, .inserted]
        )
    }

    // MARK: - the snapshot observer

    func testLiveSnapshotsCarryTheirDictationSessionID() async throws {
        let harness = await makeHarness()
        harness.manager.finishResult = .success("the quick brown fox")

        try await harness.record(chunks: [FakeRecorder.speech(seconds: 0.5)]) { manager in
            manager.reportTentative("the quick")
        }

        let live = harness.transcripts.events.filter { $0.phase == .live }
        XCTAssertEqual(live.map(\.dictationSessionID), [harness.startedSessionIDs.first])
    }

    func testLiveSnapshotsSeparateCommittedTextFromTheTentativeTail() async throws {
        let harness = await makeHarness()
        harness.manager.finishResult = .success("the quick brown fox")

        try await harness.record(chunks: [FakeRecorder.speech(seconds: 0.5)]) { manager in
            manager.reportCommitted("the quick ")
            manager.reportTentative("the quick brown")
        }

        let live = harness.transcripts.events.filter { $0.phase == .live }
        XCTAssertEqual(live.map(\.snapshot), [
            TranscriptSnapshot(committed: "the quick ", tentative: ""),
            TranscriptSnapshot(committed: "the quick ", tentative: "brown"),
        ])
    }

    func testHotkeyReleaseLocksTheLastLiveSnapshot() async throws {
        let harness = await makeHarness()
        harness.manager.finishResult = .success("the quick brown fox")

        try await harness.record(chunks: [FakeRecorder.speech(seconds: 0.5)]) { manager in
            manager.reportTentative("the quick")
        }

        XCTAssertEqual(
            harness.transcripts.events.filter { $0.phase == .locked }.map(\.snapshot.text),
            ["the quick", "the quick brown fox"]
        )
    }

    func testRecognitionAfterHotkeyReleaseDoesNotRewriteTheLockedText() async throws {
        let harness = await makeHarness()
        harness.manager.finishResult = .success("the quick brown fox")
        harness.manager.onFinish = { [manager = harness.manager] in
            manager.reportTentative("something else entirely")
        }

        try await harness.record(chunks: [FakeRecorder.speech(seconds: 0.5)]) { manager in
            manager.reportTentative("the quick")
        }

        XCTAssertEqual(
            harness.transcripts.events.map(\.snapshot.text),
            ["the quick", "the quick", "the quick brown fox"]
        )
    }

    func testHotkeyReleaseDetachesIncrementalDelivery() async throws {
        let harness = await makeHarness()
        harness.manager.finishResult = .success("the quick brown fox")

        try await harness.record(chunks: [FakeRecorder.speech(seconds: 0.5)])

        XCTAssertFalse(harness.recorder.deliversSamples)
    }

    // MARK: - recovery

    func testBrokenStreamRecoversThroughAFreshStream() async throws {
        let harness = await makeHarness()
        harness.failFinalizations(1, thenSucceedWith: "recovered sentence")

        try await harness.record(chunks: [FakeRecorder.speech(seconds: 0.5)]) { manager in
            manager.reportCommitted("truncated ")
        }

        XCTAssertEqual(harness.inserted.texts, ["recovered sentence"])
    }

    func testRecoveryRefeedsTheWholeRetainedBuffer() async throws {
        let harness = await makeHarness()
        harness.failFinalizations(1, thenSucceedWith: "recovered sentence")
        let first = FakeRecorder.speech(seconds: 0.2, amplitude: 0.1)
        let second = FakeRecorder.speech(seconds: 0.2, amplitude: 0.2)

        try await harness.record(chunks: [first, second])

        XCTAssertEqual(harness.manager.appended.last, first + second)
    }

    func testStreamLostDuringCaptureStillRecoversByRefeed() async throws {
        let harness = await makeHarness()
        harness.manager.finishResult = .success("recovered sentence")
        harness.manager.appendError = StreamFailure()
        harness.manager.onAppend = { [manager = harness.manager] in
            manager.appendError = nil
        }

        try await harness.record(chunks: [FakeRecorder.speech(seconds: 0.5)])

        XCTAssertEqual(harness.inserted.texts, ["recovered sentence"])
    }

    func testSecondFailureFallsBackToTheConfirmedPrefix() async throws {
        let harness = await makeHarness()
        harness.manager.finishResult = .failure(StreamFailure())

        try await harness.record(chunks: [FakeRecorder.speech(seconds: 0.5)]) { manager in
            manager.reportCommitted("the quick brown ")
            manager.reportTentative("the quick brown fo")
        }

        XCTAssertEqual(harness.inserted.texts, ["the quick brown "])
    }

    func testSecondFailureWithoutAConfirmedPrefixReportsRecognitionFailure() async throws {
        let harness = await makeHarness()
        harness.manager.finishResult = .failure(StreamFailure())

        try await harness.record(chunks: [FakeRecorder.speech(seconds: 0.5)]) { manager in
            manager.reportTentative("nothing committed yet")
        }

        guard case .error = harness.states.states.last else {
            return XCTFail("A twice-failed session with no confirmed prefix must report failure.")
        }
        XCTAssertTrue(harness.inserted.texts.isEmpty)
    }

    // MARK: - one driver per loaded engine

    func testOverlappingSessionRecordsWithoutLiveSnapshots() async throws {
        let harness = await makeHarness()
        let overlap = try await harness.recordOverlappingSession()

        XCTAssertEqual(
            Set(harness.transcripts.events.map(\.dictationSessionID)),
            [overlap.first]
        )
    }

    func testOverlappingSessionsInsertInOrder() async throws {
        let harness = await makeHarness()
        _ = try await harness.recordOverlappingSession()

        XCTAssertEqual(harness.inserted.texts, ["first session", "second session"])
    }

    func testOverlappingSessionResolvesByRefeedingItsOwnBuffer() async throws {
        let harness = await makeHarness()
        _ = try await harness.recordOverlappingSession()

        XCTAssertEqual(harness.manager.appended.last, harness.recorder.samples)
    }

    // MARK: - teardown

    func testShutdownDuringLiveRecordingAbandonsTheAttempt() async throws {
        let harness = await makeHarness()
        try await harness.beginLiveRecording()

        harness.pipeline.shutdown()
        harness.manager.reportTentative("dropped on the floor")
        await harness.pipeline.awaitPendingJob()

        XCTAssertEqual(harness.manager.finishCount, 0)
    }

    func testShutdownDuringLiveRecordingPublishesNoFurtherSnapshots() async throws {
        let harness = await makeHarness()
        try await harness.beginLiveRecording()

        harness.pipeline.shutdown()
        harness.manager.reportTentative("dropped on the floor")
        await harness.pipeline.awaitPendingJob()

        XCTAssertTrue(harness.transcripts.events.isEmpty)
    }

    // MARK: - the batch path is untouched

    func testNonStreamingSessionStillTranscribesTheRetainedBuffer() async {
        let transcriber = FakeTranscriber()
        transcriber.result = .success("hello world")
        let recorder = FakeRecorder(samples: [])
        let inserted = InsertSpy()
        let pipeline = Pipeline(
            config: makeTestConfig(),
            recorder: recorder,
            sessionProvider: FakeTranscriberSessionProvider(transcriber),
            insert: { inserted.insert($0) },
            record: { _ in },
            frontmostApp: { nil }
        )
        let captured = FakeRecorder.speech(seconds: 0.5)

        pipeline.startRecording()
        recorder.deliver(captured)
        pipeline.stopRecording()
        await pipeline.awaitPendingJob()

        XCTAssertEqual(transcriber.received, [captured])
    }

    func testNonStreamingSessionPublishesNoTranscriptSnapshots() async {
        let transcriber = FakeTranscriber()
        transcriber.result = .success("hello world")
        let recorder = FakeRecorder()
        let pipeline = Pipeline(
            config: makeTestConfig(),
            recorder: recorder,
            sessionProvider: FakeTranscriberSessionProvider(transcriber),
            record: { _ in },
            frontmostApp: { nil }
        )
        let transcripts = EventCollector<DictationTranscript>()
        pipeline.onTranscript = { transcripts.append($0) }

        pipeline.startRecording()
        pipeline.stopRecording()
        await pipeline.awaitPendingJob()

        XCTAssertTrue(transcripts.events.isEmpty)
    }

    func testNonStreamingSessionDoesNotSubscribeIncrementalDelivery() {
        let recorder = FakeRecorder()
        let pipeline = Pipeline(
            config: makeTestConfig(),
            recorder: recorder,
            sessionProvider: FakeTranscriberSessionProvider(FakeTranscriber()),
            record: { _ in },
            frontmostApp: { nil }
        )

        pipeline.startRecording()

        XCTAssertFalse(recorder.deliversSamples)
    }

    // MARK: - harness

    private func makeHarness(mode: Mode? = nil) async -> StreamingSessionHarness {
        let adapter = StreamingCapabilityAdapter()
        let lifecycle = ASRModelLifecycle(
            storedSelection: ASRModelCatalog.defaultID,
            adapters: [adapter]
        )
        await lifecycle.start()
        let recorder = FakeRecorder(samples: [])
        let inserted = InsertSpy()
        let recorded = RecordSpy()
        let states = StateCollector()
        let transcripts = EventCollector<DictationTranscript>()
        let sessions = EventCollector<DictationSessionEvent>()
        let pipeline = Pipeline(
            config: makeTestConfig(mode: mode ?? Mode(
                name: "Voice to Text", asrModel: "", llmModel: nil, systemPrompt: nil, vocab: []
            )),
            recorder: recorder,
            sessionProvider: lifecycle,
            polish: { text, _ in "polished: \(text)" },
            insert: { inserted.insert($0) },
            record: { recorded.record($0) },
            frontmostApp: { nil }
        )
        pipeline.onState = { states.append($0) }
        pipeline.onTranscript = { transcripts.append($0) }
        pipeline.onSessionEvent = { sessions.append($0) }
        addTeardownBlock { pipeline.shutdown() }
        return StreamingSessionHarness(
            testCase: self,
            adapter: adapter,
            recorder: recorder,
            pipeline: pipeline,
            inserted: inserted,
            recorded: recorded,
            states: states,
            transcripts: transcripts,
            sessions: sessions
        )
    }
}

/// Drives whole Dictation sessions against a streaming engine. Every wait is on
/// a signal the engine actually emits — subscription, finalization — so the tests
/// never depend on how fast the suite runs.
private struct StreamingSessionHarness {
    let testCase: XCTestCase
    let adapter: StreamingCapabilityAdapter
    let recorder: FakeRecorder
    let pipeline: Pipeline
    let inserted: InsertSpy
    let recorded: RecordSpy
    let states: StateCollector
    let transcripts: EventCollector<DictationTranscript>
    let sessions: EventCollector<DictationSessionEvent>

    /// Every wait is on a signal the engine emits within microseconds, so this
    /// bound is only ever reached by a regression that stops emitting it at all —
    /// which fails the test instead of hanging the suite.
    private static let signalTimeout: TimeInterval = 5

    var manager: FakeStreamingASRManager {
        adapter.manager
    }

    var startedSessionIDs: [UUID] {
        sessions.events.compactMap { event in
            guard case let .started(id) = event else { return nil }
            return id
        }
    }

    /// The first `count` finalizations fail; the next one settles on `text`.
    func failFinalizations(_ count: Int, thenSucceedWith text: String) {
        let attempts = EventCollector<Int>()
        manager.onFinish = { [manager] in
            attempts.append(1)
            manager.finishResult = attempts.events.count <= count
                ? .failure(StreamFailure())
                : .success(text)
        }
    }

    /// Starts recording and returns once the engine has subscribed this session's
    /// attempt, which is when engine reports can reach it.
    func beginLiveRecording() async throws {
        let subscribed = testCase.expectation(description: "live attempt subscribed")
        subscribed.assertForOverFulfill = false
        manager.onObserve = { subscribed.fulfill() }

        pipeline.startRecording()

        await testCase.fulfillment(of: [subscribed], timeout: Self.signalTimeout)
    }

    /// One whole Dictation session: capture `chunks`, let `report` emit engine
    /// reports into the open attempt, then release the hotkey and drain the job.
    func record(
        chunks: [[Float]],
        report: (FakeStreamingASRManager) -> Void = { _ in }
    ) async throws {
        try await beginLiveRecording()
        for chunk in chunks {
            recorder.deliver(chunk)
        }
        report(manager)
        pipeline.stopRecording()
        await pipeline.awaitPendingJob()
    }

    /// A second Dictation session started while the first is still finalizing, so
    /// the loaded engine is still driven by exactly one attempt. Returns the two
    /// Dictation session IDs in start order.
    func recordOverlappingSession() async throws -> (first: UUID, second: UUID) {
        let finalizing = testCase.expectation(description: "first session finalizing")
        finalizing.assertForOverFulfill = false
        let holdFirstFinalization = Latch()
        let attempts = EventCollector<Int>()
        manager.onFinish = { [manager] in
            attempts.append(1)
            guard attempts.events.count == 1 else {
                manager.finishResult = .success("second session")
                return
            }
            manager.finishResult = .success("first session")
            finalizing.fulfill()
            await holdFirstFinalization.wait()
        }

        try await beginLiveRecording()
        recorder.deliver(FakeRecorder.speech(seconds: 0.5))
        pipeline.stopRecording()
        await testCase.fulfillment(of: [finalizing], timeout: Self.signalTimeout)

        pipeline.startRecording()
        recorder.deliver(FakeRecorder.speech(seconds: 0.5))
        pipeline.stopRecording()
        await holdFirstFinalization.open()
        await pipeline.awaitPendingJob()

        let ids = startedSessionIDs
        guard ids.count == 2 else {
            throw XCTSkip("Expected two Dictation sessions to start.")
        }
        return (ids[0], ids[1])
    }
}
