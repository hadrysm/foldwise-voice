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
    var modeName: String // frozen display fallback retained after rename/delete
    var modeID: ModeID? // nil for Voice to Text and legacy pre-ID rows
    var wordCount: Int?
    var sourceApp: String? // frontmost app at insert time
    var durationMs: Int?
    var flagged: Bool
    var flagReason: String? // reserved; not captured in v1
}

/// What a history row's shown `text` actually is, for the row's honesty
/// indicator (PRD #78, story 28). Derived purely from `isPolished`: `.polished`
/// only when Polish ran AND survived the off-task check; otherwise `.raw` — the
/// shown text is the pre-Polish transcript, whether because the Mode does not
/// polish or because Polish went Off-task and fell back to it. Kept a pure
/// mapping (like `RetentionWindow.label`) so the rule is unit-tested apart from
/// the untested SwiftUI view, and so a row can never claim to be polished when
/// it fell back to raw.
enum PolishStatus {
    case polished
    case raw

    init(_ entry: HistoryEntry) {
        self = entry.isPolished ? .polished : .raw
    }

    /// One word, matching the app's raw↔polished vocabulary ("Copy raw").
    var label: String {
        switch self {
        case .polished: "Polished"
        case .raw: "Raw"
        }
    }
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
    @discardableResult
    func update(_ entry: HistoryEntry) -> Bool
    /// Removes exactly the entry with `id`; a no-op if none matches.
    @discardableResult
    func delete(id: UUID) -> Bool
    /// Empties the store, leaving no residue for the next append.
    @discardableResult
    func clearAll() -> Bool
    /// Deletes entries older than `window` measured from `now`; a `.forever`
    /// window leaves the store untouched. Best-effort like the other mutations.
    func sweep(retention window: RetentionWindow, now: Date)
    /// Registers `observer`, called with each entry as it is appended, so an
    /// open History pane can prepend a just-spoken dictation live without
    /// polling the file — the store owns change propagation, following Config
    /// (ADR-0003). A failed best-effort append notifies no one. Observers are
    /// app-lifetime, so the list is append-only and never unsubscribed.
    func onAppend(_ observer: @escaping (HistoryEntry) -> Void)
}

/// Appends entries as one JSON object per line to a `history.jsonl` file —
/// separate from `config.json`, which preserves the committed Mode array order
/// and must not carry churny append data. Reads and writes are best-effort:
/// nothing here throws to the caller, so a failed or blocked write degrades to
/// a no-op logged at the boundary rather than breaking the session.
final class JSONLHistoryStore: HistoryStore {
    private let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    /// Append observers, registered once at startup and app-lifetime, so there
    /// is no unsubscribe path (AppMain wires the pane before the hotkey listener
    /// starts). Access still goes through `lock` so registration and the
    /// snapshot taken in `append` can't race.
    private var appendObservers: [(HistoryEntry) -> Void] = []
    /// Serializes every file operation and observer access. The pipeline appends
    /// off the main thread while the History pane mutates the store on the main
    /// actor, so an `append` must never interleave with an
    /// `update`/`delete`/`sweep` load-then-rewrite — otherwise the rewrite would
    /// silently drop the just-appended entry.
    private let lock = NSLock()

    init(url: URL) {
        self.url = url
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    /// `history.jsonl` alongside `config.json` in Application Support.
    static var defaultURL: URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FoldWise Voice", isDirectory: true)
        return support.appendingPathComponent("history.jsonl")
    }

    func append(_ entry: HistoryEntry) {
        lock.lock()
        let persisted = writeAppend(entry)
        // Snapshot under the lock so a concurrent `onAppend` can't mutate the
        // array mid-loop.
        let observers = persisted ? appendObservers : []
        lock.unlock()
        // Only after the entry is on disk, and outside the lock: an open pane
        // must never prepend a dictation the store failed to persist (ADR-0003).
        // May run off the main thread (the pipeline records off-main), so
        // observers hop themselves.
        for observer in observers {
            observer(entry)
        }
    }

    func onAppend(_ observer: @escaping (HistoryEntry) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        appendObservers.append(observer)
    }

    func load() -> [HistoryEntry] {
        lock.lock()
        defer { lock.unlock() }
        return readEntries()
    }

    /// Replaces the matching row by rewriting the whole file. Rewriting
    /// everything (rather than editing in place) is acceptable at the volumes
    /// this feature targets and is what the eventual DB backend removes.
    @discardableResult
    func update(_ entry: HistoryEntry) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let all = readEntries()
        guard all.contains(where: { $0.id == entry.id }) else { return false }
        return rewrite(all.map { $0.id == entry.id ? entry : $0 })
    }

    /// Deletes by rewriting the whole file without the target row.
    @discardableResult
    func delete(id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let all = readEntries()
        guard all.contains(where: { $0.id == id }) else { return false }
        return rewrite(all.filter { $0.id != id })
    }

    @discardableResult
    func clearAll() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
            return true
        } catch {
            Log.history.error(
                "History clear-all skipped: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    func sweep(retention window: RetentionWindow, now: Date) {
        guard let maxAge = window.maxAge else { return } // .forever — keep everything
        lock.lock()
        defer { lock.unlock() }
        let cutoff = now.addingTimeInterval(-maxAge)
        let all = readEntries()
        let kept = all.filter { $0.createdAt >= cutoff }
        guard kept.count != all.count else { return } // nothing expired — no rewrite
        _ = rewrite(kept)
    }

    /// Writes one JSONL line for `entry`, returning whether it reached disk so
    /// `append` only notifies observers for a persisted entry. Callers hold
    /// `lock`.
    private func writeAppend(_ entry: HistoryEntry) -> Bool {
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
            return false
        }
        return true
    }

    /// Reads and decodes the whole file. Callers hold `lock`.
    private func readEntries() -> [HistoryEntry] {
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

    /// Best-effort whole-file replacement shared by the mutating operations: a
    /// failure is logged and swallowed rather than thrown, keeping the store's
    /// no-throw contract (PRD #78). Callers hold `lock`.
    private func rewrite(_ entries: [HistoryEntry]) -> Bool {
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
            return true
        } catch {
            Log.history.error(
                "History rewrite skipped: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }
}
