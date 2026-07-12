// Pins the Polish output sanitizer: given a model response string, the text a
// user would actually receive. The sanitizer only removes known-bad patterns
// (echoed delimiters, narration, meta blocks) — it never truncates by length,
// so Email/Bullets rewrites survive intact.

import XCTest
@testable import FoldWiseVoiceKit

final class OllamaSanitizeTests: XCTestCase {
    /// The exact failure reported in the field: narration, an echoed
    /// delimiter, a "Changes:" block, and a "Corrected:" block around the
    /// one sentence that should have been inserted.
    func testReportedFailureSanitizesToCorrectedSentence() {
        let response = """
        The extracted sentence is:
        "The previous prompt has been skipped."

        After applying the rules, the result becomes:
        The previous prompt has been  removed.

        Changes: Remove redundant word ("has"), incorrect punctuation ("<transcript>").

        Corrected:
        The previous prompt has been removed.
        """
        XCTAssertEqual(
            OllamaClient.sanitize(response),
            "The previous prompt has been removed."
        )
    }

    func testEchoedTranscriptDelimitersAreRemoved() {
        let response = "<transcript>\nWe should meet at noon.\n</transcript>"
        XCTAssertEqual(OllamaClient.sanitize(response), "We should meet at noon.")
    }

    func testLeadingPreambleLineIsStripped() {
        let response = "Here is the cleaned text:\nWe should meet at noon."
        XCTAssertEqual(OllamaClient.sanitize(response), "We should meet at noon.")
    }

    func testSureStylePreambleIsStripped() {
        let response = "Sure, here's the corrected version:\nWe should meet at noon."
        XCTAssertEqual(OllamaClient.sanitize(response), "We should meet at noon.")
    }

    func testTrailingChangesBlockIsStripped() {
        let response = "We should meet at noon.\n\nChanges: removed a filler word."
        XCTAssertEqual(OllamaClient.sanitize(response), "We should meet at noon.")
    }

    func testCorrectedLabelKeepsOnlyLabeledAnswer() {
        let response = "Corrected:\nWe should meet at noon."
        XCTAssertEqual(OllamaClient.sanitize(response), "We should meet at noon.")
    }

    func testInlineCorrectedLabelKeepsRestOfLine() {
        let response = "Corrected: We should meet at noon."
        XCTAssertEqual(OllamaClient.sanitize(response), "We should meet at noon.")
    }

    func testCleanTextPassesThroughUnchanged() {
        let response = "We should meet at noon. Bring the quarterly report."
        XCTAssertEqual(OllamaClient.sanitize(response), response)
    }

    /// A dictated colon-headed list looks superficially like a preamble;
    /// without a narration keyword it must survive untouched.
    func testColonHeadedListSurvivesUnchanged() {
        let response = "Here is what we need:\n- apples\n- bananas"
        XCTAssertEqual(OllamaClient.sanitize(response), response)
    }

    func testMultilineBulletsSurviveUnchanged() {
        let response = "- Review the budget\n- Email the vendor\n- Book the room"
        XCTAssertEqual(OllamaClient.sanitize(response), response)
    }

    /// Chatter-only output must sanitize to empty so the Polish stage's
    /// existing empty-check falls back to the raw transcript.
    func testChatterOnlyOutputSanitizesToEmpty() {
        let response = "Changes: tidied punctuation and spacing."
        XCTAssertEqual(OllamaClient.sanitize(response), "")
    }
}
