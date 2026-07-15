import XCTest
@testable import FoldWiseVoiceKit

final class DictationRowPresentationTests: XCTestCase {
    private struct Snapshot: Equatable {
        let time: String
        let text: String
        let fullModeName: String
        let compactModeName: String
        let polishStatus: String
        let isFlagged: Bool
        let accessibilityDescription: String

        init(_ presentation: DictationRowPresentation) {
            time = presentation.time
            text = presentation.text
            fullModeName = presentation.fullModeName
            compactModeName = presentation.compactModeName
            polishStatus = presentation.polishStatus.label
            isFlagged = presentation.isFlagged
            accessibilityDescription = presentation.accessibilityDescription
        }

        init(
            time: String,
            text: String,
            fullModeName: String,
            compactModeName: String,
            polishStatus: String,
            isFlagged: Bool,
            accessibilityDescription: String
        ) {
            self.time = time
            self.text = text
            self.fullModeName = fullModeName
            self.compactModeName = compactModeName
            self.polishStatus = polishStatus
            self.isFlagged = isFlagged
            self.accessibilityDescription = accessibilityDescription
        }
    }

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    func testPresentationProjectsCompactAndAccessibleRowIdentity() {
        let entry = HistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_783_499_700),
            text: "  First line\n second   line  ",
            rawText: "first line second line",
            isPolished: true,
            modeName: "My Extremely Long Custom Mode",
            wordCount: 4,
            sourceApp: nil,
            durationMs: nil,
            flagged: true,
            flagReason: nil
        )

        let presentation = DictationRowPresentation(entry: entry, calendar: calendar)

        XCTAssertEqual(
            Snapshot(presentation),
            Snapshot(
                time: "08:35",
                text: "First line second line",
                fullModeName: "My Extremely Long Custom Mode",
                compactModeName: "my extremely lon",
                polishStatus: "Polished",
                isFlagged: true,
                accessibilityDescription: "08:35, First line second line, "
                    + "Mode My Extremely Long Custom Mode, Polished, Flagged"
            )
        )
    }

    func testAccessibilityDescribesRawAndUnflaggedState() {
        let entry = HistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_783_499_700),
            text: "Raw words",
            rawText: "Raw words",
            isPolished: false,
            modeName: "Voice to Text",
            wordCount: 2,
            sourceApp: nil,
            durationMs: nil,
            flagged: false,
            flagReason: nil
        )

        let presentation = DictationRowPresentation(entry: entry, calendar: calendar)

        XCTAssertEqual(
            presentation.accessibilityDescription,
            "08:35, Raw words, Mode Voice to Text, Raw, Not flagged"
        )
    }

    func testTimeFormatterCacheKeepsTimeZonesIndependent() throws {
        let entry = HistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_783_499_700),
            text: "Words",
            rawText: "Words",
            isPolished: false,
            modeName: "Voice to Text",
            wordCount: 1,
            sourceApp: nil,
            durationMs: nil,
            flagged: false,
            flagReason: nil
        )
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var utcPlusTwo = Calendar(identifier: .gregorian)
        utcPlusTwo.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 2 * 60 * 60))

        let firstUTC = DictationRowPresentation(entry: entry, calendar: utc)
        let plusTwo = DictationRowPresentation(entry: entry, calendar: utcPlusTwo)
        let cachedUTC = DictationRowPresentation(entry: entry, calendar: utc)

        XCTAssertEqual([firstUTC.time, plusTwo.time, cachedUTC.time], ["08:35", "10:35", "08:35"])
    }
}
