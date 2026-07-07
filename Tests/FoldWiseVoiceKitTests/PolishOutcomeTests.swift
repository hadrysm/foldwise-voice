// The Polish stage's keep-or-fall-back decision (ADR-0004), extracted into
// `Polish.run` as the single source of truth for both the live session
// (Pipeline) and Re-run Polish (HistoryReprocessor). These pin the decision at
// its own seam — the short-input/raw-Mode gate, the on-task keep, and the
// off-task fallback — so a change to either caller can't silently diverge from
// the rule. The polish stage is an injected closure; no live Ollama.

import XCTest
@testable import FoldWiseVoiceKit

final class PolishOutcomeTests: XCTestCase {
    /// An In-place Mode (expands: false): the off-task check falls back on a
    /// low-overlap candidate via the strict-overlap rule, matching the fixtures
    /// in PipelineOutcomeTests and HistoryReprocessorTests.
    private let cleanMode = Mode(
        name: "Clean", asrModel: "", llmModel: "llama3", systemPrompt: nil, vocab: [],
        expands: false
    )
    private let rawMode = Mode(
        name: "Voice to Text", asrModel: "", llmModel: nil, systemPrompt: nil, vocab: []
    )
    private let longTranscript =
        "this transcript is unquestionably longer than the forty character polish threshold"

    // MARK: - skipped: no verdict, raw text, unpolished

    func testRawModeSkipsPolishAndKeepsRawText() async {
        let box = InputBox()
        let outcome = await Polish.run(rawText: longTranscript, mode: rawMode) { input, _ in
            box.value = input
            return "should never be used"
        }
        XCTAssertNil(box.value) // the polish seam was never called
        XCTAssertEqual(outcome.text, longTranscript)
        XCTAssertFalse(outcome.isPolished)
        XCTAssertNil(outcome.verdict)
    }

    func testTooShortTranscriptSkipsPolish() async {
        let short = "too short to polish"
        let box = InputBox()
        let outcome = await Polish.run(rawText: short, mode: cleanMode) { input, _ in
            box.value = input
            return "cleaned"
        }
        XCTAssertNil(box.value)
        XCTAssertEqual(outcome.text, short)
        XCTAssertFalse(outcome.isPolished)
        XCTAssertNil(outcome.verdict)
    }

    // MARK: - on-task: candidate kept, marked polished

    func testOnTaskPolishIsKept() async {
        let cleaned =
            "This transcript is unquestionably longer than the forty-character polish threshold."
        let outcome = await Polish.run(rawText: longTranscript, mode: cleanMode) { _, _ in cleaned }
        XCTAssertEqual(outcome.text, cleaned)
        XCTAssertTrue(outcome.isPolished)
        XCTAssertEqual(outcome.verdict?.fellBack, false)
    }

    // MARK: - off-task: candidate discarded, raw restored

    func testOffTaskPolishFallsBackToRaw() async {
        let outcome = await Polish.run(rawText: longTranscript, mode: cleanMode) { _, _ in
            "Roses are red, violets are blue,\nA poem replies where a cleanup was due."
        }
        XCTAssertEqual(outcome.text, longTranscript)
        XCTAssertFalse(outcome.isPolished)
        XCTAssertEqual(outcome.verdict?.fellBack, true)
    }
}

/// A reference box for capturing what the injected polish seam received (or
/// asserting it was never called).
private final class InputBox {
    var value: String?
}
