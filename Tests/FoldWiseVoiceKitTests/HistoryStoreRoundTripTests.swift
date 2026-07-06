// Round-trip tests for JSONLHistoryStore: append → load must return exactly
// what was written, in order; a blocked write degrades to a best-effort no-op
// rather than throwing. Driven against a temp file injected via the
// initializer, following the ConfigRoundTripTests prior art.

import XCTest
@testable import FoldWiseVoiceKit

final class HistoryStoreRoundTripTests: XCTestCase {
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
}
