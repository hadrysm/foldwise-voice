// Pins every synchronous decision branch of a dictation session (issue #50):
// full sessions driven through the Pipeline seams (ADR-0002), asserting only
// the emitted state sequence and the texts the insert stage receives.

import XCTest
@testable import FoldWiseVoiceKit

private struct StubTranscribeError: Error {}

final class PipelineOutcomeTests: XCTestCase {
    private let llmMode = Mode(
        name: "Clean", asrModel: "", llmModel: "llama3", systemPrompt: nil, vocab: []
    )
    private let longTranscript =
        "this transcript is unquestionably longer than the forty character polish threshold"

    /// Drives one full start→stop session through a Pipeline built from fakes
    /// and returns the emitted state sequence.
    private func runSession(
        config: Config = makeTestConfig(),
        samples: [Float] = FakeRecorder.speech(),
        transcript: Result<String, Error> = .success("hello world"),
        polish: @escaping (String, Mode) async -> String = { text, _ in text },
        insert: @escaping (String) async -> Bool = { _ in true }
    ) async -> [PipelineState] {
        let transcriber = FakeTranscriber()
        transcriber.result = transcript
        let pipeline = Pipeline(
            config: config,
            recorder: FakeRecorder(samples: samples),
            transcriber: transcriber,
            polish: polish,
            insert: insert,
            record: { _ in },
            frontmostApp: { nil }
        )
        let collector = StateCollector()
        pipeline.onState = { collector.append($0) }
        pipeline.startRecording()
        pipeline.stopRecording()
        await pipeline.awaitPendingJob()
        return collector.states
    }

    // MARK: - sessions that end at idle

    func testSessionEndsIdleWhenCaptureTooShort() async {
        let states = await runSession(samples: FakeRecorder.speech(seconds: 0.05))
        XCTAssertEqual(states, [.listening(mode: "Voice to Text"), .transcribing, .idle])
    }

    func testSessionEndsIdleWhenCaptureNearSilent() async {
        let states = await runSession(samples: FakeRecorder.speech(amplitude: 0.001))
        XCTAssertEqual(states, [.listening(mode: "Voice to Text"), .transcribing, .idle])
    }

    func testSessionEndsIdleWhenTranscriptEmpty() async {
        let states = await runSession(transcript: .success(""))
        XCTAssertEqual(states, [.listening(mode: "Voice to Text"), .transcribing, .idle])
    }

    // MARK: - transcribe failure

    func testSessionEmitsErrorWhenTranscribeThrows() async {
        let states = await runSession(transcript: .failure(StubTranscribeError()))
        XCTAssertEqual(
            states,
            [.listening(mode: "Voice to Text"), .transcribing, .error("StubTranscribeError()")]
        )
    }

    func testSessionEndsIdleWhenTranscriptionIsCancelled() async {
        let states = await runSession(transcript: .failure(CancellationError()))
        XCTAssertEqual(states, [.listening(mode: "Voice to Text"), .transcribing, .idle])
    }

    // MARK: - polish gating

    func testPolishSkippedWhenTranscriptBelowLengthThreshold() async {
        let states = await runSession(
            config: makeTestConfig(mode: llmMode), transcript: .success("short transcript")
        )
        XCTAssertEqual(states, [.listening(mode: "Clean"), .transcribing, .inserted])
    }

    func testPolishSkippedInRawMode() async {
        let states = await runSession(transcript: .success(longTranscript))
        XCTAssertEqual(states, [.listening(mode: "Voice to Text"), .transcribing, .inserted])
    }

    func testPolishRunsForLLMModeWithLongTranscript() async {
        let states = await runSession(
            config: makeTestConfig(mode: llmMode), transcript: .success(longTranscript)
        )
        XCTAssertEqual(
            states,
            [.listening(mode: "Clean"), .transcribing, .polishing(model: "llama3"), .inserted]
        )
    }

    func testInsertReceivesPolishedTextWhenPolishRuns() async {
        let spy = InsertSpy()
        _ = await runSession(
            config: makeTestConfig(mode: llmMode),
            transcript: .success(longTranscript),
            polish: { _, _ in "polished text" },
            insert: { spy.insert($0) }
        )
        XCTAssertEqual(spy.texts, ["polished text"])
    }

    /// Polish returning its input unchanged is exactly what the production
    /// stage does when Ollama is unreachable, so one fake covers both cases.
    func testInsertReceivesRawTranscriptWhenPolishReturnsUnchanged() async {
        let spy = InsertSpy()
        _ = await runSession(
            config: makeTestConfig(mode: llmMode),
            transcript: .success(longTranscript),
            polish: { text, _ in text },
            insert: { spy.insert($0) }
        )
        XCTAssertEqual(spy.texts, [longTranscript])
    }

    /// An off-task polish (a poem instead of a cleanup) is discarded and the
    /// raw transcript is pasted — the reported "write me a verse" outcome in a
    /// Clean (In-place) Mode. The wiring runs through the injected `polish`
    /// closure, no live Ollama.
    func testInsertReceivesRawTranscriptWhenPolishGoesOffTask() async {
        let cleanMode = Mode(
            name: "Clean", asrModel: "", llmModel: "llama3", systemPrompt: nil, vocab: [],
            expands: false
        )
        let spy = InsertSpy()
        _ = await runSession(
            config: makeTestConfig(mode: cleanMode),
            transcript: .success(longTranscript),
            polish: { _, _ in
                "Roses are red, violets are blue,\nA poem replies where a cleanup was due."
            },
            insert: { spy.insert($0) }
        )
        XCTAssertEqual(spy.texts, [longTranscript])
    }

    /// A legitimate polish (the transcript, cleaned) is on-task, so the polished
    /// text is pasted rather than the raw transcript.
    func testInsertReceivesPolishedTextWhenPolishStaysOnTask() async {
        let spy = InsertSpy()
        let cleaned = "This transcript is unquestionably longer than the forty-character polish threshold."
        _ = await runSession(
            config: makeTestConfig(mode: llmMode),
            transcript: .success(longTranscript),
            polish: { _, _ in cleaned },
            insert: { spy.insert($0) }
        )
        XCTAssertEqual(spy.texts, [cleaned])
    }

    // MARK: - insert outcome

    func testSessionEmitsInsertedWhenInsertSucceeds() async {
        let states = await runSession(insert: { _ in true })
        XCTAssertEqual(states, [.listening(mode: "Voice to Text"), .transcribing, .inserted])
    }

    func testSessionEmitsClipboardWhenInsertFails() async {
        let states = await runSession(insert: { _ in false })
        XCTAssertEqual(states, [.listening(mode: "Voice to Text"), .transcribing, .clipboard])
    }

    // MARK: - start/stop guards

    func testStartWhileRecordingIsNoOp() {
        let pipeline = Pipeline(
            config: makeTestConfig(),
            recorder: FakeRecorder(),
            transcriber: FakeTranscriber(),
            polish: { text, _ in text },
            insert: { _ in true }
        )
        let collector = StateCollector()
        pipeline.onState = { collector.append($0) }

        pipeline.startRecording()
        pipeline.startRecording()

        XCTAssertEqual(collector.states, [.listening(mode: "Voice to Text")])
    }

    func testStopWhileIdleIsNoOp() {
        let pipeline = Pipeline(
            config: makeTestConfig(),
            recorder: FakeRecorder(),
            transcriber: FakeTranscriber(),
            polish: { text, _ in text },
            insert: { _ in true }
        )
        let collector = StateCollector()
        pipeline.onState = { collector.append($0) }

        pipeline.stopRecording()

        XCTAssertTrue(collector.states.isEmpty)
    }

    func testToggleStartsAndStopsCompleteSession() async {
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

        pipeline.toggleRecording()
        pipeline.toggleRecording()
        await pipeline.awaitPendingJob()

        XCTAssertEqual(
            collector.states,
            [.listening(mode: "Voice to Text"), .transcribing, .inserted]
        )
    }

    func testDefaultPolishSkipsRawModeWithoutExternalService() async {
        let transcriber = FakeTranscriber()
        transcriber.result = .success(longTranscript)
        let insert = InsertSpy()
        let pipeline = Pipeline(
            config: makeTestConfig(),
            recorder: FakeRecorder(),
            transcriber: transcriber,
            insert: { insert.insert($0) },
            record: { _ in },
            frontmostApp: { nil }
        )

        pipeline.startRecording()
        pipeline.stopRecording()
        await pipeline.awaitPendingJob()

        XCTAssertEqual(insert.texts, [longTranscript])
    }
}
