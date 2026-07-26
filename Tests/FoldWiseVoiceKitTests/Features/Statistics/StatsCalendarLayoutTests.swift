import XCTest
@testable import FoldWiseVoiceKit

final class StatsCalendarLayoutTests: XCTestCase {
    func testLayoutKeepsSevenEqualColumns() {
        let layout = StatsCalendarLayout(
            width: 736,
            leadingColumnOffset: 3,
            dayCount: 31
        )

        XCTAssertEqual(
            (0 ..< 7).map { layout.weekdayFrame(at: $0).width },
            Array(repeating: 100, count: 7)
        )
    }

    func testLayoutPlacesFirstDayAfterLeadingColumns() {
        let layout = StatsCalendarLayout(
            width: 736,
            leadingColumnOffset: 3,
            dayCount: 31
        )

        XCTAssertEqual(
            layout.dayFrame(at: 0),
            CGRect(x: 318, y: 17, width: 100, height: 44)
        )
    }

    func testLayoutWrapsLastDayIntoItsCalendarRow() {
        let layout = StatsCalendarLayout(
            width: 736,
            leadingColumnOffset: 3,
            dayCount: 31
        )

        XCTAssertEqual(
            layout.dayFrame(at: 30),
            CGRect(x: 530, y: 217, width: 100, height: 44)
        )
    }

    func testLayoutHeightFitsOnlyRequiredCalendarRows() {
        let layout = StatsCalendarLayout(
            width: 736,
            leadingColumnOffset: 3,
            dayCount: 31
        )

        XCTAssertEqual(layout.height, 261)
    }
}
