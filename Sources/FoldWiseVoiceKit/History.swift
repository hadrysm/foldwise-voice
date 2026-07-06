// Dictation history: a text-only, on-device record of past dictation sessions
// (PRD #78). Persistence goes through the `HistoryStore` protocol so the
// append-only JSONL file can be swapped for a database later without touching
// the pane or the pipeline. No audio is ever written — history is text only.

import Foundation
import os

/// One recorded dictation session. Both `rawText` (pre-Polish transcript) and
/// `text` (what actually landed) are always kept: that pair powers the
/// raw↔polished distinction, "Copy raw", and re-running Polish on stored text
/// rather than re-decoded audio.
struct HistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date // row timestamp AND the day-grouping key
    var text: String // shown text: polished if Polish survived, else raw
    var rawText: String // pre-Polish transcript, always kept
    var isPolished: Bool // Polish ran AND survived the off-task check
    var modeName: String
    var wordCount: Int?
    var sourceApp: String? // frontmost app at insert time
    var durationMs: Int?
    var flagged: Bool
    var flagReason: String? // reserved; not captured in v1
}

/// The persistence seam for history. A best-effort store: `append` swallows
/// failures (a history write must never break a dictation session, PRD #78)
/// and `load` returns what it can read. `JSONLHistoryStore` is the production
/// conformer; tests drive it against a temp file injected via its initializer.
protocol HistoryStore: AnyObject {
    func append(_ entry: HistoryEntry)
    func load() -> [HistoryEntry]
}

/// Appends entries as one JSON object per line to a `history.jsonl` file —
/// separate from `modes.json`, which is hand-serialized to preserve Mode order
/// and must not carry churny append data. Reads and writes are best-effort:
/// nothing here throws to the caller, so a failed or blocked write degrades to
/// a no-op logged at the boundary rather than breaking the session.
final class JSONLHistoryStore: HistoryStore {
    private let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(url: URL) {
        self.url = url
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    /// `history.jsonl` alongside `modes.json` in Application Support.
    static var defaultURL: URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FoldWise Voice", isDirectory: true)
        return support.appendingPathComponent("history.jsonl")
    }

    func append(_ entry: HistoryEntry) {
        do {
            // JSONEncoder emits a single line (newlines inside strings are
            // escaped), so one entry maps to exactly one JSONL line.
            let data = try encoder.encode(entry)
            var line = data
            line.append(0x0A) // "\n"
            let fm = FileManager.default
            if fm.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try fm.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try line.write(to: url, options: .atomic)
            }
        } catch {
            Log.history.error(
                "History append skipped: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func load() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        var entries: [HistoryEntry] = []
        // `split` drops empty subsequences, so a trailing newline or blank line
        // is ignored; a single malformed line is skipped, not fatal.
        for line in data.split(separator: 0x0A) {
            if let entry = try? decoder.decode(HistoryEntry.self, from: Data(line)) {
                entries.append(entry)
            }
        }
        return entries
    }
}
