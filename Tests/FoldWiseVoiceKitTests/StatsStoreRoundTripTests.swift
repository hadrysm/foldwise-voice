// Round-trip tests for JSONStatsStore (PRD #97): advance → load must return the
// folded streak record; a blocked write degrades to a best-effort no-op rather
// than throwing (a stats write can never break a dictation session); and reset
// drops the run so load returns nil. Driven against a temp file injected via the
// initializer, following the HistoryStoreRoundTripTests prior art. The pure
// advance/display arithmetic is covered in StreakRulesTests; here we prove only
// that the store persists, degrades, and resets.

import XCTest
@testable import FoldWiseVoiceKit

final class StatsStoreRoundTripTests: XCTestCase {
    /// XCTest instantiates the case once per test method, so each test gets its
    /// own scratch directory.
    private let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("foldwise-stats-tests-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    private var storeURL: URL {
        dir.appendingPathComponent("stats.json")
    }

    /// A Gregorian calendar pinned to UTC, so the day the store buckets an entry
    /// into does not depend on where the test runs.
    private func calendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        return calendar
    }

    private func day(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int) throws -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 9
        return try XCTUnwrap(calendar.date(from: components))
    }

    func testDefaultURLKeepsStatsBesideOtherApplicationSupportData() {
        XCTAssertEqual(JSONStatsStore.defaultURL.lastPathComponent, "stats.json")
        XCTAssertEqual(JSONStatsStore.defaultURL.deletingLastPathComponent().lastPathComponent, "FoldWise Voice")
    }

    func testLoadOnMissingFileReturnsNil() {
        XCTAssertNil(JSONStatsStore(url: storeURL).load())
    }

    /// A present-but-undecodable file is the other nil branch of `readRecord`: the
    /// `try?` decode swallows the failure so a corrupt `stats.json` loads as nil
    /// rather than throwing — a best-effort load never breaks a session.
    func testLoadOnCorruptFileReturnsNil() throws {
        try Data("{ not valid json".utf8).write(to: storeURL)

        XCTAssertNil(JSONStatsStore(url: storeURL).load())
    }

    /// A first advance persists a run of 1 at the entry's day start — the
    /// round-trip the pane reads through.
    func testFirstAdvancePersistsRunOfOne() throws {
        let calendar = try calendar()
        let store = JSONStatsStore(url: storeURL)
        let today = try day(calendar, 2026, 1, 1)

        store.advance(on: today, calendar: calendar)

        XCTAssertEqual(store.load(), StreakRecord(currentStreak: 1, lastActiveDay: calendar.startOfDay(for: today)))
    }

    /// Consecutive-day advances accumulate on disk, and a separate store instance
    /// reads the run back — the state lives in the file, so the streak survives
    /// process restarts (and thus outlives retention pruning that never touches
    /// this file).
    func testConsecutiveAdvancesAccumulateAcrossStoreInstances() throws {
        let calendar = try calendar()
        JSONStatsStore(url: storeURL).advance(on: try day(calendar, 2026, 1, 1), calendar: calendar)
        JSONStatsStore(url: storeURL).advance(on: try day(calendar, 2026, 1, 2), calendar: calendar)

        let loaded = JSONStatsStore(url: storeURL).load()

        XCTAssertEqual(
            loaded,
            StreakRecord(currentStreak: 2, lastActiveDay: calendar.startOfDay(for: try day(calendar, 2026, 1, 2)))
        )
    }

    /// reset drops the run so a subsequent load returns nil — the deliberate-wipe
    /// behavior, verified at the store level rather than through the controller.
    func testResetDropsTheStoredRun() throws {
        let calendar = try calendar()
        let store = JSONStatsStore(url: storeURL)
        store.advance(on: try day(calendar, 2026, 1, 1), calendar: calendar)

        store.reset()

        XCTAssertNil(store.load())
    }

    /// A wipe wins an advance that raced it: `clearHistory` erases two
    /// independently-locked stores in sequence, so a dictation append can land its
    /// `advance` after `reset` deleted `stats.json`. The `clearedThrough` guard
    /// skips any advance whose entry predates the wipe, so the entry that `reset`
    /// just erased is not resurrected — `load` stays nil (PRD #97). A fixed clock
    /// makes the ordering deterministic: the wipe instant sits after the entry day.
    func testAdvanceAfterResetDoesNotResurrectAPreResetEntry() throws {
        let calendar = try calendar()
        let resetInstant = try day(calendar, 2026, 6, 1)
        let store = JSONStatsStore(url: storeURL, now: { resetInstant })
        let earlyDay = try day(calendar, 2026, 1, 1)
        store.advance(on: earlyDay, calendar: calendar) // seeds the run

        store.reset() // stamps clearedThrough = resetInstant, deletes the file
        store.advance(on: earlyDay, calendar: calendar) // the raced, pre-wipe append

        XCTAssertNil(store.load())
    }

    /// A dictation recorded after the wipe still starts a fresh run: its entry day
    /// sits at or after `clearedThrough`, so it clears the guard and re-seeds the
    /// streak from nil → 1 exactly as a first-ever advance would (PRD #97).
    func testAdvanceOnANewEntryAfterResetStartsAFreshRun() throws {
        let calendar = try calendar()
        let resetInstant = try day(calendar, 2026, 6, 1)
        let store = JSONStatsStore(url: storeURL, now: { resetInstant })

        store.reset() // clearedThrough = resetInstant
        let laterDay = try day(calendar, 2026, 7, 1)
        store.advance(on: laterDay, calendar: calendar)

        XCTAssertEqual(
            store.load(),
            StreakRecord(currentStreak: 1, lastActiveDay: calendar.startOfDay(for: laterDay))
        )
    }

    /// An advance to an unwritable path (parent is a file, not a directory) must
    /// not throw — it degrades to a no-op, so a failing stats write can never
    /// break a dictation session (PRD #97).
    func testAdvanceToBlockedPathIsBestEffortNoOp() throws {
        let calendar = try calendar()
        let blocker = dir.appendingPathComponent("blocker")
        try Data("not a directory".utf8).write(to: blocker)
        let store = JSONStatsStore(url: blocker.appendingPathComponent("stats.json"))

        store.advance(on: try day(calendar, 2026, 1, 1), calendar: calendar)

        XCTAssertNil(store.load())
    }
}
