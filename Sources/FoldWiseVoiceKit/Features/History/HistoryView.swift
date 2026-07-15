// The History pane content (PRD #78): a "Save dictation history" master switch
// and a separate retention (auto-delete) control above a date-grouped list of
// past dictations — TODAY / YESTERDAY / date headers, newest first — each row
// showing a timestamp and the inserted text, with an empty state when there is
// none. A search box filters live across the polished and raw text and a
// "Flagged only" toggle narrows to bookmarked rows. Hovering a row reveals Copy
// and Flag; a per-row overflow menu offers Copy raw (when the row is polished),
// Re-run Polish under a chosen Mode, and Delete; a Clear all history control
// (behind a confirmation) empties the store. Turning saving off offers to
// delete what is already saved.

import Combine
import SwiftUI

struct HistoryPane: View {
    @ObservedObject var model: SettingsModel
    @State private var confirmingClearAll = false
    @State private var confirmingDeleteOnOff = false
    @State private var search = ""
    @State private var flaggedOnly = false
    @State private var projection = HistoryProjection.empty
    @State private var projectionCache: HistoryProjectionCache
    private let notificationCenter: NotificationCenter

    init(
        model: SettingsModel,
        projectionCache: HistoryProjectionCache = HistoryProjectionCache(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.model = model
        _projectionCache = State(initialValue: projectionCache)
        self.notificationCenter = notificationCenter
    }

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
        .onChange(of: projectionInput, initial: true) { _, input in
            projection = projectionCache.resolve(input)
        }
        .onReceive(notificationCenter.publisher(for: .NSCalendarDayChanged)) { _ in
            projection = projectionCache.resolve(projectionInput)
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
        VStack(alignment: .leading, spacing: 16) {
            searchControls
            if projection.isEmpty {
                noMatchesState
            } else {
                HistoryCollection(
                    projection: projection,
                    polishModeNames: polishModeNames,
                    onCommand: { entry, command in
                        model.onHistoryCommand?(entry, command)
                    }
                )
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

    private var projectionInput: HistoryProjection.Input {
        HistoryProjection.Input(
            entries: model.historyEntries,
            search: search,
            flaggedOnly: flaggedOnly
        )
    }

    private var polishModeNames: [String] {
        model.modeNames.filter { model.llmModes.contains($0) }
    }

    /// Live search over both the polished and raw text, plus a Flagged-only
    /// toggle. Both narrow the loaded list through `HistoryProjection`;
    /// neither touches the store.
    private var searchControls: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.textSecondary)
                TextField("Search dictations", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.textTertiary)
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
                    .font(Theme.ui(12, .medium))
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Show only dictations you have flagged")
        }
    }

    /// Shown when the store has entries but the search / Flagged-only filter
    /// leaves none — distinct from the first-run empty state.
    private var noMatchesState: some View {
        let flaggedButEmpty = flaggedOnly && search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
}

/// Value-fed collection rendering. It deliberately observes no Settings state;
/// only a new projection or action values can invalidate this lazy tree.
private struct HistoryCollection: View {
    let projection: HistoryProjection
    let polishModeNames: [String]
    let onCommand: (HistoryEntry, DictationRowCommand) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(projection.sections, id: \.header) { section in
                sectionHeader(section.header)
                Card {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 {
                                Divider().padding(.leading, 14)
                            }
                            DictationRow(
                                presentation: row.presentation,
                                moreCapabilities: DictationRowMoreCapabilities(
                                    canCopyRaw: row.entry.isPolished,
                                    polishModeNames: polishModeNames
                                ),
                                onCommand: { command in
                                    onCommand(row.entry, command)
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}
