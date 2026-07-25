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

private struct QueuedASRSessionState: Equatable {
    let insertedTexts: [String]
    let captureCount: Int
    let releaseCount: Int
}

private final class BlockingStartRecorder: AudioRecording {
    var onFailure: ((AudioCaptureError) -> Void)?
    let startupEntered = DispatchSemaphore(value: 0)
    let releaseStartup = DispatchSemaphore(value: 0)

    func start() throws {
        startupEntered.signal()
        releaseStartup.wait()
    }

    func stop() -> [Float] {
        []
    }

    func close() {}
}

final class PipelineSessionTests: XCTestCase {
    func testShutdownReturnsWhileCaptureStartupIsBlocked() {
        let recorder = BlockingStartRecorder()
        let pipeline = Pipeline(
            config: makeTestConfig(),
            recorder: recorder,
            sessionProvider: FakeTranscriberSessionProvider(FakeTranscriber()),
            record: { _ in },
            frontmostApp: { nil }
        )
        let shutdownReturned = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            pipeline.startRecording()
        }
        XCTAssertEqual(recorder.startupEntered.wait(timeout: .now() + 0.2), .success)
        DispatchQueue.global().async {
            pipeline.shutdown()
            shutdownReturned.signal()
        }

        let result = shutdownReturned.wait(timeout: .now() + 0.2)
        recorder.releaseStartup.signal()

        XCTAssertEqual(result, .success)
    }

    func testSessionHandleReleasesAfterTranscriptionBeforePolishAndInsert() async {
        let events = SessionHandleEventProbe()
        let handle = FakeASRSessionHandle(
            result: .success(
                "this transcript is unquestionably longer than the forty character polish threshold"
            ),
            events: events
        )
        let provider = FakeASRSessionHandleProvider(handles: [handle], events: events)
        let mode = Mode(
            name: "Clean", asrModel: "", llmModel: "llama3", systemPrompt: nil, vocab: []
        )
        let pipeline = Pipeline(
            config: makeTestConfig(mode: mode),
            recorder: FakeRecorder(),
            sessionProvider: provider,
            polish: { text, _ in
                events.append(.polish)
                return text
            },
            insert: { _ in
                events.append(.insert)
                return true
            },
            record: { _ in },
            frontmostApp: { nil }
        )

        pipeline.startRecording()
        pipeline.stopRecording()
        await pipeline.awaitPendingJob()

        XCTAssertEqual(events.events, [.capture, .transcribe, .release, .polish, .insert])
    }

    func testShutdownFromTranscribingReleasesCapturedSession() async {
        let events = SessionHandleEventProbe()
        let handle = FakeASRSessionHandle(result: .success("unused"), events: events)
        let provider = FakeASRSessionHandleProvider(handles: [handle], events: events)
        let pipeline = Pipeline(
            config: makeTestConfig(),
            recorder: FakeRecorder(),
            sessionProvider: provider,
            record: { _ in },
            frontmostApp: { nil }
        )
        pipeline.onState = { state in
            if state == .transcribing {
                pipeline.shutdown()
            }
        }

        pipeline.startRecording()
        pipeline.stopRecording()
        await pipeline.awaitPendingJob()

        XCTAssertEqual(events.events, [.capture, .release])
    }

    func testSessionHandleReleasesWhenAudioDoesNotReachTranscription() async {
        let events = SessionHandleEventProbe()
        let handle = FakeASRSessionHandle(result: .success("unused"), events: events)
        let provider = FakeASRSessionHandleProvider(handles: [handle], events: events)
        let pipeline = Pipeline(
            config: makeTestConfig(),
            recorder: FakeRecorder(samples: FakeRecorder.speech(seconds: 0.05)),
            sessionProvider: provider,
            record: { _ in },
            frontmostApp: { nil }
        )

        pipeline.startRecording()
        pipeline.stopRecording()
        await pipeline.awaitPendingJob()

        XCTAssertEqual(events.events, [.capture, .release])
    }

    func testSessionHandleReleasesWhenTranscriptionFails() async {
        let events = SessionHandleEventProbe()
        let handle = FakeASRSessionHandle(result: .failure(FailedSessionError()), events: events)
        let provider = FakeASRSessionHandleProvider(handles: [handle], events: events)
        let pipeline = Pipeline(
            config: makeTestConfig(),
            recorder: FakeRecorder(),
            sessionProvider: provider,
            record: { _ in },
            frontmostApp: { nil }
        )

        pipeline.startRecording()
        pipeline.stopRecording()
        await pipeline.awaitPendingJob()

        XCTAssertEqual(events.events, [.capture, .transcribe, .release])
    }

    func testSessionHandleReleasesWhenTranscriptionIsCanceled() async {
        let events = SessionHandleEventProbe()
        let handle = FakeASRSessionHandle(result: .success("unused"), events: events)
        let transcribing = expectation(description: "transcription started")
        let finishTranscribing = Latch()
        handle.onTranscribe = {
            transcribing.fulfill()
            await finishTranscribing.wait()
        }
        let provider = FakeASRSessionHandleProvider(handles: [handle], events: events)
        let pipeline = Pipeline(
            config: makeTestConfig(),
            recorder: FakeRecorder(),
            sessionProvider: provider,
            record: { _ in },
            frontmostApp: { nil }
        )

        pipeline.startRecording()
        pipeline.stopRecording()
        await fulfillment(of: [transcribing])
        pipeline.shutdown()
        await finishTranscribing.open()
        await pipeline.awaitPendingJob()

        XCTAssertEqual(events.events, [.capture, .transcribe, .release])
    }

    func testSessionHandleReleasesWhenRecorderCannotStart() async {
        let events = SessionHandleEventProbe()
        let handle = FakeASRSessionHandle(result: .success("unused"), events: events)
        let provider = FakeASRSessionHandleProvider(handles: [handle], events: events)
        let recorder = FakeRecorder()
        recorder.startError = .bindFailed(device: "Studio Mic")
        let pipeline = Pipeline(
            config: makeTestConfig(),
            recorder: recorder,
            sessionProvider: provider,
            record: { _ in },
            frontmostApp: { nil }
        )

        pipeline.startRecording()
        await pipeline.awaitPendingJob()

        XCTAssertEqual(events.events, [.capture, .release])
    }

    func testSessionHandleReleasesWhenRecorderFailsDuringCapture() async {
        let events = SessionHandleEventProbe()
        let handle = FakeASRSessionHandle(result: .success("unused"), events: events)
        let provider = FakeASRSessionHandleProvider(handles: [handle], events: events)
        let recorder = FakeRecorder()
        let pipeline = Pipeline(
            config: makeTestConfig(),
            recorder: recorder,
            sessionProvider: provider,
            record: { _ in },
            frontmostApp: { nil }
        )

        pipeline.startRecording()
        recorder.fail(.configurationChanged)
        await pipeline.awaitPendingJob()

        XCTAssertEqual(events.events, [.capture, .release])
    }

    func testQueuedSessionsUseHandlesCapturedAtTheirRecordingStarts() async {
        let events = SessionHandleEventProbe()
        let first = FakeASRSessionHandle(result: .success("first model"), events: events)
        let second = FakeASRSessionHandle(result: .success("second model"), events: events)
        let provider = FakeASRSessionHandleProvider(handles: [first, second], events: events)
        let inserted = InsertSpy()
        let pipeline = Pipeline(
            config: makeTestConfig(),
            recorder: FakeRecorder(),
            sessionProvider: provider,
            insert: { inserted.insert($0) },
            record: { _ in },
            frontmostApp: { nil }
        )

        pipeline.startRecording()
        pipeline.stopRecording()
        pipeline.startRecording()
        pipeline.stopRecording()
        await pipeline.awaitPendingJob()

        XCTAssertEqual(
            QueuedASRSessionState(
                insertedTexts: inserted.texts,
                captureCount: events.events.count { $0 == .capture },
                releaseCount: events.events.count { $0 == .release }
            ),
            QueuedASRSessionState(
                insertedTexts: ["first model", "second model"],
                captureCount: 2,
                releaseCount: 2
            )
        )
    }

    func testBlockedRecognitionPreventsRecordingFromStarting() {
        let recorder = FakeRecorder()
        let transcriber = FakeTranscriber()
        transcriber.isDictationBlocked = true
        let ducker = FakeAudioDucker()
        let pipeline = Pipeline(
            config: makeTestConfig(pauseAudio: true),
            recorder: recorder,
            sessionProvider: FakeTranscriberSessionProvider(transcriber),
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
            sessionProvider: FakeTranscriberSessionProvider(transcriber), ducker: ducker,
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
            sessionProvider: FakeTranscriberSessionProvider(transcriber), ducker: ducker,
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
            sessionProvider: FakeTranscriberSessionProvider(transcriber),
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

    func testFullSessionEmitsPairedDictationSessionEvents() async {
        let transcriber = FakeTranscriber()
        transcriber.result = .success("hello world")
        let pipeline = Pipeline(
            config: makeTestConfig(),
            recorder: FakeRecorder(),
            sessionProvider: FakeTranscriberSessionProvider(transcriber),
            polish: { text, _ in text },
            insert: { _ in true },
            record: { _ in },
            frontmostApp: { nil }
        )
        let collector = EventCollector<DictationSessionEvent>()
        pipeline.onSessionEvent = { collector.append($0) }

        pipeline.startRecording()
        pipeline.stopRecording()
        await pipeline.awaitPendingJob()

        guard case let .started(startedID) = collector.events.first,
              case let .finished(finishedID) = collector.events.last
        else {
            return XCTFail("Expected paired Dictation session events")
        }
        XCTAssertEqual(startedID, finishedID)
    }

    func testCaptureStartupFailureEmitsNoDictationSessionEvents() {
        let recorder = FakeRecorder()
        recorder.startError = .bindFailed(device: "Studio Mic")
        let pipeline = Pipeline(
            config: makeTestConfig(),
            recorder: recorder,
            sessionProvider: FakeTranscriberSessionProvider(FakeTranscriber()),
            record: { _ in },
            frontmostApp: { nil }
        )
        let collector = EventCollector<DictationSessionEvent>()
        pipeline.onSessionEvent = { collector.append($0) }

        pipeline.startRecording()

        XCTAssertEqual(collector.events, [])
    }

    func testRelaunchDuringInsertionWaitsForSessionFinish() async {
        let events = EventCollector<String>()
        let insertionStarted = expectation(description: "insertion started")
        let finishInsertion = Latch()
        let transcriber = FakeTranscriber()
        transcriber.result = .success("hello world")
        let pipeline = Pipeline(
            config: makeTestConfig(),
            recorder: FakeRecorder(),
            sessionProvider: FakeTranscriberSessionProvider(transcriber),
            insert: { _ in
                insertionStarted.fulfill()
                await finishInsertion.wait()
                return true
            },
            record: { _ in },
            frontmostApp: { nil }
        )
        let coordinator = DictationLifecycleCoordinator(tearDown: {})
        pipeline.onSessionEvent = { coordinator.sessionDidChange($0) }

        pipeline.startRecording()
        pipeline.stopRecording()
        await fulfillment(of: [insertionStarted])
        let postponed = coordinator.shouldPostponeRelaunch {
            events.append("install")
        }
        events.append(postponed ? "postponed" : "continued")
        await finishInsertion.open()
        await pipeline.awaitPendingJob()

        XCTAssertEqual(events.events, ["postponed", "install"])
    }

    func testFullSessionDucksAndRestoresAudio() async {
        let transcriber = FakeTranscriber()
        transcriber.result = .success("hello world")
        let ducker = FakeAudioDucker()
        let pipeline = Pipeline(
            config: makeTestConfig(pauseAudio: true),
            recorder: FakeRecorder(),
            sessionProvider: FakeTranscriberSessionProvider(transcriber),
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
            sessionProvider: FakeTranscriberSessionProvider(FakeTranscriber()),
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
            sessionProvider: FakeTranscriberSessionProvider(transcriber),
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
