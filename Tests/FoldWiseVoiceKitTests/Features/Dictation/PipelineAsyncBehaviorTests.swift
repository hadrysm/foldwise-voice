// Pins the asynchronous session behaviors (issue #51): the model-loading
// indicator — when it appears, what it resolves to, and its suppression while
// recording — and strict in-order processing of silently double-tapped
// sessions. Sessions run through the Pipeline seams (ADR-0002); assertions
// touch only emitted states and the samples the transcribe stage receives.

import XCTest
@testable import FoldWiseVoiceKit

private struct StubTranscriptionError: Error {}

final class PipelineAsyncBehaviorTests: XCTestCase {
    private func makePipeline(
        config: Config = makeTestConfig(),
        recorder: FakeRecorder = FakeRecorder(),
        transcriber: FakeTranscriber,
        polish: @escaping (String, Mode) async -> String = { text, _ in text },
        insert: @escaping (String) async -> Bool = { _ in true },
        record: @escaping (HistoryEntry) -> Void = { _ in },
        frontmostApp: @escaping () async -> String? = { nil }
    ) -> (Pipeline, StateCollector) {
        let pipeline = Pipeline(
            config: config,
            recorder: recorder,
            transcriber: transcriber,
            polish: polish,
            insert: insert,
            record: record,
            frontmostApp: frontmostApp
        )
        let collector = StateCollector()
        pipeline.onState = { collector.append($0) }
        return (pipeline, collector)
    }

    // MARK: - model-loading indicator

    func testSessionEmitsLoadingModelWhenTranscriberNotReady() async {
        let transcriber = FakeTranscriber()
        transcriber.ready = false
        transcriber.result = .success("hello world")
        let (pipeline, collector) = makePipeline(transcriber: transcriber)

        pipeline.startRecording()
        pipeline.stopRecording()
        await pipeline.awaitPendingJob()

        XCTAssertEqual(
            collector.states,
            [.listening(mode: "Voice to Text"), .transcribing, .loadingModel, .inserted]
        )
    }

    func testLoadingModelResolvesToTranscribingWhenSessionQueued() async {
        let transcriber = FakeTranscriber()
        transcriber.ready = false
        transcriber.result = .success("hello world")
        // The load finishing mid-job is what the real Transcriber does when a
        // dictation is queued behind the model load.
        transcriber.onTranscribe = { [weak transcriber] in
            transcriber?.onLoading?(false)
        }
        let (pipeline, collector) = makePipeline(transcriber: transcriber)

        pipeline.startRecording()
        pipeline.stopRecording()
        await pipeline.awaitPendingJob()

        XCTAssertEqual(
            collector.states,
            [
                .listening(mode: "Voice to Text"), .transcribing,
                .loadingModel, .transcribing, .inserted,
            ]
        )
    }

    func testLoadingModelResolvesToIdleAfterLaunchWarmup() {
        let transcriber = FakeTranscriber()
        let (pipeline, collector) = makePipeline(transcriber: transcriber)

        transcriber.onLoading?(true)
        transcriber.onLoading?(false)

        // The Pipeline must outlive the callbacks — its deinit would sever the
        // weakly-captured onLoading handler under test.
        withExtendedLifetime(pipeline) {
            XCTAssertEqual(collector.states, [.loadingModel, .idle])
        }
    }

    func testLoadingModelSuppressedWhileRecording() {
        let transcriber = FakeTranscriber()
        let (pipeline, collector) = makePipeline(transcriber: transcriber)

        pipeline.startRecording()
        transcriber.onLoading?(true)
        transcriber.onLoading?(false)

        XCTAssertEqual(collector.states, [.listening(mode: "Voice to Text")])
    }

    // MARK: - fractional download progress

    /// An engine that reports a download fraction surfaces it as a
    /// `.downloadingModel(fraction:)` state, and the load-done signal resolves
    /// it back to transcribing for the queued dictation behind it.
    func testSessionEmitsDownloadingModelWhenEngineReportsProgress() async {
        let transcriber = FakeTranscriber()
        transcriber.ready = false
        transcriber.result = .success("hello world")
        // The real Whisper first-load downloads (reporting a fraction) then
        // flips the loading flag off once the weights are compiled and loaded.
        transcriber.onTranscribe = { [weak transcriber] in
            transcriber?.onDownloadProgress?(0.5)
            transcriber?.onLoading?(false)
        }
        let (pipeline, collector) = makePipeline(transcriber: transcriber)

        pipeline.startRecording()
        pipeline.stopRecording()
        await pipeline.awaitPendingJob()

        XCTAssertEqual(
            collector.states,
            [
                .listening(mode: "Voice to Text"), .transcribing,
                .loadingModel, .downloadingModel(fraction: 0.5), .transcribing, .inserted,
            ]
        )
    }

    func testDownloadingModelSuppressedWhileRecording() {
        let transcriber = FakeTranscriber()
        let (pipeline, collector) = makePipeline(transcriber: transcriber)

        pipeline.startRecording()
        transcriber.onDownloadProgress?(0.5)

        XCTAssertEqual(collector.states, [.listening(mode: "Voice to Text")])
    }

    // MARK: - silent double-tap queueing

    func testDoubleTappedSessionsProcessStrictlyInOrder() async {
        let firstCapture = FakeRecorder.speech(seconds: 1.0)
        let secondCapture = FakeRecorder.speech(seconds: 0.5)
        let recorder = FakeRecorder(samples: firstCapture)
        let transcriber = FakeTranscriber()
        transcriber.result = .success("hello world")
        // Hold the first session in its transcribe stage until the second
        // session has been queued behind it.
        let latch = Latch()
        transcriber.onTranscribe = { await latch.wait() }
        let (pipeline, collector) = makePipeline(recorder: recorder, transcriber: transcriber)

        pipeline.startRecording()
        pipeline.stopRecording()
        recorder.samples = secondCapture
        pipeline.startRecording()
        pipeline.stopRecording()
        await latch.open()
        await pipeline.awaitPendingJob()

        XCTAssertEqual(
            collector.states,
            [
                .listening(mode: "Voice to Text"), .transcribing,
                .listening(mode: "Voice to Text"), .transcribing,
                .inserted, .inserted,
            ]
        )
        XCTAssertEqual(
            transcriber.received.map(\.count), [firstCapture.count, secondCapture.count]
        )
    }

    func testQueuedSessionsContinueAfterTranscriptionFailure() async {
        let transcriber = FakeTranscriber()
        transcriber.result = .failure(StubTranscriptionError())
        let (pipeline, collector) = makePipeline(transcriber: transcriber)

        pipeline.startRecording()
        pipeline.stopRecording()
        pipeline.startRecording()
        pipeline.stopRecording()
        await pipeline.awaitPendingJob()

        XCTAssertEqual(
            collector.states,
            [
                .listening(mode: "Voice to Text"), .transcribing,
                .listening(mode: "Voice to Text"), .transcribing,
                .error("StubTranscriptionError()"), .error("StubTranscriptionError()"),
            ]
        )
    }

    // MARK: - start-time Mode snapshot

    func testModeSnapshotSurvivesDeletionDuringTranscription() async throws {
        let fixture = snapshotFixture()
        try preparePersistence(for: fixture.config, in: self)
        let transcriber = FakeTranscriber()
        transcriber.result = .success(snapshotTranscript)
        let entered = expectation(description: "transcription started")
        let finish = Latch()
        transcriber.onTranscribe = {
            entered.fulfill()
            await finish.wait()
        }
        let recorded = RecordSpy()
        let (pipeline, _) = makePipeline(
            config: fixture.config,
            transcriber: transcriber,
            record: { recorded.record($0) }
        )

        pipeline.startRecording()
        pipeline.stopRecording()
        await fulfillment(of: [entered])
        try await deleteModes(from: fixture.config)
        await finish.open()
        await pipeline.awaitPendingJob()

        XCTAssertEqual(recorded.entries.first?.modeID, fixture.modeID)
    }

    func testModeSnapshotSurvivesDeletionDuringPolish() async throws {
        let fixture = snapshotFixture()
        try preparePersistence(for: fixture.config, in: self)
        let transcriber = FakeTranscriber()
        transcriber.result = .success(snapshotTranscript)
        let entered = expectation(description: "polish started")
        let finish = Latch()
        let recorded = RecordSpy()
        let (pipeline, _) = makePipeline(
            config: fixture.config,
            transcriber: transcriber,
            polish: { text, _ in
                entered.fulfill()
                await finish.wait()
                return text
            },
            record: { recorded.record($0) }
        )

        pipeline.startRecording()
        pipeline.stopRecording()
        await fulfillment(of: [entered])
        try await deleteModes(from: fixture.config)
        await finish.open()
        await pipeline.awaitPendingJob()

        XCTAssertEqual(recorded.entries.first?.modeID, fixture.modeID)
    }

    func testModeSnapshotSurvivesDeletionDuringInsertion() async throws {
        let fixture = snapshotFixture()
        try preparePersistence(for: fixture.config, in: self)
        let transcriber = FakeTranscriber()
        transcriber.result = .success(snapshotTranscript)
        let entered = expectation(description: "insertion started")
        let finish = Latch()
        let recorded = RecordSpy()
        let (pipeline, _) = makePipeline(
            config: fixture.config,
            transcriber: transcriber,
            insert: { _ in
                entered.fulfill()
                await finish.wait()
                return true
            },
            record: { recorded.record($0) }
        )

        pipeline.startRecording()
        pipeline.stopRecording()
        await fulfillment(of: [entered])
        try await deleteModes(from: fixture.config)
        await finish.open()
        await pipeline.awaitPendingJob()

        XCTAssertEqual(recorded.entries.first?.modeID, fixture.modeID)
    }

    // MARK: - callback lifetime

    func testTranscriberCallbacksDoNothingAfterPipelineDeallocation() {
        let transcriber = FakeTranscriber()
        var pipeline: Pipeline? = makePipeline(transcriber: transcriber).0
        let collector = StateCollector()
        pipeline?.onState = { collector.append($0) }

        pipeline = nil
        transcriber.onLoading?(true)
        transcriber.onDownloadProgress?(0.5)

        XCTAssertTrue(collector.states.isEmpty)
    }

    // MARK: - shutdown cancellation

    func testShutdownCancelsSessionBeforeInsertion() async {
        let transcriber = FakeTranscriber()
        transcriber.result = .success("text that must not be inserted")
        let transcribing = expectation(description: "transcription started")
        let finishTranscribing = Latch()
        transcriber.onTranscribe = {
            transcribing.fulfill()
            await finishTranscribing.wait()
        }
        let (pipeline, collector) = makePipeline(
            transcriber: transcriber,
            insert: { _ in true }
        )

        pipeline.startRecording()
        pipeline.stopRecording()
        await fulfillment(of: [transcribing])
        pipeline.shutdown()
        await finishTranscribing.open()
        await pipeline.awaitPendingJob()

        XCTAssertEqual(
            collector.states,
            [.listening(mode: "Voice to Text"), .transcribing, .idle]
        )
    }

    func testShutdownCancelsEveryQueuedSession() async {
        let transcriber = FakeTranscriber()
        transcriber.result = .success("text that must not be inserted")
        let firstTranscription = expectation(description: "first transcription started")
        firstTranscription.assertForOverFulfill = false
        let finishTranscribing = Latch()
        transcriber.onTranscribe = {
            firstTranscription.fulfill()
            await finishTranscribing.wait()
        }
        let insert = InsertSpy()
        let (pipeline, _) = makePipeline(
            transcriber: transcriber,
            insert: { insert.insert($0) }
        )

        pipeline.startRecording()
        pipeline.stopRecording()
        await fulfillment(of: [firstTranscription])
        pipeline.startRecording()
        pipeline.stopRecording()
        pipeline.shutdown()
        await finishTranscribing.open()
        await pipeline.awaitPendingJob()

        XCTAssertTrue(insert.texts.isEmpty)
    }

    func testShutdownDuringPolishCancelsSessionBeforeInsertion() async {
        let mode = Mode(
            name: "Clean", asrModel: "", llmModel: "llama3", systemPrompt: nil, vocab: []
        )
        let transcriber = FakeTranscriber()
        transcriber.result = .success(
            "this transcript is unquestionably longer than the forty character polish threshold"
        )
        let polishing = expectation(description: "polish started")
        let finishPolishing = Latch()
        let insert = InsertSpy()
        let (pipeline, _) = makePipeline(
            config: makeTestConfig(mode: mode),
            transcriber: transcriber,
            polish: { text, _ in
                polishing.fulfill()
                await finishPolishing.wait()
                return text
            },
            insert: { insert.insert($0) }
        )

        pipeline.startRecording()
        pipeline.stopRecording()
        await fulfillment(of: [polishing])
        pipeline.shutdown()
        await finishPolishing.open()
        await pipeline.awaitPendingJob()

        XCTAssertTrue(insert.texts.isEmpty)
    }

    func testShutdownWhileResolvingPasteTargetCancelsInsertion() async {
        let transcriber = FakeTranscriber()
        transcriber.result = .success("text that must not be inserted")
        let resolvingTarget = expectation(description: "paste target lookup started")
        let finishResolvingTarget = Latch()
        let insert = InsertSpy()
        let (pipeline, _) = makePipeline(
            transcriber: transcriber,
            insert: { insert.insert($0) },
            frontmostApp: {
                resolvingTarget.fulfill()
                await finishResolvingTarget.wait()
                return "TextEdit"
            }
        )

        pipeline.startRecording()
        pipeline.stopRecording()
        await fulfillment(of: [resolvingTarget])
        pipeline.shutdown()
        await finishResolvingTarget.open()
        await pipeline.awaitPendingJob()

        XCTAssertTrue(insert.texts.isEmpty)
    }

    func testShutdownClosesRecorder() {
        let recorder = FakeRecorder()
        let transcriber = FakeTranscriber()
        let (pipeline, _) = makePipeline(recorder: recorder, transcriber: transcriber)

        pipeline.shutdown()
        pipeline.shutdown()

        XCTAssertEqual(recorder.closeCount, 1)
    }

    func testTranscriberCallbacksDoNothingAfterShutdown() {
        let transcriber = FakeTranscriber()
        let (pipeline, collector) = makePipeline(transcriber: transcriber)

        pipeline.shutdown()
        transcriber.onLoading?(true)
        transcriber.onDownloadProgress?(0.5)

        XCTAssertEqual(collector.states, [.idle])
    }

    func testStateCallbackCanShutDownPipelineWithoutDeadlocking() {
        let transcriber = FakeTranscriber()
        let (pipeline, collector) = makePipeline(transcriber: transcriber)
        pipeline.onState = { state in
            collector.append(state)
            if state == .loadingModel {
                pipeline.shutdown()
            }
        }

        transcriber.onLoading?(true)

        XCTAssertEqual(collector.states, [.loadingModel, .idle])
    }

    func testShutdownFromTranscribingDoesNotStartSession() async {
        let transcriber = FakeTranscriber()
        transcriber.result = .success("text that must not be inserted")
        let (pipeline, _) = makePipeline(transcriber: transcriber)
        pipeline.onState = { state in
            if state == .transcribing {
                pipeline.shutdown()
            }
        }

        pipeline.startRecording()
        pipeline.stopRecording()
        await pipeline.awaitPendingJob()

        XCTAssertTrue(transcriber.received.isEmpty)
    }

    func testShutdownFromInsertedDoesNotRecordHistory() async {
        let transcriber = FakeTranscriber()
        transcriber.result = .success("inserted text")
        let record = RecordSpy()
        let (pipeline, _) = makePipeline(
            transcriber: transcriber,
            record: { record.record($0) }
        )
        pipeline.onState = { state in
            if state == .inserted {
                pipeline.shutdown()
            }
        }

        pipeline.startRecording()
        pipeline.stopRecording()
        await pipeline.awaitPendingJob()

        XCTAssertTrue(record.entries.isEmpty)
    }

    func testShutdownDuringInsertionKeepsIdleAsTerminalState() async {
        let transcriber = FakeTranscriber()
        transcriber.result = .success("insertion already started")
        let inserting = expectation(description: "insert started")
        let finishInserting = Latch()
        let (pipeline, collector) = makePipeline(
            transcriber: transcriber,
            insert: { _ in
                inserting.fulfill()
                await finishInserting.wait()
                return true
            }
        )

        pipeline.startRecording()
        pipeline.stopRecording()
        await fulfillment(of: [inserting])
        pipeline.shutdown()
        await finishInserting.open()
        await pipeline.awaitPendingJob()

        XCTAssertEqual(
            collector.states,
            [.listening(mode: "Voice to Text"), .transcribing, .idle]
        )
    }

    func testShutdownDuringInsertionDoesNotRecordHistory() async {
        let transcriber = FakeTranscriber()
        transcriber.result = .success("insertion already started")
        let inserting = expectation(description: "insert started")
        let finishInserting = Latch()
        let record = RecordSpy()
        let (pipeline, _) = makePipeline(
            transcriber: transcriber,
            insert: { _ in
                inserting.fulfill()
                await finishInserting.wait()
                return true
            },
            record: { record.record($0) }
        )

        pipeline.startRecording()
        pipeline.stopRecording()
        await fulfillment(of: [inserting])
        pipeline.shutdown()
        await finishInserting.open()
        await pipeline.awaitPendingJob()

        XCTAssertTrue(record.entries.isEmpty)
    }

    func testShutdownDuringCaptureIgnoresLaterInputAndEndsIdle() async {
        let transcriber = FakeTranscriber()
        transcriber.result = .success("text that must not be inserted")
        let (pipeline, collector) = makePipeline(transcriber: transcriber)

        pipeline.startRecording()
        pipeline.shutdown()
        pipeline.stopRecording()
        pipeline.startRecording()
        pipeline.toggleRecording()
        await pipeline.awaitPendingJob()

        XCTAssertEqual(
            collector.states,
            [.listening(mode: "Voice to Text"), .idle]
        )
    }

    private var snapshotTranscript: String {
        "this transcript is unquestionably longer than the forty character polish threshold"
    }

    private func snapshotFixture() -> (config: Config, modeID: ModeID) {
        let modeID = ModeID.random()
        let mode = Mode(
            id: modeID,
            name: "Frozen",
            icon: "snowflake",
            asrModel: ASRModelCatalog.defaultID,
            llmModel: "qwen2.5:3b",
            transformation: .inPlace,
            systemPrompt: "Keep the wording",
            vocabulary: ["FoldWise"]
        )
        return (makeTestConfig(mode: mode), modeID)
    }

    private func deleteModes(from config: Config) async throws {
        try await MainActor.run {
            try config.replaceModes([], selection: .voiceToText)
        }
    }
}
