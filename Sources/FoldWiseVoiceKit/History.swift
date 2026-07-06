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

/// How long dictation history is kept before the launch sweep deletes it
/// (PRD #78). Persisted as a day count (`.forever` as 0) alongside the app's
/// other settings and offered as a picker in the History pane. This is a
/// control distinct from the "Save dictation history" on/off switch:
/// `.forever` keeps everything, it does not turn saving off.
enum RetentionWindow: Int, CaseIterable, Identifiable {
    case sevenDays = 7
    case thirtyDays = 30
    case ninetyDays = 90
    case forever = 0

    static let `default` = RetentionWindow.thirtyDays

    var id: Int {
        rawValue
    }

    /// Persisted day count; 0 means keep everything.
    var days: Int {
        rawValue
    }

    /// Reconstruct from the persisted day count, falling back to the default
    /// for an absent or unrecognized value.
    init(days: Int) {
        self = RetentionWindow(rawValue: days) ?? .default
    }

    /// Oldest age an entry may reach before the sweep drops it, or nil for
    /// `.forever` — the sweep leaves a Forever store untouched.
    var maxAge: TimeInterval? {
        self == .forever ? nil : TimeInterval(days) * 86400
    }

    var label: String {
        switch self {
        case .sevenDays: "7 days"
        case .thirtyDays: "30 days"
        case .ninetyDays: "90 days"
        case .forever: "Forever"
        }
    }
}

/// The persistence seam for history. A best-effort store: mutations swallow
/// failures (a history write must never break a dictation session, PRD #78)
/// and `load` returns what it can read. `JSONLHistoryStore` is the production
/// conformer; tests drive it against a temp file injected via its initializer.
protocol HistoryStore: AnyObject {
    func append(_ entry: HistoryEntry)
    func load() -> [HistoryEntry]
    /// Replaces the stored entry sharing `entry.id`, keeping the others and
    /// their order; a no-op if none matches. The persist path for toggling
    /// `flagged` and for Re-run Polish overwriting `text`/`isPolished`.
    func update(_ entry: HistoryEntry)
    /// Removes exactly the entry with `id`; a no-op if none matches.
    func delete(id: UUID)
    /// Empties the store, leaving no residue for the next append.
    func clearAll()
    /// Deletes entries older than `window` measured from `now`; a `.forever`
    /// window leaves the store untouched. Best-effort like the other mutations.
    func sweep(retention window: RetentionWindow, now: Date)
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

    /// Replaces the matching row by rewriting the whole file. Rewriting
    /// everything (rather than editing in place) is acceptable at the volumes
    /// this feature targets and is what the eventual DB backend removes.
    func update(_ entry: HistoryEntry) {
        let all = load()
        guard all.contains(where: { $0.id == entry.id }) else { return }
        rewrite(all.map { $0.id == entry.id ? entry : $0 })
    }

    /// Deletes by rewriting the whole file without the target row.
    func delete(id: UUID) {
        rewrite(load().filter { $0.id != id })
    }

    func clearAll() {
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
        } catch {
            Log.history.error(
                "History clear-all skipped: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func sweep(retention window: RetentionWindow, now: Date) {
        guard let maxAge = window.maxAge else { return } // .forever — keep everything
        let cutoff = now.addingTimeInterval(-maxAge)
        let all = load()
        let kept = all.filter { $0.createdAt >= cutoff }
        guard kept.count != all.count else { return } // nothing expired — no rewrite
        rewrite(kept)
    }

    /// Best-effort whole-file replacement shared by the mutating operations: a
    /// failure is logged and swallowed rather than thrown, keeping the store's
    /// no-throw contract (PRD #78).
    private func rewrite(_ entries: [HistoryEntry]) {
        do {
            var data = Data()
            for entry in entries {
                data.append(try encoder.encode(entry))
                data.append(0x0A) // "\n" — one entry per JSONL line
            }
            let fm = FileManager.default
            try fm.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            Log.history.error(
                "History rewrite skipped: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

/// The History pane's list filter, kept a pure function so its matching rules
/// are unit-tested apart from the (untested) SwiftUI view (PRD #78). Narrows to
/// flagged rows when `flaggedOnly` is set, then keeps rows whose polished `text`
/// or raw `rawText` contains `query` — case-insensitively, so a dictation is
/// found by any words it contained whichever version the user remembers. A
/// blank query matches every row. Order-preserving.
enum HistoryFilter {
    static func apply(
        to entries: [HistoryEntry], query: String, flaggedOnly: Bool
    ) -> [HistoryEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            if flaggedOnly, !entry.flagged { return false }
            guard !needle.isEmpty else { return true }
            return entry.text.localizedCaseInsensitiveContains(needle)
                || entry.rawText.localizedCaseInsensitiveContains(needle)
        }
    }
}
