// The Home view's dictation list, as a pure projection over the history the
// app already keeps (PRD #103): the newest ten entries, grouped by calendar
// day (Today / Yesterday / absolute day labels), each row reduced to a mono
// timestamp, a single-line transcript preview, and a lowercased Mode tag while
// retaining the exact source entry for direct actions. Value-in/value-out like
// `UsageStatsAggregator`, so the grouping, labeling, and truncation rules are
// unit-tested apart from the SwiftUI view.

import Foundation

struct HomeProjection: Equatable {
    struct Row: Equatable, Identifiable {
        /// Exact source identity and current persisted state for Home's direct
        /// Copy and Flag actions; the view never looks the entry up by id.
        let entry: HistoryEntry
        var id: UUID {
            entry.id
        }

        /// 24-hour mono timestamp ("20:37"), matching the design's fixed-width
        /// 44pt column — deliberately not locale-shaped, which would overflow it.
        let time: String
        /// The transcript with all whitespace runs collapsed, so the row is a
        /// genuine single line however the dictation was broken.
        let preview: String
        /// The Mode name lowercased and tail-truncated — no aliasing, so
        /// user-defined Modes render as themselves.
        let tag: String
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
    static let maxTagLength = 16

    static func project(
        _ entries: [HistoryEntry],
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> HomeProjection {
        let latest = entries.sorted { $0.createdAt > $1.createdAt }.prefix(maxRows)
        var order: [Date] = []
        var buckets: [Date: [Row]] = [:]
        let timeFormatter = makeTimeFormatter(calendar: calendar)
        for entry in latest {
            let day = calendar.startOfDay(for: entry.createdAt)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(Row(
                entry: entry,
                time: timeFormatter.string(from: entry.createdAt),
                preview: singleLine(entry.text),
                tag: tag(for: entry.modeName)
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

    /// The row's trailing Mode tag: lowercased, tail-truncated to keep the
    /// column narrow. No "raw" aliasing — that breaks with user-defined Modes.
    static func tag(for modeName: String) -> String {
        String(modeName.lowercased().prefix(maxTagLength))
    }

    private static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func header(
        for day: Date, now: Date, calendar: Calendar, formatter: DateFormatter
    ) -> String {
        let today = calendar.startOfDay(for: now)
        if day == today { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           day == yesterday {
            return "Yesterday"
        }
        return formatter.string(from: day)
    }

    private static func makeTimeFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        // Fixed template, not a locale style: the design's mono column is
        // exactly five glyphs wide.
        formatter.dateFormat = "HH:mm"
        return formatter
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
