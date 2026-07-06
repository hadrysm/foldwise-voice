// Pins the Polish `max_tokens` sizing formula: a generous backstop against
// UNBOUNDED runaway keyed to transcript length and Mode category, never a tight
// bound on legitimate expansion (a truncated legitimate output reads as on-task
// and the off-task check cannot rescue it, so the cap errs generous). Expanding
// Modes get a larger multiple and a higher floor; In-place Modes track the
// transcript, so a tighter multiple catches a runaway sooner. Mirrors
// OllamaDeleteOutcomeTests: drives the client's pure helper directly, no network.

import XCTest
@testable import FoldWiseVoiceKit

final class OllamaMaxTokensTests: XCTestCase {
    private func size(_ chars: Int, expands: Bool) -> Int {
        OllamaClient.maxPolishTokens(transcriptCharacterCount: chars, expands: expands)
    }

    func testShortTranscriptInExpandingModeResolvesToFloor() {
        // 40 chars ≈ 10 tokens; the multiple stays under the floor, so the
        // floor governs — a 40-char dictation can still become a full email.
        XCTAssertEqual(size(40, expands: true), 512)
    }

    func testShortTranscriptInInPlaceModeResolvesToFloor() {
        XCTAssertEqual(size(40, expands: false), 256)
    }

    func testLongTranscriptInExpandingModeResolvesToMultiple() {
        // 4000 chars ≈ 1000 tokens; 4× clears the floor, so the multiple wins.
        XCTAssertEqual(size(4000, expands: true), 4000)
    }

    func testLongTranscriptInInPlaceModeResolvesToMultiple() {
        XCTAssertEqual(size(4000, expands: false), 2000)
    }

    func testInPlaceIsTighterThanExpandingForTheSameInput() {
        XCTAssertLessThan(size(4000, expands: false), size(4000, expands: true))
    }

    func testGenerousEmailForShortDictationIsNotTruncated() {
        // A ~60-char dictation ("remind the team about the launch deadline")
        // legitimately expands into a full ~200-token email; the cap must clear
        // it, otherwise a truncated-but-on-task output is unrescuable.
        XCTAssertGreaterThanOrEqual(size(60, expands: true), 200)
    }
}
