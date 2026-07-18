// The Home view's dictation list, as a pure projection over the history the
// app already keeps (PRD #103): the newest ten entries, grouped by calendar
// day (Today / Yesterday / absolute day labels), with a shared row presentation
// that retains the exact source entry for direct actions. Value-in/value-out
// like `UsageStatsAggregator`, so grouping and labeling remain unit-tested
// apart from the SwiftUI view.

import Foundation

struct HomeProjection: Equatable {
    struct Input: Equatable {
        let entries: [HistoryEntry]
        let modes: [Mode]

        init(entries: [HistoryEntry], modes: [Mode] = []) {
            self.entries = entries
            self.modes = modes
        }
    }

    struct Row: Equatable, Identifiable {
        /// Exact source identity and current persisted state for Home's direct
        /// Copy and Flag actions; the view never looks the entry up by id.
        let entry: HistoryEntry
        var id: UUID {
            entry.id
        }

        let presentation: DictationRowPresentation
    }

    struct Section: Equatable {
        let header: String
        let rows: [Row]
    }

    let sections: [Section]

    var isEmpty: Bool {
        sections.isEmpty
    }

    static let maxRows = 10
    static func project(
        _ input: Input,
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> HomeProjection {
        let latest = input.entries.sorted { $0.createdAt > $1.createdAt }.prefix(maxRows)
        var order: [Date] = []
        var buckets: [Date: [Row]] = [:]
        for entry in latest {
            let day = calendar.startOfDay(for: entry.createdAt)
            if buckets[day] == nil {
                order.append(day)
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
        let dayFormatter = makeDayFormatter(calendar: calendar, locale: locale)
        let sections = order.map { day in
            Section(
                header: header(for: day, now: now, calendar: calendar, formatter: dayFormatter),
                rows: buckets[day] ?? []
            )
        }
        return HomeProjection(sections: sections)
    }

    private static func header(
        for day: Date, now: Date, calendar: Calendar, formatter: DateFormatter
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

    private static func makeDayFormatter(calendar: Calendar, locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }
}
