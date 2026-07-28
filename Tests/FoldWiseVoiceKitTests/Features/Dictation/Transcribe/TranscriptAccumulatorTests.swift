import XCTest
@testable import FoldWiseVoiceKit

/// The committed/tentative rules a Transcript snapshot promises (ADR-0009),
/// exercised through the accumulator's public updates.
final class TranscriptAccumulatorTests: XCTestCase {
    func testFirstReportBecomesTheTentativeSuffix() {
        var accumulator = TranscriptAccumulator()

        XCTAssertEqual(
            accumulator.observeTentative("the quick brown"),
            TranscriptSnapshot(committed: "", tentative: "the quick brown")
        )
    }

    func testLaterReportRewritesTheTentativeSuffix() {
        var accumulator = TranscriptAccumulator()
        accumulator.observeTentative("the quick brown")

        XCTAssertEqual(
            accumulator.observeTentative("the quick brownie"),
            TranscriptSnapshot(committed: "", tentative: "the quick brownie")
        )
    }

    func testCommitMovesTheBoundaryWithoutChangingRecognizedText() {
        var accumulator = TranscriptAccumulator()
        accumulator.observeTentative("the quick brown fox")

        XCTAssertEqual(
            accumulator.commit("the quick brown"),
            TranscriptSnapshot(committed: "the quick brown", tentative: " fox")
        )
    }

    func testReportAfterCommitKeepsTheCommittedPrefix() {
        var accumulator = TranscriptAccumulator()
        accumulator.observeTentative("the quick brown")
        accumulator.commit("the quick brown")

        XCTAssertEqual(
            accumulator.observeTentative("the quick brown fox jumps"),
            TranscriptSnapshot(committed: "the quick brown", tentative: " fox jumps")
        )
    }

    func testShorterCommitCannotUnsayCommittedWords() {
        var accumulator = TranscriptAccumulator()
        accumulator.observeTentative("the quick brown fox")
        accumulator.commit("the quick brown")

        XCTAssertEqual(
            accumulator.commit("the quick"),
            TranscriptSnapshot(committed: "the quick brown", tentative: " fox")
        )
    }

    func testDivergingCommitIsIgnored() {
        var accumulator = TranscriptAccumulator()
        accumulator.observeTentative("the quick brown")
        accumulator.commit("the quick brown")

        XCTAssertEqual(
            accumulator.commit("a quick brown fox"),
            TranscriptSnapshot(committed: "the quick brown", tentative: "")
        )
    }

    func testDivergingReportCannotRewriteCommittedWords() {
        var accumulator = TranscriptAccumulator()
        accumulator.observeTentative("the quick brown")
        accumulator.commit("the quick brown")

        // "brawn" diverges inside the committed span: the committed text wins, and
        // the boundary split leaves the surrounding words neither doubled nor mangled.
        XCTAssertEqual(
            accumulator.observeTentative("the quick brawn fox"),
            TranscriptSnapshot(committed: "the quick brown", tentative: " fox")
        )
    }

    func testReportShorterThanTheCommittedPrefixIsIgnored() {
        var accumulator = TranscriptAccumulator()
        accumulator.observeTentative("the quick brown fox")
        accumulator.commit("the quick brown")

        XCTAssertEqual(
            accumulator.observeTentative("the qu"),
            TranscriptSnapshot(committed: "the quick brown", tentative: " fox")
        )
    }

    func testCommitWithoutAnyReportLeavesNothingTentative() {
        var accumulator = TranscriptAccumulator()

        XCTAssertEqual(
            accumulator.commit("the quick brown"),
            TranscriptSnapshot(committed: "the quick brown", tentative: "")
        )
    }

    func testFinalizeReplacesBothSpans() {
        var accumulator = TranscriptAccumulator()
        accumulator.observeTentative("the quick brown fox")
        accumulator.commit("the quick brown")

        XCTAssertEqual(
            accumulator.finalize("The quick brown fox."),
            TranscriptSnapshot(committed: "The quick brown fox.", tentative: "")
        )
    }

    func testSnapshotTextConcatenatesSpansVerbatim() {
        let snapshot = TranscriptSnapshot(committed: "the quick brown", tentative: " fox")

        XCTAssertEqual(snapshot.text, "the quick brown fox")
    }

    func testSnapshotWithNeitherSpanIsEmpty() {
        XCTAssertTrue(TranscriptSnapshot.empty.isEmpty)
    }

    func testSnapshotWithOnlyTentativeTextIsNotEmpty() {
        XCTAssertFalse(TranscriptSnapshot(committed: "", tentative: "the").isEmpty)
    }
}
