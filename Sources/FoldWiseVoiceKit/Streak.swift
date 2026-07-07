// The lifetime dictation streak (PRD #97): the one deliberate exception to the
// Stats pane's "no new state" rule. The four projection stats
// (`UsageStatsAggregator`) are a pure lens over kept history, but a consecutive-
// day count can't be projected — a rolling retention window would silently cap
// and corrupt it — so the streak is backed by a tiny persisted record so it can
// outlive pruning and become a *true* lifetime streak.
//
// It still honors the privacy posture: the record holds aggregates only (a count
// and a date, never transcript text or audio); it advances off the history
// store's append seam (ADR-0003), so it freezes when "Save dictation history" is
// off for free; and it is reset by a deliberate wipe. The pure advance/display
// rules live here, apart from any storage, so their day arithmetic is unit-tested
// in isolation like `RetentionWindow` and `PolishStatus`.

import Foundation
import os

/// The single persisted streak fact: how many consecutive days the run is, and
/// the last day a dictation was recorded (stored as that day's `startOfDay`, so
/// the day arithmetic never depends on the time of day). Aggregates only — no
/// transcript text or audio ever reaches this record.
struct StreakRecord: Codable, Equatable {
    var currentStreak: Int
    var lastActiveDay: Date
}

/// The two pure rules that govern the streak, kept as value-in/value-out
/// functions with an injected `Calendar` so time zone and DST day steps are
/// exercised apart from the store (PRD #97). `advance` decides how a new
/// dictation moves the stored run; `display` decides what the pane shows for a
/// stored run as of `now`.
enum StreakRules {
    /// The run after a dictation on `day`: a first-ever entry starts at 1, the
    /// same day is a no-op, the next consecutive day is +1, and a genuine forward
    /// gap of two or more days resets to 1. A backwards step — a clock rollback or
    /// a westward timezone move that lands `day` before the stored day — is a
    /// no-op that preserves the stored run rather than corrupting it. Days are
    /// compared through the injected calendar's `startOfDay`, so a spring-forward
    /// day (only 23 hours long) still counts as one step — a naive
    /// divide-by-86400 would miss it.
    static func advance(_ record: StreakRecord?, on day: Date, calendar: Calendar) -> StreakRecord {
        let newDay = calendar.startOfDay(for: day)
        guard let record else {
            return StreakRecord(currentStreak: 1, lastActiveDay: newDay)
        }
        let lastDay = calendar.startOfDay(for: record.lastActiveDay)
        let dayDelta = calendar.dateComponents([.day], from: lastDay, to: newDay).day ?? 0
        switch dayDelta {
        case 0:
            return record // same day — no-op
        case 1:
            return StreakRecord(currentStreak: record.currentStreak + 1, lastActiveDay: newDay)
        case ..<0:
            // A backwards step — a clock rollback or a westward timezone move that
            // lands `newDay` before the stored day — is ignored: we return the
            // record untouched so a transient skew never wipes a live run or drags
            // `lastActiveDay` into the past (which would then misread the real next
            // day as a +1 and compound the corruption). Only a genuine forward gap
            // restarts the run; going backwards can never be a legitimate advance.
            return record
        default:
            // A genuine forward gap of two or more days restarts the run at 1 on
            // the new day — a streak is consecutive or it is nothing.
            return StreakRecord(currentStreak: 1, lastActiveDay: newDay)
        }
    }

    /// The streak to show as of `now`, or `nil` when it has lapsed or never
    /// started — the pane renders `nil` as "No active streak" rather than a
    /// misleading "0 days". A run is alive only while its last active day is today
    /// or yesterday; a skipped day lapses it.
    static func display(_ record: StreakRecord?, now: Date, calendar: Calendar) -> Int? {
        guard let record, record.currentStreak > 0 else { return nil }
        let today = calendar.startOfDay(for: now)
        let lastDay = calendar.startOfDay(for: record.lastActiveDay)
        let dayDelta = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
        return (0 ... 1).contains(dayDelta) ? record.currentStreak : nil
    }
}

/// The persistence seam for the streak. A best-effort store like `HistoryStore`:
/// `advance` and `reset` swallow write failures and `load` returns what it can
/// read, so a stats write can never break a dictation session (PRD #97).
/// `JSONStatsStore` is the production conformer; tests drive it against a temp
/// file injected via its initializer.
protocol StatsStore: AnyObject {
    /// The stored run, or `nil` on first launch / after a reset.
    func load() -> StreakRecord?
    /// Fold a dictation recorded on `day` into the stored run via
    /// `StreakRules.advance`, then persist. Called off the history store's append
    /// seam, so it only ever fires while saving is on.
    func advance(on day: Date, calendar: Calendar)
    /// Drop the stored run entirely (a deliberate wipe — Clear All or
    /// delete-on-turn-off), so `load` returns `nil` and the pane reads "No active
    /// streak".
    func reset()
}

/// Persists the streak as a small `stats.json` object in Application Support,
/// alongside `history.jsonl`. Reads and writes are best-effort: nothing here
/// throws to the caller, so a failed or blocked write degrades to a logged no-op
/// rather than breaking the session.
final class JSONStatsStore: StatsStore {
    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    /// Serializes file access: the pipeline advances the streak off the main
    /// thread (the record seam) while the Settings controller loads it on the main
    /// actor, so a load must never interleave with an advance's read-then-write.
    private let lock = NSLock()

    init(url: URL) {
        self.url = url
    }

    /// `stats.json` alongside `history.jsonl` in Application Support.
    static var defaultURL: URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FoldWise Voice", isDirectory: true)
        return support.appendingPathComponent("stats.json")
    }

    func load() -> StreakRecord? {
        lock.lock()
        defer { lock.unlock() }
        return readRecord()
    }

    func advance(on day: Date, calendar: Calendar) {
        lock.lock()
        defer { lock.unlock() }
        let updated = StreakRules.advance(readRecord(), on: day, calendar: calendar)
        write(updated)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
        } catch {
            Log.history.error(
                "Streak reset skipped: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Reads and decodes the record, or `nil` on a missing/unreadable/corrupt
    /// file — a best-effort load never throws. Callers hold `lock`.
    private func readRecord() -> StreakRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(StreakRecord.self, from: data)
    }

    /// Writes the record atomically; a failure is logged and swallowed to keep
    /// the store's no-throw contract. Callers hold `lock`.
    private func write(_ record: StreakRecord) {
        do {
            let data = try encoder.encode(record)
            let fm = FileManager.default
            try fm.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            Log.history.error(
                "Streak advance skipped: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
