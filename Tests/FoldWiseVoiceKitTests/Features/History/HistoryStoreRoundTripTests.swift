// Round-trip tests for JSONLHistoryStore: append → load must return exactly
// what was written, in order; a blocked write degrades to a best-effort no-op
// rather than throwing. Driven against a temp file injected via the
// initializer, following the ConfigRoundTripTests prior art.

import XCTest
@testable import FoldWiseVoiceKit

final class HistoryStoreRoundTripTests: XCTestCase {
    func testRetentionDaysResolveKnownAndUnknownValues() {
        XCTAssertEqual(
            [RetentionWindow(days: 7), RetentionWindow(days: 30), RetentionWindow(days: 12)],
            [.sevenDays, .thirtyDays, .default]
        )
    }

    /// XCTest instantiates the case once per test method, so each test gets
    /// its own scratch directory.
    private let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("foldwise-history-tests-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    private var storeURL: URL {
        dir.appendingPathComponent("history.jsonl")
    }

    /// Whole-second dates so JSON round-trips are exact and equatable.
    private func entry(
        secondsSince1970: TimeInterval, text: String, isPolished: Bool = false
    ) -> HistoryEntry {
        HistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: secondsSince1970),
            text: text,
            rawText: text + " (raw)",
            isPolished: isPolished,
            modeName: "Clean",
            wordCount: text.split(whereSeparator: { $0.isWhitespace }).count,
            sourceApp: "TextEdit",
            durationMs: 1200,
            flagged: false,
            flagReason: nil
        )
    }

    func testAppendThenLoadReturnsTheEntry() {
        let store = JSONLHistoryStore(url: storeURL)
        let written = entry(secondsSince1970: 1_700_000_000, text: "hello world", isPolished: true)

        store.append(written)

        XCTAssertEqual(store.load(), [written])
    }

    func testStableModeIDRoundTrips() {
        let store = JSONLHistoryStore(url: storeURL)
        let modeID = ModeID.random()
        var written = entry(secondsSince1970: 1_700_000_000, text: "identified")
        written.modeID = modeID

        store.append(written)

        XCTAssertEqual(store.load().first?.modeID, modeID)
    }

    func testDictationSessionTimingRoundTrips() {
        let store = JSONLHistoryStore(url: storeURL)
        var written = entry(secondsSince1970: 1_700_000_000, text: "measured")
        written.timing = DictationSessionTiming(
            totalMilliseconds: 412.5,
            queuedMilliseconds: 2.5,
            transcribeMilliseconds: 120,
            polishMilliseconds: 220,
            polishServerMilliseconds: 200,
            polishModelLoadMilliseconds: 80,
            polishPromptEvalMilliseconds: 20,
            polishGenerationMilliseconds: 100,
            insertMilliseconds: 52,
            serialTailMilliseconds: 70
        )

        store.append(written)

        XCTAssertEqual(store.load().first?.timing, written.timing)
    }

    func testLegacyNameOnlyEntryWithoutModeIDStillLoads() throws {
        let legacy = entry(secondsSince1970: 1_700_000_000, text: "legacy")
        var line = try JSONEncoder().encode(legacy)
        line.append(0x0A)
        try line.write(to: storeURL)

        XCTAssertEqual(JSONLHistoryStore(url: storeURL).load().first?.modeName, "Clean")
    }

    func testMultipleAppendsLoadInAppendOrder() {
        let store = JSONLHistoryStore(url: storeURL)
        let first = entry(secondsSince1970: 1_700_000_000, text: "first")
        let second = entry(secondsSince1970: 1_700_000_060, text: "second")
        let third = entry(secondsSince1970: 1_700_000_120, text: "third")

        store.append(first)
        store.append(second)
        store.append(third)

        XCTAssertEqual(store.load(), [first, second, third])
    }

    func testAppendPreservesEmbeddedNewlinesAndQuotes() {
        let store = JSONLHistoryStore(url: storeURL)
        let written = entry(
            secondsSince1970: 1_700_000_000,
            text: "line one\nline \"two\"\ntab\there"
        )

        store.append(written)

        XCTAssertEqual(store.load(), [written])
    }

    func testLoadOnMissingFileReturnsEmpty() {
        let store = JSONLHistoryStore(url: storeURL)
        XCTAssertEqual(store.load(), [])
    }

    /// A separate store instance sees entries a prior one appended, because the
    /// state lives in the file — the seam other panes read through.
    func testAppendSurvivesAcrossStoreInstances() {
        let written = entry(secondsSince1970: 1_700_000_000, text: "persisted")
        JSONLHistoryStore(url: storeURL).append(written)

        XCTAssertEqual(JSONLHistoryStore(url: storeURL).load(), [written])
    }

    /// A write to an unwritable path (parent is a file, not a directory) must
    /// not throw — it degrades to a no-op, so a failing history write can never
    /// break a dictation session (PRD #78).
    func testAppendToBlockedPathIsBestEffortNoOp() throws {
        let blocker = dir.appendingPathComponent("blocker")
        try Data("not a directory".utf8).write(to: blocker)
        let store = JSONLHistoryStore(url: blocker.appendingPathComponent("history.jsonl"))

        store.append(entry(secondsSince1970: 1_700_000_000, text: "dropped"))

        XCTAssertEqual(store.load(), [])
    }

    // MARK: - delete-one and clear-all (PRD #78, slice 2)

    func testDeleteRemovesExactlyTheTargetEntry() {
        let store = JSONLHistoryStore(url: storeURL)
        let first = entry(secondsSince1970: 1_700_000_000, text: "first")
        let second = entry(secondsSince1970: 1_700_000_060, text: "second")
        let third = entry(secondsSince1970: 1_700_000_120, text: "third")
        store.append(first)
        store.append(second)
        store.append(third)

        store.delete(id: second.id)

        XCTAssertEqual(store.load(), [first, third])
    }

    func testDeleteUnknownIdLeavesEntriesUnchanged() {
        let store = JSONLHistoryStore(url: storeURL)
        let only = entry(secondsSince1970: 1_700_000_000, text: "only")
        store.append(only)

        store.delete(id: UUID())

        XCTAssertEqual(store.load(), [only])
    }

    /// The whole-file rewrite is what a second store instance reads back, so
    /// deletion is durable, not just an in-memory prune.
    func testDeletePersistsAcrossStoreInstances() {
        let kept = entry(secondsSince1970: 1_700_000_000, text: "keep")
        let removed = entry(secondsSince1970: 1_700_000_060, text: "remove")
        let writer = JSONLHistoryStore(url: storeURL)
        writer.append(kept)
        writer.append(removed)

        JSONLHistoryStore(url: storeURL).delete(id: removed.id)

        XCTAssertEqual(JSONLHistoryStore(url: storeURL).load(), [kept])
    }

    func testClearAllLeavesTheStoreEmpty() {
        let store = JSONLHistoryStore(url: storeURL)
        store.append(entry(secondsSince1970: 1_700_000_000, text: "first"))
        store.append(entry(secondsSince1970: 1_700_000_060, text: "second"))

        store.clearAll()

        XCTAssertEqual(store.load(), [])
    }

    /// After clear-all a fresh append starts a clean file — clearing doesn't
    /// leave residue that resurrects on the next write.
    func testClearAllThenAppendStartsFresh() {
        let store = JSONLHistoryStore(url: storeURL)
        store.append(entry(secondsSince1970: 1_700_000_000, text: "old"))
        store.clearAll()

        let fresh = entry(secondsSince1970: 1_700_000_060, text: "new")
        store.append(fresh)

        XCTAssertEqual(store.load(), [fresh])
    }

    // MARK: - update one (PRD #78, slice 5)

    /// Toggling a flag persists: the store replaces the matching entry, and a
    /// separate instance reads the new `flagged` back — the round-trip the
    /// Flag action relies on.
    func testUpdatePersistsFlaggedAcrossStoreInstances() {
        var written = entry(secondsSince1970: 1_700_000_000, text: "bookmark me")
        JSONLHistoryStore(url: storeURL).append(written)

        written.flagged = true
        JSONLHistoryStore(url: storeURL).update(written)

        XCTAssertEqual(JSONLHistoryStore(url: storeURL).load(), [written])
    }

    /// Updating one entry rewrites only that row, leaving its neighbours and
    /// their order untouched.
    func testUpdateReplacesOnlyTheMatchingEntry() {
        let store = JSONLHistoryStore(url: storeURL)
        let first = entry(secondsSince1970: 1_700_000_000, text: "first")
        var second = entry(secondsSince1970: 1_700_000_060, text: "second")
        let third = entry(secondsSince1970: 1_700_000_120, text: "third")
        store.append(first)
        store.append(second)
        store.append(third)

        second.text = "second edited"
        store.update(second)

        XCTAssertEqual(store.load(), [first, second, third])
    }

    func testUpdateUnknownIdLeavesEntriesUnchanged() {
        let store = JSONLHistoryStore(url: storeURL)
        let only = entry(secondsSince1970: 1_700_000_000, text: "only")
        store.append(only)

        store.update(entry(secondsSince1970: 1_700_000_060, text: "ghost"))

        XCTAssertEqual(store.load(), [only])
    }

    // MARK: - append observers (PRD #78, slice 7)

    /// The live-update contract: an appended entry is delivered to a registered
    /// observer, so an open History pane can prepend it without polling.
    /// Follows the ConfigChangePropagationTests observer prior art.
    func testAppendNotifiesObserverWithTheEntry() {
        let store = JSONLHistoryStore(url: storeURL)
        var received: [HistoryEntry] = []
        store.onAppend { received.append($0) }
        let written = entry(secondsSince1970: 1_700_000_000, text: "spoken just now")

        store.append(written)

        XCTAssertEqual(received, [written])
    }

    func testEachAppendNotifiesObserversInOrder() {
        let store = JSONLHistoryStore(url: storeURL)
        var received: [HistoryEntry] = []
        store.onAppend { received.append($0) }
        let first = entry(secondsSince1970: 1_700_000_000, text: "first")
        let second = entry(secondsSince1970: 1_700_000_060, text: "second")

        store.append(first)
        store.append(second)

        XCTAssertEqual(received, [first, second])
    }

    /// A best-effort no-op append (unwritable path) persisted nothing, so it
    /// must notify no observer — the pane must never prepend a dictation that
    /// never reached disk (mirrors the failed-save contract in
    /// ConfigChangePropagationTests).
    func testFailedAppendNotifiesNoObserver() throws {
        let blocker = dir.appendingPathComponent("blocker")
        try Data("not a directory".utf8).write(to: blocker)
        let store = JSONLHistoryStore(url: blocker.appendingPathComponent("history.jsonl"))
        var received: [HistoryEntry] = []
        store.onAppend { received.append($0) }

        store.append(entry(secondsSince1970: 1_700_000_000, text: "dropped"))

        XCTAssertTrue(received.isEmpty)
    }

    // MARK: - retention sweep (PRD #78, slice 4)

    /// A fixed reference "now" the sweep measures the window against, so the
    /// test is deterministic rather than depending on the wall clock.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func entry(daysBeforeNow days: Double, text: String) -> HistoryEntry {
        entry(secondsSince1970: now.timeIntervalSince1970 - days * 86400, text: text)
    }

    func testSweepDropsEntriesOlderThanWindow() {
        let store = JSONLHistoryStore(url: storeURL)
        let old = entry(daysBeforeNow: 40, text: "old")
        let recent = entry(daysBeforeNow: 5, text: "recent")
        store.append(old)
        store.append(recent)

        store.sweep(retention: .thirtyDays, now: now)

        XCTAssertEqual(store.load(), [recent])
    }

    func testSweepKeepsEntriesWithinWindow() {
        let store = JSONLHistoryStore(url: storeURL)
        let recent = entry(daysBeforeNow: 29, text: "recent")
        store.append(recent)

        store.sweep(retention: .thirtyDays, now: now)

        XCTAssertEqual(store.load(), [recent])
    }

    func testSweepForeverKeepsEverything() {
        let store = JSONLHistoryStore(url: storeURL)
        let ancient = entry(daysBeforeNow: 5000, text: "ancient")
        store.append(ancient)

        store.sweep(retention: .forever, now: now)

        XCTAssertEqual(store.load(), [ancient])
    }

    /// The sweep is best-effort: an unwritable path degrades to a no-op that
    /// doesn't throw, so a failing sweep can never break launch (PRD #78).
    func testSweepOnBlockedPathIsBestEffortNoOp() throws {
        let blocker = dir.appendingPathComponent("blocker")
        try Data("not a directory".utf8).write(to: blocker)
        let store = JSONLHistoryStore(url: blocker.appendingPathComponent("history.jsonl"))

        store.sweep(retention: .thirtyDays, now: now)

        XCTAssertEqual(store.load(), [])
    }
}
