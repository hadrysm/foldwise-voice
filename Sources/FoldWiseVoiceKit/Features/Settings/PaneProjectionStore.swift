import Foundation
import Observation

@MainActor
@Observable
final class PaneProjectionStore {
    enum Pane: Hashable {
        case home
        case history
        case stats
    }

    enum Phase: Equatable {
        case loading
        case updating
        case current
    }

    struct Projection<Value: Equatable>: Equatable {
        let completed: Completed<Value>?
        let phase: Phase

        var isCurrent: Bool {
            phase == .current
        }

        fileprivate static var loading: Projection<Value> {
            Projection(completed: nil, phase: .loading)
        }

        fileprivate static func preparing(
            from completed: Completed<Value>?
        ) -> Projection<Value> {
            Projection(
                completed: completed,
                phase: completed == nil ? .loading : .updating
            )
        }

        fileprivate static func current(
            _ completed: Completed<Value>
        ) -> Projection<Value> {
            Projection(completed: completed, phase: .current)
        }
    }

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

    @ObservationIgnored private let beforePreparation:
        @Sendable (Pane) async -> Void
    @ObservationIgnored private var historyEntries: [HistoryEntry] = []
    @ObservationIgnored private var historyIndex = HistoryIndex()
    @ObservationIgnored private var statsEntriesKey: [StatsEntryKey: Int] = [:]
    @ObservationIgnored private var historyDerivationCache: (
        key: HistoryDerivationKey,
        sessions: [UsageStatsAggregator.Session]
    )?
    @ObservationIgnored private var modes: [Mode] = []
    @ObservationIgnored private var currentStreak: Int?
    @ObservationIgnored private var savingEnabled = true
    @ObservationIgnored private var generation: UInt = 0
    @ObservationIgnored private var homePreparationRevision: UInt = 0
    @ObservationIgnored private var homeEnvironment: Environment?
    @ObservationIgnored private var homeTask: Task<Void, Never>?
    @ObservationIgnored private var defaultHistoryPreparationRevision: UInt = 0
    @ObservationIgnored private var defaultHistoryPendingKey: EnvironmentKey?
    @ObservationIgnored private var defaultHistoryTask: Task<Void, Never>?
    @ObservationIgnored private var historyPreparationRevision: UInt = 0
    @ObservationIgnored private var historyRequest: (
        search: String,
        flaggedOnly: Bool,
        environment: Environment
    )?
    @ObservationIgnored private var historyTask: Task<Void, Never>?
    @ObservationIgnored private var statsPreparationRevision: UInt = 0
    @ObservationIgnored private var statsEnvironment: Environment?
    @ObservationIgnored private var statsTask: Task<Void, Never>?
    @ObservationIgnored private var homeCache:
        (key: EnvironmentKey, completed: Completed<HomeValue>)?
    @ObservationIgnored private var defaultHistoryCache: (
        key: EnvironmentKey,
        completed: Completed<HistoryProjection>
    )?
    @ObservationIgnored private var previousDefaultHistoryCompleted:
        Completed<HistoryProjection>?
    @ObservationIgnored private var filteredHistoryCache: (
        key: HistoryKey,
        completed: Completed<HistoryProjection>
    )?
    @ObservationIgnored private var statsCache:
        (key: StatsEnvironmentKey, completed: Completed<StatsProjection>)?

    private(set) var homeProjection = Projection<HomeValue>.loading
    private(set) var historyProjection = Projection<HistoryProjection>.loading
    private(set) var statsProjection = Projection<StatsProjection>.loading

    init(
        beforePreparation: @escaping @Sendable (Pane) async -> Void = { _ in }
    ) {
        self.beforePreparation = beforePreparation
    }

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
        historyIndex.setModes(modes)
        invalidateHomeAndHistory()
        if let homeEnvironment {
            prepareHome(in: homeEnvironment)
        }
        if let historyRequest {
            prepareHistory(
                search: historyRequest.search,
                flaggedOnly: historyRequest.flaggedOnly,
                in: historyRequest.environment
            )
        }
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
        historyIndex.setEntries(entries)
        invalidateHomeAndHistory()
        var invalidation: Invalidation = [.home, .history]
        if statsEntriesKey != nextStatsKey {
            statsEntriesKey = nextStatsKey
            historyDerivationCache = nil
            statsCache = nil
            invalidation.insert(.stats)
        }
        if let homeEnvironment {
            prepareHome(in: homeEnvironment)
        }
        if let historyRequest {
            prepareHistory(
                search: historyRequest.search,
                flaggedOnly: historyRequest.flaggedOnly,
                in: historyRequest.environment
            )
        }
        if invalidation.contains(.stats), let statsEnvironment {
            prepareStats(in: statsEnvironment)
        }
        return invalidation
    }

    @discardableResult
    func setCurrentStreak(_ currentStreak: Int?) -> Invalidation {
        guard self.currentStreak != currentStreak else { return [] }
        self.currentStreak = currentStreak
        homeCache = nil
        statsCache = nil
        if let homeEnvironment {
            prepareHome(in: homeEnvironment)
        }
        if let statsEnvironment {
            prepareStats(in: statsEnvironment)
        }
        return [.home, .stats]
    }

    @discardableResult
    func setSavingEnabled(_ savingEnabled: Bool) -> Invalidation {
        guard self.savingEnabled != savingEnabled else { return [] }
        self.savingEnabled = savingEnabled
        statsCache = nil
        if let statsEnvironment {
            prepareStats(in: statsEnvironment)
        }
        return .stats
    }

    func prepareAll(in environment: Environment) {
        prepareHome(in: environment)
        prepareHistory(
            search: historyRequest?.search ?? "",
            flaggedOnly: historyRequest?.flaggedOnly ?? false,
            in: environment
        )
        prepareStats(in: environment)
    }

    func home(in environment: Environment) -> Completed<HomeValue> {
        let key = environment.key
        if let homeCache, homeCache.key == key {
            homeProjection = .current(homeCache.completed)
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
        homeProjection = .current(completed)
        return completed
    }

    func prepareHome(in environment: Environment) {
        homeEnvironment = environment
        let key = environment.key
        if let homeCache, homeCache.key == key {
            homePreparationRevision &+= 1
            homeTask?.cancel()
            homeProjection = .current(homeCache.completed)
            return
        }

        homePreparationRevision &+= 1
        let revision = homePreparationRevision
        let entries = historyEntries
        let modes = modes
        let currentStreak = currentStreak
        let beforePreparation = beforePreparation
        homeTask?.cancel()
        homeProjection = .preparing(from: homeProjection.completed)
        homeTask = Task.detached(priority: .userInitiated) { [weak self] in
            await beforePreparation(.home)
            guard !Task.isCancelled else { return }
            let value = HomeValue(
                recent: HomeProjection.project(
                    HomeProjection.Input(entries: entries, modes: modes),
                    now: environment.now,
                    calendar: environment.calendar,
                    locale: environment.locale
                ),
                usage: UsageStatsAggregator.aggregate(
                    UsageStatsAggregator.normalize(
                        entries,
                        calendar: environment.calendar
                    )
                ),
                currentStreak: currentStreak
            )
            guard !Task.isCancelled else { return }
            await self?.publishHome(value, key: key, revision: revision)
        }
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
            historyProjection = .current(defaultHistoryCache.completed)
            return defaultHistoryCache.completed
        }
        if !isDefaultFilter,
           let filteredHistoryCache,
           filteredHistoryCache.key == key {
            historyProjection = .current(filteredHistoryCache.completed)
            return filteredHistoryCache.completed
        }
        let snapshot = historyIndex.snapshot(calendar: environment.calendar)
        let projection = HistoryProjection.project(
            snapshot,
            search: search,
            flaggedOnly: flaggedOnly,
            now: environment.now,
            locale: environment.locale
        ) ?? .empty
        let completed = complete(projection)
        if isDefaultFilter {
            defaultHistoryCache = (key.environment, completed)
            previousDefaultHistoryCompleted = completed
        } else {
            // Keep interactive search bounded while preserving the disposable
            // pane's default projection for a later warm revisit.
            filteredHistoryCache = (key, completed)
        }
        historyProjection = .current(completed)
        return completed
    }

    func prepareHistory(
        search: String,
        flaggedOnly: Bool,
        in environment: Environment
    ) {
        historyRequest = (search, flaggedOnly, environment)
        let key = HistoryKey(
            search: search.trimmingCharacters(in: .whitespacesAndNewlines),
            flaggedOnly: flaggedOnly,
            environment: environment.key
        )
        let isDefaultFilter = key.search.isEmpty && !key.flaggedOnly
        prepareDefaultHistory(
            in: environment,
            publishesActiveProjection: isDefaultFilter
        )
        guard !isDefaultFilter else { return }
        if let filteredHistoryCache, filteredHistoryCache.key == key {
            historyPreparationRevision &+= 1
            historyTask?.cancel()
            historyProjection = .current(filteredHistoryCache.completed)
            return
        }

        historyPreparationRevision &+= 1
        let revision = historyPreparationRevision
        let snapshot = historyIndex.snapshot(calendar: environment.calendar)
        let beforePreparation = beforePreparation
        historyTask?.cancel()
        historyProjection = .preparing(from: historyProjection.completed)
        historyTask = Task.detached(priority: .userInitiated) { [weak self] in
            await beforePreparation(.history)
            guard !Task.isCancelled else { return }
            let projection = HistoryProjection.project(
                snapshot,
                search: search,
                flaggedOnly: flaggedOnly,
                now: environment.now,
                locale: environment.locale,
                shouldCancel: { Task.isCancelled }
            )
            guard let projection, !Task.isCancelled else { return }
            await self?.publishFilteredHistory(
                projection,
                key: key,
                revision: revision
            )
        }
    }

    private var activeHistoryKey: HistoryKey? {
        historyRequest.map {
            HistoryKey(
                search: $0.search.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
                flaggedOnly: $0.flaggedOnly,
                environment: $0.environment.key
            )
        }
    }

    private func prepareDefaultHistory(
        in environment: Environment,
        publishesActiveProjection: Bool
    ) {
        let key = environment.key
        if let defaultHistoryCache, defaultHistoryCache.key == key {
            defaultHistoryPreparationRevision &+= 1
            defaultHistoryTask?.cancel()
            defaultHistoryPendingKey = nil
            if publishesActiveProjection {
                historyProjection = .current(defaultHistoryCache.completed)
            }
            return
        }
        if defaultHistoryPendingKey == key {
            if publishesActiveProjection {
                historyProjection = .preparing(
                    from: previousDefaultHistoryCompleted
                )
            }
            return
        }

        defaultHistoryPreparationRevision &+= 1
        let revision = defaultHistoryPreparationRevision
        let snapshot = historyIndex.snapshot(calendar: environment.calendar)
        let beforePreparation = beforePreparation
        defaultHistoryTask?.cancel()
        defaultHistoryPendingKey = key
        if publishesActiveProjection {
            historyProjection = .preparing(
                from: previousDefaultHistoryCompleted
            )
        }
        defaultHistoryTask = Task.detached(priority: .userInitiated) { [weak self] in
            await beforePreparation(.history)
            guard !Task.isCancelled else { return }
            let projection = HistoryProjection.project(
                snapshot,
                search: "",
                flaggedOnly: false,
                now: environment.now,
                locale: environment.locale,
                shouldCancel: { Task.isCancelled }
            )
            guard let projection, !Task.isCancelled else { return }
            await self?.publishDefaultHistory(
                projection,
                key: key,
                revision: revision
            )
        }
    }

    func stats(in environment: Environment) -> Completed<StatsProjection> {
        let key = environment.statsKey
        if let statsCache, statsCache.key == key {
            statsProjection = .current(statsCache.completed)
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
        statsProjection = .current(completed)
        return completed
    }

    @discardableResult
    func prepareStats(in environment: Environment) -> Task<Void, Never>? {
        statsEnvironment = environment
        let key = environment.statsKey
        if let statsCache, statsCache.key == key {
            statsPreparationRevision &+= 1
            statsTask?.cancel()
            statsProjection = .current(statsCache.completed)
            return nil
        }

        statsPreparationRevision &+= 1
        let revision = statsPreparationRevision
        let entries = historyEntries
        let currentStreak = currentStreak
        let savingEnabled = savingEnabled
        let beforePreparation = beforePreparation
        statsTask?.cancel()
        statsProjection = .preparing(from: statsProjection.completed)
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            await beforePreparation(.stats)
            guard !Task.isCancelled else { return }
            let projection = StatsProjection.project(
                StatsProjection.Input(
                    entries: entries,
                    currentStreak: currentStreak,
                    savingEnabled: savingEnabled
                ),
                now: environment.now,
                calendar: environment.calendar,
                locale: environment.locale
            )
            guard !Task.isCancelled else { return }
            await self?.publishStats(projection, key: key, revision: revision)
        }
        statsTask = task
        return task
    }

    private func publishHome(
        _ value: HomeValue,
        key: EnvironmentKey,
        revision: UInt
    ) {
        guard homePreparationRevision == revision else { return }
        let completed = complete(value)
        homeCache = (key, completed)
        homeProjection = .current(completed)
    }

    private func publishFilteredHistory(
        _ projection: HistoryProjection,
        key: HistoryKey,
        revision: UInt
    ) {
        guard historyPreparationRevision == revision,
              activeHistoryKey == key else { return }
        let completed = complete(projection)
        filteredHistoryCache = (key, completed)
        historyProjection = .current(completed)
    }

    private func publishDefaultHistory(
        _ projection: HistoryProjection,
        key: EnvironmentKey,
        revision: UInt
    ) {
        guard defaultHistoryPreparationRevision == revision,
              defaultHistoryPendingKey == key else { return }
        let completed = complete(projection)
        defaultHistoryCache = (key, completed)
        previousDefaultHistoryCompleted = completed
        defaultHistoryPendingKey = nil
        if activeHistoryKey == HistoryKey(
            search: "",
            flaggedOnly: false,
            environment: key
        ) {
            historyProjection = .current(completed)
        }
    }

    private func publishStats(
        _ projection: StatsProjection,
        key: StatsEnvironmentKey,
        revision: UInt
    ) {
        guard statsPreparationRevision == revision else { return }
        let completed = complete(projection)
        statsCache = (key, completed)
        statsProjection = .current(completed)
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
        if let completed = defaultHistoryCache?.completed {
            previousDefaultHistoryCompleted = completed
        }
        defaultHistoryCache = nil
        filteredHistoryCache = nil
        defaultHistoryTask?.cancel()
        defaultHistoryPendingKey = nil
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
