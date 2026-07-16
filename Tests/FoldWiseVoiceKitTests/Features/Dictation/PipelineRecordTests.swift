// The Pipeline's record seam (PRD #78, slice 1): a full dictation session
// driven through the seams (ADR-0002) with a spy record closure, asserting the
// assembled HistoryEntry — raw vs. polished text, the isPolished flag across
// the Polish-survived and off-task-fallback cases, and the session metadata.

import XCTest
@testable import FoldWiseVoiceKit

final class PipelineRecordTests: XCTestCase {
    private let cleanMode = Mode(
        name: "Clean", asrModel: "", llmModel: "llama3", systemPrompt: nil, vocab: [],
        expands: false
    )
    private let longTranscript =
        "this transcript is unquestionably longer than the forty character polish threshold"
    private let cleaned =
        "This transcript is unquestionably longer than the forty-character polish threshold."

    /// Drives one full start→stop session through a Pipeline built from fakes
    /// and returns the entries the record seam received.
    private func recordSession(
        config: Config = makeTestConfig(),
        samples: [Float] = FakeRecorder.speech(),
        transcript: Result<String, Error> = .success("hello world"),
        polish: @escaping (String, Mode) async -> String = { text, _ in text },
        insert: @escaping (String) async -> Bool = { _ in true },
        frontmostApp: @escaping () async -> String? = { "TextEdit" }
    ) async -> [HistoryEntry] {
        let transcriber = FakeTranscriber()
        transcriber.result = transcript
        let spy = RecordSpy()
        let pipeline = Pipeline(
            config: config,
            recorder: FakeRecorder(samples: samples),
            transcriber: transcriber,
            polish: polish,
            insert: insert,
            record: { spy.record($0) },
            frontmostApp: frontmostApp
        )
        pipeline.startRecording()
        pipeline.stopRecording()
        await pipeline.awaitPendingJob()
        return spy.entries
    }

    // MARK: - Polish survived vs. off-task fallback

    func testRecordsPolishedTextAndKeepsRawWhenPolishSurvives() async throws {
        let entries = await recordSession(
            config: makeTestConfig(mode: cleanMode),
            transcript: .success(longTranscript),
            polish: { _, _ in self.cleaned }
        )
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.text, cleaned)
        XCTAssertEqual(entry.rawText, longTranscript)
        XCTAssertTrue(entry.isPolished)
    }

    func testRecordsRawTranscriptAndUnpolishedWhenPolishGoesOffTask() async throws {
        let entries = await recordSession(
            config: makeTestConfig(mode: cleanMode),
            transcript: .success(longTranscript),
            polish: { _, _ in
                "Roses are red, violets are blue,\nA poem replies where a cleanup was due."
            }
        )
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.text, longTranscript)
        XCTAssertEqual(entry.rawText, longTranscript)
        XCTAssertFalse(entry.isPolished)
    }

    func testRecordsRawModeSessionAsUnpolished() async throws {
        // makeTestConfig defaults to a raw "Voice to Text" mode: no LLM, so
        // text == rawText and Polish never ran.
        let entries = await recordSession(transcript: .success(longTranscript))
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.text, longTranscript)
        XCTAssertEqual(entry.rawText, longTranscript)
        XCTAssertFalse(entry.isPolished)
    }

    // MARK: - metadata

    func testRecordsModeNameWordCountDurationAndSourceApp() async throws {
        let entries = await recordSession(
            config: makeTestConfig(mode: cleanMode),
            samples: FakeRecorder.speech(seconds: 1.0),
            transcript: .success(longTranscript),
            polish: { _, _ in self.cleaned },
            frontmostApp: { "TextEdit" }
        )
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.modeName, "Clean")
        XCTAssertEqual(entry.wordCount, 10)
        XCTAssertEqual(entry.durationMs, 1000)
        XCTAssertEqual(entry.sourceApp, "TextEdit")
    }

    // MARK: - only completed sessions are recorded

    func testDoesNotRecordWhenCaptureTooShort() async {
        let entries = await recordSession(samples: FakeRecorder.speech(seconds: 0.05))
        XCTAssertTrue(entries.isEmpty)
    }

    func testDoesNotRecordWhenTranscriptEmpty() async {
        let entries = await recordSession(transcript: .success(""))
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - master "Save dictation history" switch

    func testDoesNotRecordWhenSavingDisabled() async throws {
        // With saving off, the Pipeline must assemble and hand off nothing —
        // the record seam is never called, so no history file is ever written.
        let config = makeTestConfig()
        try await MainActor.run { try config.setSaveHistory(false) }
        let entries = await recordSession(config: config, transcript: .success(longTranscript))
        XCTAssertTrue(entries.isEmpty)
    }
}
