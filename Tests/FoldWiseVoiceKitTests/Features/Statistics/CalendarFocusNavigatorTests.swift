import XCTest
@testable import FoldWiseVoiceKit

final class CalendarFocusNavigatorTests: XCTestCase {
    func testMoveUsesOneDayAndOneWeekStepsWithinEligibleBounds() {
        let dates = (1 ... 22).map { Date(timeIntervalSince1970: Double($0 * 86400)) }
        let navigator = CalendarFocusNavigator(eligibleDates: dates)

        XCTAssertEqual(
            [
                navigator.move(from: dates[10], direction: .left),
                navigator.move(from: dates[10], direction: .right),
                navigator.move(from: dates[10], direction: .up),
                navigator.move(from: dates[10], direction: .down),
            ],
            [dates[9], dates[11], dates[3], dates[17]]
        )
    }

    func testMoveStopsAtFirstDayAndToday() {
        let dates = (1 ... 22).map { Date(timeIntervalSince1970: Double($0 * 86400)) }
        let navigator = CalendarFocusNavigator(eligibleDates: dates)

        XCTAssertEqual(
            [
                navigator.move(from: dates[0], direction: .left),
                navigator.move(from: dates[3], direction: .up),
                navigator.move(from: dates[21], direction: .right),
                navigator.move(from: dates[18], direction: .down),
            ],
            [dates[0], dates[0], dates[21], dates[21]]
        )
    }

    func testRepairKeepsValidFocusAndRepairsInvalidFocusToToday() {
        let dates = (1 ... 22).map { Date(timeIntervalSince1970: Double($0 * 86400)) }
        let navigator = CalendarFocusNavigator(eligibleDates: dates)

        XCTAssertEqual(
            [navigator.repair(dates[10]), navigator.repair(Date.distantFuture), navigator.repair(nil)],
            [dates[10], dates[21], dates[21]]
        )
    }

    func testHoveredDateTemporarilyTakesDetailPrecedence() {
        let focused = Date(timeIntervalSince1970: 86400)
        let hovered = Date(timeIntervalSince1970: 172_800)

        XCTAssertEqual(
            [
                CalendarFocusNavigator.detailDate(hovered: hovered, focused: focused),
                CalendarFocusNavigator.detailDate(hovered: nil, focused: focused),
            ],
            [hovered, focused]
        )
    }
}
