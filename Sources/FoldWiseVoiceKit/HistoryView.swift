// The History pane content (PRD #78, slice 1): a date-grouped list of past
// dictations — TODAY / YESTERDAY / date headers, newest first — each row
// showing a timestamp and the inserted text, with an empty state when there
// is none. Per-row actions, search, filters, and settings arrive in later
// slices; this slice only records and displays.

import SwiftUI

struct HistoryPane: View {
    let entries: [HistoryEntry]

    var body: some View {
        if entries.isEmpty {
            emptyState
        } else {
            groupedList
        }
    }

    private var emptyState: some View {
        Card {
            CardRow(
                title: "No dictations yet",
                subtitle: "Your dictations will appear here after you speak. History is "
                    + "text-only and stays on this Mac — no audio is ever saved."
            ) {
                EmptyView()
            }
        }
    }

    private var groupedList: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(HistoryPane.grouped(entries), id: \.header) { group in
                sectionHeader(group.header)
                Card {
                    ForEach(Array(group.entries.enumerated()), id: \.element.id) { i, entry in
                        if i > 0 { Divider().padding(.leading, 14) }
                        row(entry)
                    }
                }
            }
        }
    }

    private func row(_ entry: HistoryEntry) -> some View {
        CardRow(
            title: entry.text,
            subtitle: "\(entry.modeName) · \(HistoryPane.time(entry.createdAt))"
        ) {
            EmptyView()
        }
    }

    // MARK: - grouping (display-only; the view is not unit-tested per PRD #78)

    struct DayGroup {
        let header: String
        let entries: [HistoryEntry]
    }

    /// Newest entry first, bucketed by calendar day, each bucket labeled
    /// TODAY / YESTERDAY / a medium date. Buckets are ordered newest day first.
    static func grouped(_ entries: [HistoryEntry], calendar: Calendar = .current) -> [DayGroup] {
        let sorted = entries.sorted { $0.createdAt > $1.createdAt }
        var order: [Date] = []
        var buckets: [Date: [HistoryEntry]] = [:]
        for entry in sorted {
            let day = calendar.startOfDay(for: entry.createdAt)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(entry)
        }
        return order.map { day in
            DayGroup(header: header(for: day, calendar: calendar), entries: buckets[day] ?? [])
        }
    }

    private static func header(for day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return dayFormatter.string(from: day)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }
}
