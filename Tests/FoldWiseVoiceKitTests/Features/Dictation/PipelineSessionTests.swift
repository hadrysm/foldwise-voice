// Tracer bullet for the Pipeline seams (ADR-0002): one full dictation
// session driven entirely through the public interface with fakes, asserting
// the emitted progress-state sequence.

import XCTest
@testable import FoldWiseVoiceKit

private struct FailedSessionError: Error {}

final class PipelineSessionTests: XCTestCase {
    func testFullSessionEmitsListeningTranscribingInserted() async {
        let transcriber = FakeTranscriber()
        transcriber.result = .success("hello world")
        let pipeline = Pipeline(
            config: makeTestConfig(),
            recorder: FakeRecorder(),
            transcriber: transcriber,
            polish: { text, _ in text },
            insert: { _ in true },
            record: { _ in },
            frontmostApp: { nil }
        )
        let collector = StateCollector()
        pipeline.onState = { collector.append($0) }

        pipeline.startRecording()
        pipeline.stopRecording()
        await pipeline.awaitPendingJob()

        XCTAssertEqual(
            collector.states,
            [.listening(mode: "Voice to Text"), .transcribing, .inserted]
        )
    }

    func testFullSessionDucksAndRestoresAudio() async {
        let transcriber = FakeTranscriber()
        transcriber.result = .success("hello world")
        let ducker = FakeAudioDucker()
        let pipeline = Pipeline(
            config: makeTestConfig(pauseAudio: true),
            recorder: FakeRecorder(),
            transcriber: transcriber,
            ducker: ducker,
            polish: { text, _ in text },
            insert: { _ in true },
            record: { _ in },
            frontmostApp: { nil }
        )

        pipeline.startRecording()
        pipeline.stopRecording()
        await pipeline.awaitPendingJob()

        XCTAssertEqual(ducker.events, [.duck, .restore])
    }

    func testShutdownDuringCaptureRestoresAudio() {
        let ducker = FakeAudioDucker()
        let pipeline = Pipeline(
            config: makeTestConfig(pauseAudio: true),
            recorder: FakeRecorder(),
            transcriber: FakeTranscriber(),
            ducker: ducker,
            record: { _ in },
            frontmostApp: { nil }
        )

        pipeline.startRecording()
        pipeline.shutdown()

        XCTAssertEqual(ducker.events, [.duck, .restore])
    }

    func testTranscriptionFailureStillRestoresAudio() async {
        let transcriber = FakeTranscriber()
        transcriber.result = .failure(FailedSessionError())
        let ducker = FakeAudioDucker()
        let pipeline = Pipeline(
            config: makeTestConfig(pauseAudio: true),
            recorder: FakeRecorder(),
            transcriber: transcriber,
            ducker: ducker,
            record: { _ in },
            frontmostApp: { nil }
        )

        pipeline.startRecording()
        pipeline.stopRecording()
        await pipeline.awaitPendingJob()

        XCTAssertEqual(ducker.events, [.duck, .restore])
    }
}
