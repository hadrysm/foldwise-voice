import Foundation

/// Search, filtering, ordering, and day grouping for the full History
/// collection. The exact entry travels beside its shared row presentation so
/// commands never need to look a saved Dictation session up again.
struct HistoryProjection: Equatable {
    struct Input: Equatable {
        let entries: [HistoryEntry]
        let search: String
        let flaggedOnly: Bool
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

    var isEmpty: Bool {
        sections.isEmpty
    }

    static let empty = HistoryProjection(sections: [])

    static func project(
        _ input: Input,
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> HistoryProjection {
        let search = input.search.trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = input.entries
            .filter { entry in
                if input.flaggedOnly, !entry.flagged { return false }
                guard !search.isEmpty else { return true }
                return entry.text.localizedCaseInsensitiveContains(search)
                    || entry.rawText.localizedCaseInsensitiveContains(search)
            }
            .sorted { $0.createdAt > $1.createdAt }

        var dayOrder: [Date] = []
        var buckets: [Date: [Row]] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.createdAt)
            if buckets[day] == nil { dayOrder.append(day) }
            buckets[day, default: []].append(Row(
                entry: entry,
                presentation: DictationRowPresentation(entry: entry, calendar: calendar)
            ))
        }

        let formatter = dayFormatter(calendar: calendar, locale: locale)
        return HistoryProjection(sections: dayOrder.map { day in
            Section(
                header: header(for: day, now: now, calendar: calendar, formatter: formatter),
                rows: buckets[day] ?? []
            )
        })
    }

    private static func header(
        for day: Date,
        now: Date,
        calendar: Calendar,
        formatter: DateFormatter
    ) -> String {
        let today = calendar.startOfDay(for: now)
        if day == today { return "Today" }
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

/// Memoizes History's O(n) projection by the only three values that can change
/// its result. SwiftUI may republish unrelated settings freely without making
/// the collection rescan or regroup.
final class HistoryProjectionCache {
    typealias Project = (HistoryProjection.Input) -> HistoryProjection

    private let project: Project
    private var cached: (input: HistoryProjection.Input, output: HistoryProjection)?

    init(
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) {
        project = { input in
            HistoryProjection.project(
                input,
                now: now(),
                calendar: calendar,
                locale: locale
            )
        }
    }

    init(project: @escaping Project) {
        self.project = project
    }

    func resolve(_ input: HistoryProjection.Input) -> HistoryProjection {
        if let cached, cached.input == input {
            return cached.output
        }
        let output = project(input)
        cached = (input, output)
        return output
    }
}
