// Pins the asynchronous session behaviors (issue #51): the model-loading
// indicator — when it appears, what it resolves to, and its suppression while
// recording — and strict in-order processing of silently double-tapped
// sessions. Sessions run through the Pipeline seams (ADR-0002); assertions
// touch only emitted states and the samples the transcribe stage receives.

import XCTest
@testable import FoldWiseVoiceKit

final class PipelineAsyncBehaviorTests: XCTestCase {
    private func makePipeline(
        recorder: FakeRecorder = FakeRecorder(),
        transcriber: FakeTranscriber
    ) -> (Pipeline, StateCollector) {
        let pipeline = Pipeline(
            config: makeTestConfig(),
            recorder: recorder,
            transcriber: transcriber,
            polish: { text, _ in text },
            insert: { _ in true }
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
}
