import Foundation

struct StatsProjection: Equatable {
    struct Metric: Equatable, Identifiable {
        enum Kind: String, Equatable {
            case wordsDictated
            case speakingSpeed
            case currentStreak
            case timeSaved
        }

        let kind: Kind
        let title: String
        let value: String
        let detail: String
        let symbol: String

        var id: Kind {
            kind
        }
    }

    enum Notice: Equatable {
        case none
        case noHistory(String)
        case savingOff(message: String, actionTitle: String)
    }

    struct Input: Equatable {
        let entries: [HistoryEntry]
        let currentStreak: Int?
        let savingEnabled: Bool
    }

    struct Month: Equatable {
        let title: String
        let weekdays: [String]
        let leadingColumnOffset: Int
        let spokenWordTotal: Int
        let activeDays: Int
        let spokenWordSummary: String
        let activeDaySummary: String
        let accessibilityLabel: String
        let accessibilityValue: String
        let legendLabels: [String]
        let days: [Day]
    }

    struct Day: Equatable, Identifiable {
        enum Intensity: Int, Equatable, CaseIterable {
            case neutral
            case low
            case moderate
            case medium
            case high
            case veryHigh

            init(spokenWords: Int) {
                switch spokenWords {
                case 0:
                    self = .neutral
                case 1 ..< 250:
                    self = .low
                case 250 ..< 600:
                    self = .moderate
                case 600 ..< 1000:
                    self = .medium
                case 1000 ..< 1600:
                    self = .high
                default:
                    self = .veryHigh
                }
            }
        }

        enum State: Equatable {
            case elapsed
            case today
            case future
        }

        let date: Date
        let state: State
        let dayNumber: String
        let savedSessionCount: Int
        let spokenWords: Int
        let intensity: Intensity
        let compactSpokenWords: String?
        let fullDate: String
        let detailActivity: String
        let detailTiming: String?
        let accessibilityLabel: String
        let accessibilityValue: String

        var id: Date {
            date
        }
    }

    let lifetime: UsageStats
    let metrics: [Metric]
    let notice: Notice
    let month: Month

    static func project(
        _ input: Input,
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> StatsProjection {
        let today = calendar.startOfDay(for: now)
        let monthStart = calendar.dateInterval(of: .month, for: today)?.start ?? today
        let dayRange = calendar.range(of: .day, in: .month, for: monthStart) ?? 1 ..< 1
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let sessions = UsageStatsAggregator.normalize(input.entries, calendar: calendar)
        let formatter = Formatter(locale: locale)
        var lifetimeAccumulator = UsageStatsAggregator.Accumulator()
        var buckets: [Date: [UsageStatsAggregator.Session]] = [:]
        var spokenWordTotal = 0

        for session in sessions {
            lifetimeAccumulator.add(session)
            let day = session.localDay
            guard day >= monthStart, day < monthEnd, day <= today else { continue }
            buckets[day, default: []].append(session)
            spokenWordTotal += session.spokenWords
        }

        let days = dayRange.compactMap { dayNumber -> Day? in
            guard let date = calendar.date(byAdding: .day, value: dayNumber - 1, to: monthStart) else {
                return nil
            }
            let state: Day.State = if date < today {
                .elapsed
            } else if date == today {
                .today
            } else {
                .future
            }
            let daySessions = buckets[date] ?? []
            let words = daySessions.reduce(0) { $0 + $1.spokenWords }
            let details = formatter.details(for: daySessions, spokenWords: words)
            let fullDate = formatter.fullDate(date, calendar: calendar)
            let accessibilityLabel = state == .today ? "\(fullDate), today" : fullDate
            let accessibilityValue = daySessions.isEmpty
                ? formatter.emptyAccessibilityValue
                : [details.activity, details.timing].compactMap { $0 }.joined(separator: ". ")
            return Day(
                date: date,
                state: state,
                dayNumber: formatter.number(dayNumber),
                savedSessionCount: daySessions.count,
                spokenWords: words,
                intensity: Day.Intensity(spokenWords: words),
                compactSpokenWords: daySessions.isEmpty ? nil : formatter.compactNumber(words),
                fullDate: fullDate,
                detailActivity: details.activity,
                detailTiming: details.timing,
                accessibilityLabel: accessibilityLabel,
                accessibilityValue: accessibilityValue
            )
        }

        let title = formatter.monthTitle(monthStart, calendar: calendar)
        let lifetime = lifetimeAccumulator.stats()
        let spokenWordSummary = formatter.spokenWords(spokenWordTotal)
        let activeDaySummary = formatter.activeDays(buckets.count)
        return StatsProjection(
            lifetime: lifetime,
            metrics: formatter.metrics(
                lifetime: lifetime,
                currentStreak: input.entries.isEmpty ? nil : input.currentStreak
            ),
            notice: notice(input),
            month: Month(
                title: title,
                weekdays: weekdays(calendar: calendar, locale: locale),
                leadingColumnOffset: leadingOffset(monthStart: monthStart, calendar: calendar),
                spokenWordTotal: spokenWordTotal,
                activeDays: buckets.count,
                spokenWordSummary: spokenWordSummary,
                activeDaySummary: activeDaySummary,
                accessibilityLabel: "\(title) activity calendar",
                accessibilityValue: "\(spokenWordSummary), \(activeDaySummary)",
                legendLabels: formatter.legendLabels,
                days: days
            )
        )
    }

    private static func notice(_ input: Input) -> Notice {
        if !input.savingEnabled {
            return .savingOff(
                message: "Saving is off — Stats won’t include new dictations. Turn it on in History.",
                actionTitle: "Open History"
            )
        }
        if input.entries.isEmpty {
            return .noHistory("No stats yet — your activity will appear after your first saved dictation.")
        }
        return .none
    }

    private static func weekdays(calendar: Calendar, locale: Locale) -> [String] {
        var localizedCalendar = calendar
        localizedCalendar.locale = locale
        let symbols = localizedCalendar.shortStandaloneWeekdaySymbols
        let start = max(0, localizedCalendar.firstWeekday - 1)
        return Array(symbols[start...] + symbols[..<start]).map {
            $0.capitalized(with: locale)
        }
    }

    private static func leadingOffset(monthStart: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: monthStart)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private struct Formatter {
        private enum Language {
            case english
            case polish
            case arabic

            init(locale: Locale) {
                switch locale.language.languageCode?.identifier {
                case "pl": self = .polish
                case "ar": self = .arabic
                default: self = .english
                }
            }
        }

        let locale: Locale
        private let language: Language

        init(locale: Locale) {
            self.locale = locale
            language = Language(locale: locale)
        }

        var legendLabels: [String] {
            [
                "None",
                "\(number(1))–\(number(249))",
                "\(number(250))–\(number(599))",
                "\(number(600))–\(number(999))",
                "\(number(1000))–\(number(1599))",
                "\(number(1600))+",
            ]
        }

        var emptyAccessibilityValue: String {
            switch language {
            case .polish: "Brak podyktowanych słów. Brak zapisanych sesji dyktowania"
            case .arabic: "لا توجد كلمات منطوقة. لا توجد جلسات إملاء محفوظة"
            case .english: "No dictated words. No saved Dictation sessions"
            }
        }

        func metrics(lifetime: UsageStats, currentStreak: Int?) -> [Metric] {
            [
                Metric(
                    kind: .wordsDictated,
                    title: "Words dictated",
                    value: number(lifetime.totalWords),
                    detail: "from saved history",
                    symbol: "quote.bubble"
                ),
                Metric(
                    kind: .speakingSpeed,
                    title: "Speaking speed",
                    value: speakingSpeed(lifetime.wordsPerMinute),
                    detail: "pauses included",
                    symbol: "waveform"
                ),
                Metric(
                    kind: .currentStreak,
                    title: "Current streak",
                    value: streak(currentStreak),
                    detail: "through today",
                    symbol: "flame"
                ),
                Metric(
                    kind: .timeSaved,
                    title: "Time saved",
                    value: timeSaved(lifetime.timeSavedMinutes),
                    detail: "versus 52 wpm typing",
                    symbol: "clock.arrow.circlepath"
                ),
            ]
        }

        func monthTitle(_ date: Date, calendar: Calendar) -> String {
            dateFormatter(calendar: calendar, template: "MMMM y").string(from: date)
        }

        func fullDate(_ date: Date, calendar: Calendar) -> String {
            let formatter = dateFormatter(calendar: calendar, template: "EEEE, MMMM d, y")
            formatter.dateStyle = .full
            return formatter.string(from: date)
        }

        func compactNumber(_ value: Int) -> String {
            value.formatted(.number.notation(.compactName).locale(locale))
        }

        func spokenWords(_ count: Int) -> String {
            let value = number(count)
            switch language {
            case .polish:
                return "\(value) \(polishForm(count, noun: .spokenWords))"
            case .arabic:
                return "\(value) \(arabicForm(count, noun: .spokenWords))"
            case .english:
                return "\(value) spoken \(count == 1 ? "word" : "words")"
            }
        }

        func activeDays(_ count: Int) -> String {
            let value = number(count)
            switch language {
            case .polish:
                return "\(value) \(polishForm(count, noun: .activeDays))"
            case .arabic:
                return "\(value) \(arabicForm(count, noun: .activeDays))"
            case .english:
                return "\(value) active \(count == 1 ? "day" : "days")"
            }
        }

        func details(
            for sessions: [UsageStatsAggregator.Session],
            spokenWords: Int
        ) -> (activity: String, timing: String?) {
            guard !sessions.isEmpty else {
                return (noSavedSessions, nil)
            }
            let activity = activity(spokenWords: spokenWords, sessionCount: sessions.count)
            let timed = sessions.compactMap(\.usableDurationMs)
            guard !timed.isEmpty else {
                return (activity, timingUnavailable)
            }
            guard timed.count == sessions.count else {
                return (activity, partialTimingUnavailable)
            }
            let durationMs = timed.reduce(0, +)
            let saved = UsageStatsAggregator.timeSaved(
                timedWords: spokenWords,
                timedMs: durationMs,
                typingWordsPerMinute: UsageStatsAggregator.typingBaselineWordsPerMinute
            )
            let durationText = duration(milliseconds: durationMs)
            guard let saved else {
                return (activity, noSavingTiming(durationText))
            }
            let savedDuration = duration(milliseconds: Int(saved * 60000))
            return (activity, savingTiming(durationText, saved: savedDuration))
        }

        func number(_ value: Int) -> String {
            let formatter = NumberFormatter()
            formatter.locale = locale
            formatter.numberStyle = .decimal
            return formatter.string(for: value) ?? String(value)
        }

        private func duration(milliseconds: Int) -> String {
            let totalSeconds = max(1, Int((Double(milliseconds) / 1000).rounded()))
            let roundedSeconds: Int
            let formatter = DateComponentsFormatter()
            if totalSeconds < 60 {
                roundedSeconds = totalSeconds
                formatter.allowedUnits = [.second]
            } else if totalSeconds < 3600 {
                roundedSeconds = max(60, Int((Double(totalSeconds) / 60).rounded()) * 60)
                formatter.allowedUnits = [.minute]
            } else {
                roundedSeconds = max(3600, Int((Double(totalSeconds) / 60).rounded()) * 60)
                formatter.allowedUnits = [.hour, .minute]
            }
            formatter.unitsStyle = .short
            formatter.maximumUnitCount = 2
            formatter.zeroFormattingBehavior = .dropAll
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = locale
            formatter.calendar = calendar
            return formatter.string(from: TimeInterval(roundedSeconds))
                ?? "\(number(totalSeconds)) sec"
        }

        private var noSavedSessions: String {
            switch language {
            case .polish: "Brak zapisanych sesji dyktowania"
            case .arabic: "لا توجد جلسات إملاء محفوظة"
            case .english: "No saved Dictation sessions"
            }
        }

        private var timingUnavailable: String {
            switch language {
            case .polish: "Dane o czasie niedostępne"
            case .arabic: "بيانات التوقيت غير متاحة"
            case .english: "Timing unavailable"
            }
        }

        private var partialTimingUnavailable: String {
            switch language {
            case .polish: "Dane o czasie niedostępne dla części sesji"
            case .arabic: "بيانات التوقيت غير متاحة لبعض الجلسات"
            case .english: "Timing unavailable for some sessions"
            }
        }

        private func activity(spokenWords count: Int, sessionCount: Int) -> String {
            switch language {
            case .polish, .arabic:
                "\(spokenWords(count)) · \(savedSessions(sessionCount))"
            case .english:
                "\(spokenWords(count)) across \(savedSessions(sessionCount))"
            }
        }

        private func savedSessions(_ count: Int) -> String {
            let value = number(count)
            switch language {
            case .polish:
                return "\(value) \(polishForm(count, noun: .savedSessions))"
            case .arabic:
                return "\(value) \(arabicForm(count, noun: .savedSessions))"
            case .english:
                return "\(value) saved \(count == 1 ? "session" : "sessions")"
            }
        }

        private enum CountedNoun {
            case spokenWords
            case activeDays
            case savedSessions
            case streakDays
        }

        private func polishForm(_ count: Int, noun: CountedNoun) -> String {
            let forms = switch noun {
            case .spokenWords: ("wypowiedziane słowo", "wypowiedziane słowa", "wypowiedzianych słów")
            case .activeDays: ("aktywny dzień", "aktywne dni", "aktywnych dni")
            case .savedSessions: ("zapisana sesja", "zapisane sesje", "zapisanych sesji")
            case .streakDays: ("dzień", "dni", "dni")
            }
            guard count != 1 else { return forms.0 }
            let lastTwo = abs(count) % 100
            let last = abs(count) % 10
            return (2 ... 4).contains(last) && !(12 ... 14).contains(lastTwo)
                ? forms.1
                : forms.2
        }

        private func arabicForm(_ count: Int, noun: CountedNoun) -> String {
            let forms = switch noun {
            case .spokenWords:
                ("كلمات منطوقة", "كلمة منطوقة", "كلمتان منطوقتان", "كلمات منطوقة", "كلمة منطوقة", "كلمة منطوقة")
            case .activeDays:
                ("أيام نشطة", "يوم نشط", "يومان نشطان", "أيام نشطة", "يومًا نشطًا", "يوم نشط")
            case .savedSessions:
                (
                    "جلسات إملاء محفوظة", "جلسة إملاء محفوظة", "جلستا إملاء محفوظتان",
                    "جلسات إملاء محفوظة", "جلسة إملاء محفوظة", "جلسة إملاء محفوظة"
                )
            case .streakDays:
                ("أيام", "يوم", "يومان", "أيام", "يومًا", "يوم")
            }
            return switch abs(count) {
            case 0: forms.0
            case 1: forms.1
            case 2: forms.2
            default:
                switch abs(count) % 100 {
                case 3 ... 10: forms.3
                case 11 ... 99: forms.4
                default: forms.5
                }
            }
        }

        private func noSavingTiming(_ duration: String) -> String {
            switch language {
            case .polish: "\(duration) dyktowania · brak szacowanego zaoszczędzonego czasu"
            case .arabic: "\(duration) من الإملاء · لا يوجد وقت موفر مقدر"
            case .english: "\(duration) dictating · no estimated time saved"
            }
        }

        private func savingTiming(_ duration: String, saved: String) -> String {
            switch language {
            case .polish: "\(duration) dyktowania · zaoszczędzono około \(saved)"
            case .arabic: "\(duration) من الإملاء · تم توفير نحو \(saved)"
            case .english: "\(duration) dictating · about \(saved) saved"
            }
        }

        private func speakingSpeed(_ wordsPerMinute: Double?) -> String {
            guard let wordsPerMinute, wordsPerMinute >= 0.5 else { return "—" }
            let unit = switch language {
            case .polish: "sł./min"
            case .arabic: "كلمة/د"
            case .english: "wpm"
            }
            return "\(number(Int(wordsPerMinute.rounded()))) \(unit)"
        }

        private func streak(_ days: Int?) -> String {
            guard let days else { return "—" }
            let value = number(days)
            switch language {
            case .polish:
                return "\(value) \(polishForm(days, noun: .streakDays))"
            case .arabic:
                return "\(value) \(arabicForm(days, noun: .streakDays))"
            case .english:
                return "\(value) \(days == 1 ? "day" : "days")"
            }
        }

        private func timeSaved(_ minutes: Double?) -> String {
            guard let minutes, minutes >= 0.5 else { return "—" }
            return "~\(duration(milliseconds: Int(minutes * 60000)))"
        }

        private func dateFormatter(calendar: Calendar, template: String) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate(template)
            return formatter
        }
    }
}

final class StatsProjectionCache {
    typealias Project = (StatsProjection.Input, Date, Calendar, Locale) -> StatsProjection

    private struct EntryKey: Hashable {
        let createdAt: Date
        let rawText: String
        let durationMs: Int?

        init(_ entry: HistoryEntry) {
            createdAt = entry.createdAt
            rawText = entry.rawText
            durationMs = entry.durationMs
        }
    }

    private struct Key: Equatable {
        let entries: [EntryKey: Int]
        let currentStreak: Int?
        let savingEnabled: Bool
        let day: Date
        let calendarIdentifier: String
        let timeZoneIdentifier: String
        let firstWeekday: Int
        let minimumDaysInFirstWeek: Int
        let localeIdentifier: String
    }

    private let now: () -> Date
    private let project: Project
    private var cached: (key: Key, projection: StatsProjection)?

    init(
        now: @escaping () -> Date = Date.init,
        project: @escaping Project = StatsProjection.project
    ) {
        self.now = now
        self.project = project
    }

    func resolve(
        _ input: StatsProjection.Input,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> StatsProjection {
        let currentNow = now()
        let key = Key(
            entries: input.entries.reduce(into: [:]) { counts, entry in
                counts[EntryKey(entry), default: 0] += 1
            },
            currentStreak: input.currentStreak,
            savingEnabled: input.savingEnabled,
            day: calendar.startOfDay(for: currentNow),
            calendarIdentifier: String(describing: calendar.identifier),
            timeZoneIdentifier: calendar.timeZone.identifier,
            firstWeekday: calendar.firstWeekday,
            minimumDaysInFirstWeek: calendar.minimumDaysInFirstWeek,
            localeIdentifier: locale.identifier
        )
        if let cached, cached.key == key {
            return cached.projection
        }
        let projection = project(input, currentNow, calendar, locale)
        cached = (key, projection)
        return projection
    }
}
