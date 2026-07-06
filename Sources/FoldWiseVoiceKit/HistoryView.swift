// The History pane content (PRD #78, slice 2): a date-grouped list of past
// dictations — TODAY / YESTERDAY / date headers, newest first — each row
// showing a timestamp and the inserted text, with an empty state when there
// is none. Hovering a row reveals Copy; a per-row overflow menu offers Delete;
// a Clear all history control (behind a confirmation) empties the store.
// Search, filters, and settings arrive in later slices.

import SwiftUI

struct HistoryPane: View {
    @ObservedObject var model: SettingsModel
    @State private var hoveredRow: UUID?
    @State private var confirmingClearAll = false

    var body: some View {
        Group {
            if model.historyEntries.isEmpty {
                emptyState
            } else {
                populated
            }
        }
        .alert("Clear all dictation history?", isPresented: $confirmingClearAll) {
            Button("Clear All", role: .destructive) { model.onClearHistory?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This permanently removes every saved dictation from this Mac. "
                    + "This can't be undone."
            )
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

    private var populated: some View {
        VStack(alignment: .leading, spacing: 16) {
            groupedList
            HStack {
                Spacer()
                Button("Clear all history…", role: .destructive) {
                    confirmingClearAll = true
                }
                .controlSize(.small)
            }
        }
    }

    private var groupedList: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(HistoryPane.grouped(model.historyEntries), id: \.header) { group in
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
            HStack(spacing: 8) {
                if hoveredRow == entry.id {
                    Button {
                        model.onCopyHistory?(entry)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy text")
                }
                overflowMenu(entry)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredRow = entry.id
            } else if hoveredRow == entry.id {
                hoveredRow = nil
            }
        }
    }

    /// The trailing kebab, mirroring the Models pane's overflow menu (kept a
    /// sibling of the row so opening it never triggers a row action). Delete
    /// removes exactly this entry from the store.
    private func overflowMenu(_ entry: HistoryEntry) -> some View {
        Menu {
            Button("Delete", role: .destructive) { model.onDeleteHistory?(entry) }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .controlSize(.small)
        .fixedSize()
        .accessibilityLabel("More actions")
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
