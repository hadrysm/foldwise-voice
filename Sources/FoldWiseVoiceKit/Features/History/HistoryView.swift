// History's Instrument Panel composition. The pane keeps persistence,
// filtering, grouping, row commands, and confirmations with their existing
// owners while presenting the shared Dictation rows through Ember Edge chrome.

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
    @FocusState private var searchFocused: Bool
    @FocusState private var clearSearchFocused: Bool
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
        VStack(alignment: .leading, spacing: 14) {
            Text("Saved locally on this Mac. Audio is never retained.")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityIdentifier("history.assurance")
            preferences
            if !model.saveHistory, !model.historyEntries.isEmpty {
                savingOffNotice
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

    private var preferences: some View {
        HStack(alignment: .top, spacing: 10) {
            preferenceCell(
                symbolName: "externaldrive",
                title: "Save dictation history",
                detail: model.saveHistory
                    ? "On · text only, on this Mac"
                    : "Off · new Dictation sessions are not saved"
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
            .accessibilityIdentifier("history.preference.saving")

            if model.saveHistory {
                preferenceCell(
                    symbolName: "calendar",
                    title: "Keep dictations",
                    detail: "Automatically removes older saved text"
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
                .accessibilityIdentifier("history.preference.retention")
            }
        }
    }

    private func preferenceCell(
        symbolName: String,
        title: String,
        detail: String,
        @ViewBuilder control: () -> some View
    ) -> some View {
        EmberSurface {
            HStack(spacing: 10) {
                Image(systemName: symbolName)
                    .font(Theme.ui(13, .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Theme.ui(12, .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(detail)
                        .font(Theme.ui(10.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                control()
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var emptyState: some View {
        EmberEmptyState(
            symbolName: "clock",
            title: "No saved Dictation sessions.",
            detail: model.saveHistory
                ? "Your saved text will appear here after you speak."
                : "Turn on History when you want new Dictation sessions saved."
        )
        .accessibilityIdentifier("history.empty.first-run")
    }

    private var savingOffNotice: some View {
        EmberStatusNotice(
            kind: .warning,
            title: "History saving is off",
            detail: "Existing saved Dictation sessions remain available until you delete them."
        )
        .frame(minHeight: 48)
        .accessibilityIdentifier("history.saving-off")
    }

    private var populated: some View {
        VStack(alignment: .leading, spacing: 16) {
            searchControls
            if projection.isEmpty {
                noMatchesState
            } else {
                HistoryCollection(
                    projection: projection,
                    polishModes: polishModes,
                    onCommand: { entry, command in
                        model.onHistoryCommand?(entry, command)
                    }
                )
            }
            HStack {
                Button("Clear all history…", role: .destructive) {
                    confirmingClearAll = true
                }
                .buttonStyle(EmberButtonStyle(kind: .destructive))
                .accessibilityIdentifier("history.clear-all")
                Spacer()
            }
        }
    }

    private var projectionInput: HistoryProjection.Input {
        HistoryProjection.Input(
            entries: model.historyEntries,
            search: search,
            flaggedOnly: flaggedOnly,
            modes: model.modes
        )
    }

    private var polishModes: [DictationRowPolishMode] {
        model.modes.compactMap { mode in
            guard mode.usesLLM, let id = mode.id else { return nil }
            return DictationRowPolishMode(id: id, name: mode.name)
        }
    }

    /// Live search over both the polished and raw text, plus a Flagged-only
    /// toggle. Both narrow the loaded list through `HistoryProjection`;
    /// neither touches the store.
    private var searchControls: some View {
        EmberSurface {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(Theme.ui(12))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                    TextField("Search dictations", text: $search)
                        .textFieldStyle(.plain)
                        .font(Theme.ui(11.5))
                        .focused($searchFocused)
                        .accessibilityLabel("Search Dictations")
                        .accessibilityIdentifier("history.search")
                    if !search.isEmpty {
                        Button {
                            search = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.textTertiary)
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                        .focused($clearSearchFocused)
                        .emberFocusRing(clearSearchFocused)
                        .help("Clear search")
                    }
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(
                    Theme.raised,
                    in: RoundedRectangle(cornerRadius: Theme.controlRadius)
                )
                .emberFocusRing(searchFocused)

                Toggle(isOn: $flaggedOnly) {
                    Label(
                        "Flagged only",
                        systemImage: flaggedOnly ? "flag.fill" : "flag"
                    )
                    .font(Theme.ui(11.5, .medium))
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Show only Dictation sessions you have flagged")
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("history.flagged-only")
            }
            .padding(.horizontal, 8)
            .frame(height: 42)
            .accessibilityElement(children: .contain)
        }
        .accessibilityIdentifier("history.utility")
    }

    /// Shown when the store has entries but the search / Flagged-only filter
    /// leaves none — distinct from the first-run empty state.
    private var noMatchesState: some View {
        let flaggedButEmpty = flaggedOnly && search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let presentation = if flaggedButEmpty {
            (
                symbolName: "flag",
                title: "No flagged Dictation sessions.",
                detail: "Flag a Dictation session to keep it in this focused view.",
                accessibilityIdentifier: "history.empty.no-flagged"
            )
        } else {
            (
                symbolName: "magnifyingglass",
                title: "No matches.",
                detail: "Try different words or clear the filters above.",
                accessibilityIdentifier: "history.empty.no-results"
            )
        }
        return EmberEmptyState(
            symbolName: presentation.symbolName,
            title: presentation.title,
            detail: presentation.detail
        )
        .accessibilityIdentifier(presentation.accessibilityIdentifier)
    }
}

/// Value-fed collection rendering. It deliberately observes no Settings state;
/// only a new projection or action values can invalidate this lazy tree.
private struct HistoryCollection: View {
    let projection: HistoryProjection
    let polishModes: [DictationRowPolishMode]
    let onCommand: (HistoryEntry, DictationRowCommand) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(projection.sections, id: \.header) { section in
                EmberSectionLabel(section.header, symbolName: "calendar")
                EmberSurface {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                            DictationRow(
                                presentation: row.presentation,
                                moreCapabilities: DictationRowMoreCapabilities(
                                    canCopyRaw: row.entry.isPolished,
                                    polishModes: polishModes
                                ),
                                onCommand: { command in
                                    onCommand(row.entry, command)
                                }
                            )
                            if index < section.rows.count - 1 {
                                EmberHairline(axis: .horizontal)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.surfaceRadius))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history.collection")
    }
}
