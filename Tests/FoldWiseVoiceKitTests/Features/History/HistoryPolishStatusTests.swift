// The History row's honest polished/raw indicator (PRD #78, story 28),
// exercised through the pure PolishStatus mapping the (untested) SwiftUI view
// calls. A row is `.polished` only when Polish ran AND survived the off-task
// check; otherwise `.raw` — the shown text is the pre-Polish transcript,
// whether because the Mode does not polish or because Polish went Off-task and
// fell back to it. The label mirrors the app's raw↔polished vocabulary.

import XCTest
@testable import FoldWiseVoiceKit

final class HistoryPolishStatusTests: XCTestCase {
    private func entry(isPolished: Bool) -> HistoryEntry {
        HistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            text: "shown",
            rawText: "raw",
            isPolished: isPolished,
            modeName: "Email",
            wordCount: nil,
            sourceApp: nil,
            durationMs: nil,
            flagged: false,
            flagReason: nil
        )
    }

    func testStatusIsPolishedWhenPolishSurvived() {
        XCTAssertEqual(PolishStatus(entry(isPolished: true)), .polished)
    }

    func testStatusIsRawWhenPolishDidNotSurvive() {
        XCTAssertEqual(PolishStatus(entry(isPolished: false)), .raw)
    }

    func testPolishedLabelReadsPolished() {
        XCTAssertEqual(PolishStatus.polished.label, "Polished")
    }

    func testRawLabelReadsRaw() {
        XCTAssertEqual(PolishStatus.raw.label, "Raw")
    }
}
