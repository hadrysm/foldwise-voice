// The two pure streak rules (PRD #97), exercised apart from any storage the way
// `RetentionWindow` and `PolishStatus` are. `advance` folds a new dictation's
// day into the stored run (first entry = 1, same day = no-op, consecutive = +1,
// gap resets to 1); `display` decides what the pane shows (alive only when the
// last active day is today or yesterday). Both take a pinned `Calendar`, and a
// spring-forward day step proves the day arithmetic doesn't naively divide by
// 86400 seconds.

import XCTest
@testable import FoldWiseVoiceKit

final class StreakRulesTests: XCTestCase {
    /// A Gregorian calendar pinned to a fixed zone, so day bucketing does not
    /// depend on where the test happens to run.
    private func calendar(_ zone: String = "UTC") throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        return calendar
    }

    private func at(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, _ hour: Int) throws -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return try XCTUnwrap(calendar.date(from: components))
    }

    // MARK: - advance

    func testAdvanceFromNoRecordStartsAtOne() throws {
        let calendar = try calendar()
        let day = try at(calendar, 2026, 1, 1, 9)

        let advanced = StreakRules.advance(nil, on: day, calendar: calendar)

        XCTAssertEqual(advanced, StreakRecord(currentStreak: 1, lastActiveDay: calendar.startOfDay(for: day)))
    }

    /// A second dictation on the same calendar day is a no-op: the run neither
    /// grows nor resets, whatever the clock time.
    func testAdvanceSameDayIsNoOp() throws {
        let calendar = try calendar()
        let existing = StreakRecord(currentStreak: 3, lastActiveDay: try at(calendar, 2026, 1, 1, 8))

        let advanced = StreakRules.advance(existing, on: try at(calendar, 2026, 1, 1, 22), calendar: calendar)

        XCTAssertEqual(advanced, existing)
    }

    func testAdvanceNextConsecutiveDayIncrementsByOne() throws {
        let calendar = try calendar()
        let existing = StreakRecord(currentStreak: 3, lastActiveDay: try at(calendar, 2026, 1, 1, 8))
        let nextDay = try at(calendar, 2026, 1, 2, 10)

        let advanced = StreakRules.advance(existing, on: nextDay, calendar: calendar)

        XCTAssertEqual(advanced, StreakRecord(currentStreak: 4, lastActiveDay: calendar.startOfDay(for: nextDay)))
    }

    /// Any skipped day restarts the run at 1 on the new day — a streak is
    /// consecutive or it is nothing.
    func testAdvanceAfterAGapResetsToOne() throws {
        let calendar = try calendar()
        let existing = StreakRecord(currentStreak: 9, lastActiveDay: try at(calendar, 2026, 1, 1, 8))
        let afterGap = try at(calendar, 2026, 1, 4, 10) // two days skipped

        let advanced = StreakRules.advance(existing, on: afterGap, calendar: calendar)

        XCTAssertEqual(advanced, StreakRecord(currentStreak: 1, lastActiveDay: calendar.startOfDay(for: afterGap)))
    }

    /// A backwards day step (a clock rollback or a westward timezone move across
    /// midnight) is a no-op: it must not wipe a live run or drag `lastActiveDay`
    /// into the past. The stored record is returned unchanged, so a later dictation
    /// on the real current day still reads as the correct forward step rather than
    /// compounding the skew.
    func testAdvanceBackwardsClockStepIsNoOp() throws {
        let calendar = try calendar()
        let existing = StreakRecord(currentStreak: 5, lastActiveDay: try at(calendar, 2026, 1, 10, 8))
        let earlierDay = try at(calendar, 2026, 1, 8, 10) // two days before the stored day

        let advanced = StreakRules.advance(existing, on: earlierDay, calendar: calendar)

        XCTAssertEqual(advanced, existing)
    }

    /// The spring-forward day is only 23 hours long, so a consecutive-day step
    /// across it spans under 24 hours; the rule must still read it as +1, which a
    /// naive divide-by-86400 would miss (it would look like the same day).
    func testAdvanceAcrossDaylightSavingBoundaryStillIncrements() throws {
        let calendar = try calendar("America/New_York")
        let existing = StreakRecord(currentStreak: 2, lastActiveDay: try at(
            calendar,
            2026,
            3,
            8,
            1
        )) // before the 02:00 jump
        let nextDay = try at(calendar, 2026, 3, 9, 6)

        let advanced = StreakRules.advance(existing, on: nextDay, calendar: calendar)

        XCTAssertEqual(advanced.currentStreak, 3)
    }

    /// A record at `Int.max` — reachable only via a corrupt or hand-edited
    /// `stats.json`, which `readRecord` decodes without complaint — must saturate
    /// on the next consecutive day rather than trap on integer overflow. A trapping
    /// `+ 1` here would crash the session, so the increment clamps at `Int.max`.
    func testAdvanceSaturatesAtIntMax() throws {
        let calendar = try calendar()
        let existing = StreakRecord(currentStreak: Int.max, lastActiveDay: try at(calendar, 2026, 1, 1, 8))
        let nextDay = try at(calendar, 2026, 1, 2, 10)

        let advanced = StreakRules.advance(existing, on: nextDay, calendar: calendar)

        XCTAssertEqual(advanced, StreakRecord(currentStreak: Int.max, lastActiveDay: calendar.startOfDay(for: nextDay)))
    }

    /// A hand-edited or corrupt record can decode with a nonpositive count. The
    /// next real dictation must repair it to a valid one-day run rather than
    /// perpetuating an impossible zero or negative streak.
    func testAdvanceRepairsNegativeStoredCount() throws {
        let calendar = try calendar()
        let existing = StreakRecord(currentStreak: -1, lastActiveDay: try at(calendar, 2026, 1, 1, 8))
        let nextDay = try at(calendar, 2026, 1, 2, 10)

        let advanced = StreakRules.advance(existing, on: nextDay, calendar: calendar)

        XCTAssertEqual(advanced, StreakRecord(currentStreak: 1, lastActiveDay: calendar.startOfDay(for: nextDay)))
    }

    func testAdvanceRepairsZeroStoredCount() throws {
        let calendar = try calendar()
        let existing = StreakRecord(currentStreak: 0, lastActiveDay: try at(calendar, 2026, 1, 1, 8))
        let nextDay = try at(calendar, 2026, 1, 2, 10)

        let advanced = StreakRules.advance(existing, on: nextDay, calendar: calendar)

        XCTAssertEqual(advanced, StreakRecord(currentStreak: 1, lastActiveDay: calendar.startOfDay(for: nextDay)))
    }

    func testAdvancePreservesInvalidRecordDuringBackwardsClockStep() throws {
        let calendar = try calendar()
        let existing = StreakRecord(currentStreak: 0, lastActiveDay: try at(calendar, 2026, 1, 10, 8))
        let earlierDay = try at(calendar, 2026, 1, 8, 10)

        let advanced = StreakRules.advance(existing, on: earlierDay, calendar: calendar)

        XCTAssertEqual(advanced, existing)
    }

    // MARK: - display

    func testDisplayIsNilForNoRecord() throws {
        let calendar = try calendar()

        XCTAssertNil(StreakRules.display(nil, now: try at(calendar, 2026, 1, 1, 9), calendar: calendar))
    }

    func testDisplayShowsRunWhenLastActiveIsToday() throws {
        let calendar = try calendar()
        let record = StreakRecord(currentStreak: 5, lastActiveDay: try at(calendar, 2026, 1, 10, 8))

        let shown = StreakRules.display(record, now: try at(calendar, 2026, 1, 10, 21), calendar: calendar)

        XCTAssertEqual(shown, 5)
    }

    func testDisplayShowsRunWhenLastActiveWasYesterday() throws {
        let calendar = try calendar()
        let record = StreakRecord(currentStreak: 5, lastActiveDay: try at(calendar, 2026, 1, 9, 8))

        let shown = StreakRules.display(record, now: try at(calendar, 2026, 1, 10, 9), calendar: calendar)

        XCTAssertEqual(shown, 5)
    }

    /// A skipped day lapses the run: the record still holds a count on disk, but
    /// `display` reports `nil` so the pane reads "No active streak" rather than
    /// bragging about a broken run.
    func testDisplayIsNilWhenTheRunHasLapsed() throws {
        let calendar = try calendar()
        let record = StreakRecord(currentStreak: 5, lastActiveDay: try at(calendar, 2026, 1, 8, 8))

        let shown = StreakRules
            .display(record, now: try at(calendar, 2026, 1, 10, 9), calendar: calendar) // two days on

        XCTAssertNil(shown)
    }

    /// Yesterday is still alive across the spring-forward boundary: a run last
    /// active March 8 is shown on March 9 even though under 24 hours separate the
    /// day starts.
    func testDisplayYesterdayHoldsAcrossDaylightSavingBoundary() throws {
        let calendar = try calendar("America/New_York")
        let record = StreakRecord(currentStreak: 4, lastActiveDay: try at(calendar, 2026, 3, 8, 1))

        let shown = StreakRules.display(record, now: try at(calendar, 2026, 3, 9, 6), calendar: calendar)

        XCTAssertEqual(shown, 4)
    }
}
