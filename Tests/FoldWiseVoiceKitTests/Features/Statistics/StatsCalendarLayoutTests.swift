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

    func testHoverCrossfadePlanScopesTransitionToChangedDay() {
        let dates = [
            Date(timeIntervalSinceReferenceDate: 1),
            Date(timeIntervalSinceReferenceDate: 2),
        ]
        let layout = StatsCalendarLayout(
            width: 736,
            leadingColumnOffset: 3,
            dayCount: dates.count
        )

        XCTAssertEqual(
            StatsCalendarCrossfadePlan.hoverFrames(
                dates: dates,
                from: nil,
                to: dates[0],
                layout: layout,
                reduceMotion: false
            ),
            [layout.dayFrame(at: 0)]
        )
    }

    func testHoverCrossfadePlanIsImmediateWithReducedMotion() {
        let date = Date(timeIntervalSinceReferenceDate: 1)
        let layout = StatsCalendarLayout(
            width: 736,
            leadingColumnOffset: 3,
            dayCount: 1
        )

        XCTAssertTrue(StatsCalendarCrossfadePlan.hoverFrames(
            dates: [date],
            from: nil,
            to: date,
            layout: layout,
            reduceMotion: true
        ).isEmpty)
    }
}
