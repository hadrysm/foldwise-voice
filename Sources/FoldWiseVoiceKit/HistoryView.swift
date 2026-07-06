// The History pane content (PRD #78): a "Save dictation history" master switch
// and a separate retention (auto-delete) control above a date-grouped list of
// past dictations — TODAY / YESTERDAY / date headers, newest first — each row
// showing a timestamp and the inserted text, with an empty state when there is
// none. A search box filters live across the polished and raw text and a
// "Flagged only" toggle narrows to bookmarked rows. Hovering a row reveals Copy
// and Flag; a per-row overflow menu offers Delete; a Clear all history control
// (behind a confirmation) empties the store. Turning saving off offers to
// delete what is already saved.

import SwiftUI

struct HistoryPane: View {
    @ObservedObject var model: SettingsModel
    @State private var hoveredRow: UUID?
    @State private var confirmingClearAll = false
    @State private var confirmingDeleteOnOff = false
    @State private var search = ""
    @State private var flaggedOnly = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            saveHistoryCard
            if model.saveHistory {
                retentionCard
            }
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
        .alert("Delete saved dictations?", isPresented: $confirmingDeleteOnOff) {
            Button("Delete", role: .destructive) { model.onClearHistory?() }
            Button("Keep", role: .cancel) {}
        } message: {
            Text(
                "Saving is now off, so no new dictations will be recorded. "
                    + "Delete the dictations already saved on this Mac?"
            )
        }
    }

    /// The master on/off switch, shown above the list in both the empty and
    /// populated states so history can be turned off before it fills. Turning
    /// it off offers to also delete what is already saved (PRD #78).
    private var saveHistoryCard: some View {
        Card {
            CardRow(
                title: "Save dictation history",
                subtitle: "Keep a text-only, on-device record of your dictations. "
                    + "Turn this off and nothing is written to disk."
            ) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { model.saveHistory },
                        set: { isOn in
                            model.saveHistory = isOn
                            model.onCommit?()
                            if !isOn, !model.historyEntries.isEmpty {
                                confirmingDeleteOnOff = true
                            }
                        }
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()
            }
        }
    }

    /// Auto-delete window, kept a separate card from the on/off switch so
    /// "Forever" and "Off" never read as the same thing (PRD #78). Shown only
    /// while saving is on, since retention governs what gets saved.
    private var retentionCard: some View {
        Card {
            CardRow(
                title: "Keep history for",
                subtitle: "Automatically delete dictations older than this. "
                    + "\u{201C}Forever\u{201D} keeps everything — it does not turn saving off."
            ) {
                Picker(
                    "",
                    selection: Binding(
                        get: { model.retention },
                        set: { newValue in
                            model.retention = newValue
                            model.onCommit?()
                        }
                    )
                ) {
                    ForEach(RetentionWindow.allCases) { window in
                        Text(window.label).tag(window)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private var emptyState: some View {
        Card {
            CardRow(
                title: "No dictations yet",
                subtitle: "Your dictations will appear here after you speak. History is "
                    + "text-only and stays on this Mac — no audio is ever saved. Use the "
                    + "switch above to turn saving off."
            ) {
                EmptyView()
            }
        }
    }

    private var populated: some View {
        let filtered = HistoryFilter.apply(
            to: model.historyEntries, query: search, flaggedOnly: flaggedOnly
        )
        return VStack(alignment: .leading, spacing: 16) {
            searchControls
            if filtered.isEmpty {
                noMatchesState
            } else {
                groupedList(filtered)
            }
            HStack {
                Spacer()
                Button("Clear all history…", role: .destructive) {
                    confirmingClearAll = true
                }
                .controlSize(.small)
            }
        }
    }

    /// Live search over both the polished and raw text, plus a Flagged-only
    /// toggle. Both narrow the loaded list in memory via `HistoryFilter`;
    /// neither touches the store.
    private var searchControls: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                TextField("Search dictations", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))

            Toggle(isOn: $flaggedOnly) {
                Label("Flagged only", systemImage: "flag.fill")
                    .font(.system(size: 12, weight: .medium))
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Show only dictations you have flagged")
        }
    }

    /// Shown when the store has entries but the search / Flagged-only filter
    /// leaves none — distinct from the first-run empty state.
    private var noMatchesState: some View {
        let flaggedButEmpty = flaggedOnly && search.trimmingCharacters(in: .whitespaces).isEmpty
        return Card {
            CardRow(
                title: flaggedButEmpty ? "No flagged dictations" : "No matches",
                subtitle: flaggedButEmpty
                    ? "Flag a dictation to bookmark it for your own review."
                    : "No dictation matches your search. Try different words, or clear "
                        + "the filters above."
            ) {
                EmptyView()
            }
        }
    }

    private func groupedList(_ entries: [HistoryEntry]) -> some View {
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
                // A flagged row keeps its filled flag on show even off-hover, so
                // the bookmark is visible at a glance; hovering reveals the flag
                // affordance on unflagged rows.
                if hoveredRow == entry.id || entry.flagged {
                    Button {
                        model.onFlagHistory?(entry)
                    } label: {
                        Image(systemName: entry.flagged ? "flag.fill" : "flag")
                            .foregroundStyle(
                                entry.flagged ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(entry.flagged ? "Remove flag" : "Flag for my review")
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
