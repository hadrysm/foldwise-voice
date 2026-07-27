// Re-run Polish (PRD #78, slice 6): HistoryReprocessor takes a stored entry's
// pre-Polish `rawText`, runs the Polish stage under a Mode the user picks
// through an injected polish seam, keeps the candidate only if it survives the
// off-task check, and overwrites + persists the row's text/isPolished/modeName.
// Driven against a real JSONLHistoryStore in a temp file so the "persisted"
// contract is exercised, following the HistoryStoreRoundTripTests prior art.
// Reprocessing operates on stored TEXT only — there is no audio path.

import XCTest
@testable import FoldWiseVoiceKit

final class HistoryReprocessorTests: XCTestCase {
    /// XCTest instantiates the case once per test method, so each test gets its
    /// own scratch directory.
    private let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("foldwise-reprocess-tests-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    private var storeURL: URL {
        dir.appendingPathComponent("history.jsonl")
    }

    /// An In-place Mode (expands: false), so the off-task check falls back on a
    /// low-overlap candidate via the strict-overlap rule — a deterministic
    /// fixture, mirroring PipelineRecordTests' `cleanMode`.
    private let cleanMode = Mode(
        name: "Clean", asrModel: "", llmModel: "llama3", systemPrompt: nil, vocab: [],
        expands: false
    )
    private let rawTranscript =
        "hey can you send the quarterly numbers over to the finance team when you get a chance"
    private let cleaned =
        "Hey, can you send the quarterly numbers over to the finance team when you get a chance?"

    private func storedEntry(
        text: String, rawText: String, isPolished: Bool, modeName: String = "Voice to Text"
    ) -> HistoryEntry {
        HistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            text: text,
            rawText: rawText,
            isPolished: isPolished,
            modeName: modeName,
            wordCount: text.split(whereSeparator: { $0.isWhitespace }).count,
            sourceApp: "TextEdit",
            durationMs: 1200,
            flagged: false,
            flagReason: nil
        )
    }

    // MARK: - a surviving polish overwrites the row

    func testRerunPolishOverwritesTextAndMarksPolishedWhenSurvives() async throws {
        let store = JSONLHistoryStore(url: storeURL)
        let entry = storedEntry(text: rawTranscript, rawText: rawTranscript, isPolished: false)
        store.append(entry)
        let reprocessor = HistoryReprocessor(store: store, polish: { _, _ in self.cleaned })

        let result = await reprocessor.rerunPolish(entry, mode: cleanMode)
        let updated = try XCTUnwrap(result)

        XCTAssertEqual(updated.text, cleaned)
        XCTAssertTrue(updated.isPolished)
    }

    func testRerunPolishPersistsTheUpdatedEntry() async throws {
        let store = JSONLHistoryStore(url: storeURL)
        let entry = storedEntry(text: rawTranscript, rawText: rawTranscript, isPolished: false)
        store.append(entry)
        let reprocessor = HistoryReprocessor(store: store, polish: { _, _ in self.cleaned })

        _ = await reprocessor.rerunPolish(entry, mode: cleanMode)

        let reloaded = try XCTUnwrap(JSONLHistoryStore(url: storeURL).load().first)
        XCTAssertEqual(reloaded.text, cleaned)
        XCTAssertTrue(reloaded.isPolished)
    }

    // MARK: - off-task fallback keeps the raw transcript

    func testRerunPolishFallsBackToRawWhenPolishGoesOffTask() async throws {
        let store = JSONLHistoryStore(url: storeURL)
        let entry = storedEntry(text: rawTranscript, rawText: rawTranscript, isPolished: false)
        store.append(entry)
        let reprocessor = HistoryReprocessor(store: store, polish: { _, _ in
            "Roses are red, violets are blue, a poem replies where a cleanup was due."
        })

        let result = await reprocessor.rerunPolish(entry, mode: cleanMode)
        let updated = try XCTUnwrap(result)

        XCTAssertEqual(updated.text, rawTranscript)
        XCTAssertFalse(updated.isPolished)
    }

    // MARK: - stored raw text is the input, never the displayed text (no audio)

    func testRerunPolishFeedsStoredRawTextToThePolishStage() async {
        let store = JSONLHistoryStore(url: storeURL)
        // A previously-polished entry: `text` differs from `rawText`. Re-run must
        // reshape the ORIGINAL raw transcript, not the already-polished text.
        let entry = storedEntry(
            text: "An earlier polish.", rawText: rawTranscript, isPolished: true, modeName: "Email"
        )
        store.append(entry)
        let box = InputBox()
        let reprocessor = HistoryReprocessor(store: store, polish: { input, _ in
            box.value = input
            return self.cleaned
        })

        _ = await reprocessor.rerunPolish(entry, mode: cleanMode)

        XCTAssertEqual(box.value, rawTranscript)
    }

    // MARK: - a transcript too short to polish skips the LLM and keeps the raw

    /// An LLM Mode picked on a transcript below `MIN_CHARS_FOR_LLM` must not
    /// reach the polish stage at all — the same short-input gate the live
    /// session applies — and resolves to the raw transcript marked unpolished.
    /// The menu offers every LLM Mode regardless of length, so this path is
    /// reachable from the UI.
    func testRerunPolishSkipsPolishForATooShortTranscript() async throws {
        let store = JSONLHistoryStore(url: storeURL)
        let short = "too short to polish"
        let entry = storedEntry(text: short, rawText: short, isPolished: false)
        store.append(entry)
        let box = InputBox()
        let reprocessor = HistoryReprocessor(store: store, polish: { input, _ in
            box.value = input
            return self.cleaned
        })

        let result = await reprocessor.rerunPolish(entry, mode: cleanMode)
        let updated = try XCTUnwrap(result)

        XCTAssertNil(box.value) // the polish seam was never called
        XCTAssertEqual(updated.text, short)
        XCTAssertFalse(updated.isPolished)
    }

    // MARK: - the chosen Mode is recorded as the row's producer

    func testRerunPolishRecordsTheChosenModeName() async throws {
        let store = JSONLHistoryStore(url: storeURL)
        let entry = storedEntry(
            text: rawTranscript, rawText: rawTranscript, isPolished: false, modeName: "Voice to Text"
        )
        store.append(entry)
        let reprocessor = HistoryReprocessor(store: store, polish: { _, _ in self.cleaned })

        let result = await reprocessor.rerunPolish(entry, mode: cleanMode)
        let updated = try XCTUnwrap(result)

        XCTAssertEqual(updated.modeName, "Clean")
    }
}

/// A reference box for capturing what the injected polish seam received, so a
/// test can assert Re-run Polish feeds it the stored raw transcript.
private final class InputBox {
    var value: String?
}
