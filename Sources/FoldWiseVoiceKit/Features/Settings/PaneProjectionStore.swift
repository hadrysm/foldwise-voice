import Foundation

@MainActor
final class PaneProjectionStore {
    struct Environment {
        let now: Date
        let calendar: Calendar
        let locale: Locale

        fileprivate var key: EnvironmentKey {
            EnvironmentKey(
                day: calendar.startOfDay(for: now),
                calendarIdentifier: String(describing: calendar.identifier),
                timeZoneIdentifier: calendar.timeZone.identifier,
                localeIdentifier: locale.identifier
            )
        }

        fileprivate var statsKey: StatsEnvironmentKey {
            StatsEnvironmentKey(
                environment: key,
                firstWeekday: calendar.firstWeekday,
                minimumDaysInFirstWeek: calendar.minimumDaysInFirstWeek
            )
        }
    }

    /// An immutable pane value whose generation changes only when projection
    /// work actually completes. Reusing a generation is the store's public
    /// guarantee that a disposable pane can revisit completed work.
    struct Completed<Value: Equatable>: Equatable {
        let value: Value
        let generation: Generation
    }

    struct Generation: Hashable {
        fileprivate let rawValue: UInt
    }

    struct Revision: Equatable {
        private var rawValue: UInt = 0

        mutating func advance() {
            rawValue &+= 1
        }
    }

    struct Invalidation: OptionSet {
        let rawValue: Int

        static let home = Invalidation(rawValue: 1 << 0)
        static let history = Invalidation(rawValue: 1 << 1)
        static let stats = Invalidation(rawValue: 1 << 2)
    }

    struct HomeValue: Equatable {
        let recent: HomeProjection
        let usage: UsageStats
        let currentStreak: Int?
    }

    fileprivate struct EnvironmentKey: Hashable {
        let day: Date
        let calendarIdentifier: String
        let timeZoneIdentifier: String
        let localeIdentifier: String
    }

    fileprivate struct StatsEnvironmentKey: Hashable {
        let environment: EnvironmentKey
        let firstWeekday: Int
        let minimumDaysInFirstWeek: Int
    }

    private struct HistoryKey: Hashable {
        let search: String
        let flaggedOnly: Bool
        let environment: EnvironmentKey
    }

    private struct HistoryDerivationKey: Hashable {
        let calendarIdentifier: String
        let timeZoneIdentifier: String
    }

    private struct RowModeKey: Equatable {
        let id: ModeID?
        let name: String
        let icon: String

        init(_ mode: Mode) {
            id = mode.id
            name = mode.name
            icon = mode.icon
        }
    }

    private struct StatsEntryKey: Hashable {
        let createdAt: Date
        let rawText: String
        let durationMs: Int?

        init(_ entry: HistoryEntry) {
            createdAt = entry.createdAt
            rawText = entry.rawText
            durationMs = entry.durationMs
        }
    }

    private var historyEntries: [HistoryEntry] = []
    private var statsEntriesKey: [StatsEntryKey: Int] = [:]
    private var historyDerivationCache: (
        key: HistoryDerivationKey,
        sessions: [UsageStatsAggregator.Session]
    )?
    private var modes: [Mode] = []
    private var currentStreak: Int?
    private var savingEnabled = true
    private var generation: UInt = 0
    private var homeCache: (key: EnvironmentKey, completed: Completed<HomeValue>)?
    private var defaultHistoryCache: (
        key: EnvironmentKey,
        completed: Completed<HistoryProjection>
    )?
    private var filteredHistoryCache: (
        key: HistoryKey,
        completed: Completed<HistoryProjection>
    )?
    private var statsCache: (key: StatsEnvironmentKey, completed: Completed<StatsProjection>)?

    var completedHome: Completed<HomeValue>? {
        homeCache?.completed
    }

    var completedDefaultHistory: Completed<HistoryProjection>? {
        defaultHistoryCache?.completed
    }

    var completedStats: Completed<StatsProjection>? {
        statsCache?.completed
    }

    @discardableResult
    func setModes(_ modes: [Mode]) -> Invalidation {
        let previousKey = self.modes.map(RowModeKey.init)
        self.modes = modes
        guard previousKey != modes.map(RowModeKey.init) else { return [] }
        invalidateHomeAndHistory()
        return [.home, .history]
    }

    @discardableResult
    func setHistoryEntries(_ entries: [HistoryEntry]) -> Invalidation {
        let previousEntries = historyEntries
        let nextStatsKey = entries.reduce(into: [:]) { counts, entry in
            counts[StatsEntryKey(entry), default: 0] += 1
        }
        historyEntries = entries
        guard previousEntries != entries else { return [] }
        invalidateHomeAndHistory()
        var invalidation: Invalidation = [.home, .history]
        if statsEntriesKey != nextStatsKey {
            statsEntriesKey = nextStatsKey
            historyDerivationCache = nil
            statsCache = nil
            invalidation.insert(.stats)
        }
        return invalidation
    }

    @discardableResult
    func setCurrentStreak(_ currentStreak: Int?) -> Invalidation {
        guard self.currentStreak != currentStreak else { return [] }
        self.currentStreak = currentStreak
        homeCache = nil
        statsCache = nil
        return [.home, .stats]
    }

    @discardableResult
    func setSavingEnabled(_ savingEnabled: Bool) -> Invalidation {
        guard self.savingEnabled != savingEnabled else { return [] }
        self.savingEnabled = savingEnabled
        statsCache = nil
        return .stats
    }

    func home(in environment: Environment) -> Completed<HomeValue> {
        let key = environment.key
        if let homeCache, homeCache.key == key {
            return homeCache.completed
        }
        let value = HomeValue(
            recent: HomeProjection.project(
                HomeProjection.Input(entries: historyEntries, modes: modes),
                now: environment.now,
                calendar: environment.calendar,
                locale: environment.locale
            ),
            usage: UsageStatsAggregator.aggregate(
                historySessions(calendar: environment.calendar)
            ),
            currentStreak: currentStreak
        )
        let completed = complete(value)
        homeCache = (key, completed)
        return completed
    }

    func history(
        search: String,
        flaggedOnly: Bool,
        in environment: Environment
    ) -> Completed<HistoryProjection> {
        let key = HistoryKey(
            search: search.trimmingCharacters(in: .whitespacesAndNewlines),
            flaggedOnly: flaggedOnly,
            environment: environment.key
        )
        let isDefaultFilter = key.search.isEmpty && !key.flaggedOnly
        if isDefaultFilter,
           let defaultHistoryCache,
           defaultHistoryCache.key == key.environment {
            return defaultHistoryCache.completed
        }
        if !isDefaultFilter,
           let filteredHistoryCache,
           filteredHistoryCache.key == key {
            return filteredHistoryCache.completed
        }
        let projection = HistoryProjection.project(
            HistoryProjection.Input(
                entries: historyEntries,
                search: search,
                flaggedOnly: flaggedOnly,
                modes: modes
            ),
            now: environment.now,
            calendar: environment.calendar,
            locale: environment.locale
        )
        let completed = complete(projection)
        if isDefaultFilter {
            defaultHistoryCache = (key.environment, completed)
        } else {
            // Keep interactive search bounded while preserving the disposable
            // pane's default projection for a later warm revisit.
            filteredHistoryCache = (key, completed)
        }
        return completed
    }

    func stats(in environment: Environment) -> Completed<StatsProjection> {
        let key = environment.statsKey
        if let statsCache, statsCache.key == key {
            return statsCache.completed
        }
        let projection = StatsProjection.project(
            StatsProjection.Input(
                entries: historyEntries,
                currentStreak: currentStreak,
                savingEnabled: savingEnabled
            ),
            now: environment.now,
            calendar: environment.calendar,
            locale: environment.locale
        )
        let completed = complete(projection)
        statsCache = (key, completed)
        return completed
    }

    private func complete<Value: Equatable>(_ value: Value) -> Completed<Value> {
        generation &+= 1
        return Completed(
            value: value,
            generation: Generation(rawValue: generation)
        )
    }

    private func invalidateHomeAndHistory() {
        homeCache = nil
        defaultHistoryCache = nil
        filteredHistoryCache = nil
    }

    private func historySessions(
        calendar: Calendar
    ) -> [UsageStatsAggregator.Session] {
        let key = HistoryDerivationKey(
            calendarIdentifier: String(describing: calendar.identifier),
            timeZoneIdentifier: calendar.timeZone.identifier
        )
        if let historyDerivationCache, historyDerivationCache.key == key {
            return historyDerivationCache.sessions
        }
        let sessions = UsageStatsAggregator.normalize(historyEntries, calendar: calendar)
        historyDerivationCache = (key, sessions)
        return sessions
    }
}
