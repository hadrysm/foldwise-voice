// Tracer bullet for the Pipeline seams (ADR-0002): one full dictation
// session driven entirely through the public interface with fakes, asserting
// the emitted progress-state sequence.

import XCTest
@testable import FoldWiseVoiceKit

private struct FailedSessionError: Error {}

private struct BlockedRecordingState: Equatable {
    let recorderStartCount: Int
    let duckingEvents: [AudioDuckingEvent]
    let pipelineStates: [PipelineState]
}

final class PipelineSessionTests: XCTestCase {
    func testBlockedRecognitionPreventsRecordingFromStarting() {
        let recorder = FakeRecorder()
        let transcriber = FakeTranscriber()
        transcriber.isDictationBlocked = true
        let ducker = FakeAudioDucker()
        let pipeline = Pipeline(
            config: makeTestConfig(pauseAudio: true),
            recorder: recorder,
            transcriber: transcriber,
            ducker: ducker,
            record: { _ in },
            frontmostApp: { nil }
        )
        let collector = StateCollector()
        pipeline.onState = { collector.append($0) }

        pipeline.startRecording()

        XCTAssertEqual(
            BlockedRecordingState(
                recorderStartCount: recorder.startCount,
                duckingEvents: ducker.events,
                pipelineStates: collector.states
            ),
            BlockedRecordingState(
                recorderStartCount: 0,
                duckingEvents: [],
                pipelineStates: []
            )
        )
    }

    func testCaptureStartupFailureEmitsErrorWithoutListeningOrLaterStages() async {
        let recorder = FakeRecorder()
        recorder.startError = .bindFailed(device: "Studio Mic")
        let transcriber = FakeTranscriber()
        let ducker = FakeAudioDucker()
        let inserted = InsertSpy()
        let recorded = RecordSpy()
        let pipeline = Pipeline(
            config: makeTestConfig(pauseAudio: true), recorder: recorder,
            transcriber: transcriber, ducker: ducker,
            insert: { inserted.insert($0) }, record: { recorded.record($0) },
            frontmostApp: { nil }
        )
        let collector = StateCollector()
        pipeline.onState = { collector.append($0) }

        pipeline.startRecording()
        pipeline.stopRecording()
        await pipeline.awaitPendingJob()

        XCTAssertEqual(
            collector.states,
            [.error(AudioCaptureError.bindFailed(device: "Studio Mic").localizedDescription)]
        )
        XCTAssertEqual(ducker.events, [.duck, .restore])
        XCTAssertTrue(transcriber.received.isEmpty)
        XCTAssertTrue(inserted.texts.isEmpty)
        XCTAssertTrue(recorded.entries.isEmpty)
    }

    func testRuntimeCaptureFailureDiscardsSessionAndRestoresAudio() async {
        let recorder = FakeRecorder()
        let transcriber = FakeTranscriber()
        let ducker = FakeAudioDucker()
        let inserted = InsertSpy()
        let recorded = RecordSpy()
        let pipeline = Pipeline(
            config: makeTestConfig(pauseAudio: true), recorder: recorder,
            transcriber: transcriber, ducker: ducker,
            insert: { inserted.insert($0) }, record: { recorded.record($0) },
            frontmostApp: { nil }
        )
        let collector = StateCollector()
        pipeline.onState = { collector.append($0) }
        pipeline.startRecording()

        recorder.fail(.configurationChanged)
        pipeline.stopRecording()
        await pipeline.awaitPendingJob()

        XCTAssertEqual(
            collector.states,
            [
                .listening(mode: "Voice to Text"),
                .error(AudioCaptureError.configurationChanged.localizedDescription),
            ]
        )
        XCTAssertEqual(ducker.events, [.duck, .restore])
        XCTAssertTrue(transcriber.received.isEmpty)
        XCTAssertTrue(inserted.texts.isEmpty)
        XCTAssertTrue(recorded.entries.isEmpty)
    }

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
