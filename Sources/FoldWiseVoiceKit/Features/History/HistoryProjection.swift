import Foundation

/// Search, filtering, ordering, and day grouping for the full History
/// collection. The exact entry travels beside its shared row presentation so
/// commands never need to look a saved Dictation session up again.
struct HistoryProjection: Equatable {
    struct Input: Equatable {
        let entries: [HistoryEntry]
        let search: String
        let flaggedOnly: Bool
        let modes: [Mode]

        init(
            entries: [HistoryEntry],
            search: String,
            flaggedOnly: Bool,
            modes: [Mode] = []
        ) {
            self.entries = entries
            self.search = search
            self.flaggedOnly = flaggedOnly
            self.modes = modes
        }
    }

    struct Row: Equatable, Identifiable {
        let entry: HistoryEntry
        let presentation: DictationRowPresentation

        var id: UUID {
            entry.id
        }
    }

    struct Section: Equatable {
        let header: String
        let rows: [Row]
    }

    let sections: [Section]
    let hasSourceEntries: Bool

    var isEmpty: Bool {
        sections.isEmpty
    }

    static let empty = HistoryProjection(
        sections: [],
        hasSourceEntries: false
    )

    static func project(
        _ input: Input,
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> HistoryProjection {
        let search = input.search.trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = input.entries
            .filter { entry in
                if input.flaggedOnly, !entry.flagged {
                    return false
                }
                guard !search.isEmpty else { return true }
                return entry.text.localizedCaseInsensitiveContains(search)
                    || entry.rawText.localizedCaseInsensitiveContains(search)
            }
            .sorted { $0.createdAt > $1.createdAt }

        var dayOrder: [Date] = []
        var buckets: [Date: [Row]] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.createdAt)
            if buckets[day] == nil {
                dayOrder.append(day)
            }
            buckets[day, default: []].append(Row(
                entry: entry,
                presentation: DictationRowPresentation(
                    entry: entry,
                    modes: input.modes,
                    calendar: calendar
                )
            ))
        }

        let formatter = dayFormatter(calendar: calendar, locale: locale)
        return HistoryProjection(
            sections: dayOrder.map { day in
                Section(
                    header: header(for: day, now: now, calendar: calendar, formatter: formatter),
                    rows: buckets[day] ?? []
                )
            },
            hasSourceEntries: !input.entries.isEmpty
        )
    }

    private static func header(
        for day: Date,
        now: Date,
        calendar: Calendar,
        formatter: DateFormatter
    ) -> String {
        let today = calendar.startOfDay(for: now)
        if day == today {
            return "Today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           day == yesterday {
            return "Yesterday"
        }
        return formatter.string(from: day)
    }

    private static func dayFormatter(calendar: Calendar, locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }
}
