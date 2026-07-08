// Main window content (PRD #103, "Editorial"): a custom titlebar with a
// sidebar toggle (button + ⌘\), a collapsible sidebar that animates between
// the 190pt labeled list and the 52pt icon rail (tooltip chips on hover), and
// six panes — Home, Modes, Models, History, Stats, Settings. The old Speech
// pane lives inside Models; Configuration and Sound merged into Settings.
// Every change saves straight to modes.json; there is no Save button.

import AppKit
import SwiftUI

/// App version shared by the sidebar footer, the Settings pane, and Home's
/// system summary. Set in Info.plist by scripts/build_swift_app.py from
/// version.txt; absent when running the bare binary (swift run).
enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "dev"
    }
}

/// Rail-tile bounds, collected so the tooltip chip can be drawn at the window
/// level — a chip drawn inside the 52pt rail would be covered by the content
/// column rendered after it.
struct RailTileBoundsKey: PreferenceKey {
    static let defaultValue: [SettingsModel.Pane: Anchor<CGRect>] = [:]
    static func reduce(
        value: inout [SettingsModel.Pane: Anchor<CGRect>],
        nextValue: () -> [SettingsModel.Pane: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { $1 }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                titlebar
                hairline(.horizontal)
                HStack(spacing: 0) {
                    sidebar
                    hairline(.vertical)
                    content
                }
            }
            .background(Theme.windowBackground)
            .onAppear {
                model.windowWidth = geo.size.width
                model.sidebar.widthChanged(to: geo.size.width)
            }
            .onChange(of: geo.size.width) { _, width in
                model.windowWidth = width
                model.sidebar.widthChanged(to: width)
            }
        }
        .overlayPreferenceValue(RailTileBoundsKey.self) { anchors in
            railTooltip(anchors)
        }
        .frame(minWidth: 880, minHeight: 640)
    }

    private var sidebarMode: SidebarMode {
        model.sidebar.mode(forWidth: model.windowWidth)
    }

    private func hairline(_ axis: Axis) -> some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(
                width: axis == .vertical ? 1 : nil,
                height: axis == .horizontal ? 1 : nil
            )
    }

    // MARK: - titlebar

    private var titlebar: some View {
        HStack(spacing: 12) {
            // Clear the traffic lights drawn by the fullSizeContentView window.
            Spacer().frame(width: 70)
            Button {
                model.sidebar.toggle(width: model.windowWidth)
                model.onCommit?()
            } label: {
                sidebarToggleGlyph
            }
            .buttonStyle(.plain)
            .keyboardShortcut("\\", modifiers: .command)
            .help("Toggle sidebar (⌘\\)")
            Text("FoldWise Voice")
                .font(Theme.ui(12.5, .semibold))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
        }
        .frame(height: 44)
        .background(Theme.sidebarBackground)
    }

    /// The standard macOS "toggle sidebar" glyph: a rounded rect with an
    /// inner vertical divider.
    private var sidebarToggleGlyph: some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Theme.textFaint, lineWidth: 1.5)
            .frame(width: 27, height: 22)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Theme.textFaint)
                    .frame(width: 1.5)
                    .padding(.vertical, 1.5)
                    .offset(x: 8)
            }
            .contentShape(Rectangle())
    }

    // MARK: - sidebar

    private var sidebar: some View {
        Group {
            if sidebarMode == .expanded {
                expandedSidebar.frame(width: Theme.sidebarWidth)
            } else {
                railSidebar.frame(width: Theme.railWidth)
            }
        }
        .background(Theme.sidebarBackground)
        .clipped()
        .animation(Theme.sidebarAnimation, value: sidebarMode)
    }

    private var expandedSidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsModel.Pane.allCases) { pane in
                navRow(pane)
            }
            Spacer()
            footer
        }
        .padding(10)
    }

    private func navRow(_ pane: SettingsModel.Pane) -> some View {
        let active = model.pane == pane
        return Button {
            model.pane = pane
        } label: {
            HStack(spacing: 10) {
                Image(systemName: pane.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(active ? Theme.accent : Theme.textTertiary)
                    .frame(width: 18)
                Text(pane.rawValue)
                    .font(active ? Theme.navActive : Theme.nav)
                    .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            active ? Theme.activeNavBackground : Color.clear,
            in: RoundedRectangle(cornerRadius: Theme.navRadius)
        )
        .shadow(color: active ? Theme.activeNavShadow : .clear, radius: 3, y: 1)
    }

    private var railSidebar: some View {
        VStack(spacing: 4) {
            ForEach(SettingsModel.Pane.allCases) { pane in
                railTile(pane)
            }
            Spacer()
        }
        .padding(.vertical, 10)
    }

    private func railTile(_ pane: SettingsModel.Pane) -> some View {
        let active = model.pane == pane
        return Button {
            model.pane = pane
        } label: {
            Image(systemName: pane.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(active ? Theme.accent : Theme.textTertiary)
                .frame(width: 36, height: 36)
                .background(
                    active ? Theme.activeNavBackground : Color.clear,
                    in: RoundedRectangle(cornerRadius: Theme.railTileRadius)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shadow(color: active ? Theme.activeNavShadow : .clear, radius: 3, y: 1)
        .anchorPreference(key: RailTileBoundsKey.self, value: .bounds) { [pane: $0] }
        .onHover { hovering in
            if hovering {
                model.hoveredRailPane = pane
            } else if model.hoveredRailPane == pane {
                model.hoveredRailPane = nil
            }
        }
    }

    /// The hovered rail tile's tooltip chip, 10pt to its right and vertically
    /// centered, drawn over everything so the content column can't cover it.
    private func railTooltip(_ anchors: [SettingsModel.Pane: Anchor<CGRect>]) -> some View {
        GeometryReader { proxy in
            if sidebarMode == .rail,
               let pane = model.hoveredRailPane,
               let anchor = anchors[pane] {
                let rect = proxy[anchor]
                Text(pane.rawValue)
                    .font(Theme.tooltip)
                    .foregroundStyle(Theme.tooltipText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Theme.tooltipBackground,
                        in: RoundedRectangle(cornerRadius: Theme.tooltipRadius)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                    .fixedSize()
                    .offset(x: rect.maxX + 10, y: rect.midY - 12)
                    .transition(.opacity.combined(with: .offset(x: -4)))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.hoveredRailPane)
    }

    /// Version footer pinned to the sidebar's bottom, with the update state
    /// folded into one faint line and an accent link when a release is out.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            if case let .available(version, downloadURL) = model.updateState {
                Button("Get v\(version)") {
                    NSWorkspace.shared.open(downloadURL ?? UpdateChecker.releasesPage)
                }
                .buttonStyle(.plain)
                .font(Theme.ui(11, .semibold))
                .foregroundStyle(Theme.accent)
            }
            Text(footerText)
                .font(Theme.ui(11))
                .foregroundStyle(Theme.textFaint)
        }
        .padding(.horizontal, 11)
        .padding(.bottom, 8)
    }

    private var footerText: String {
        switch model.updateState {
        case .checking: "v\(AppInfo.version) · checking…"
        case .upToDate: "v\(AppInfo.version) · up to date"
        case let .available(version, _): "v\(AppInfo.version) · v\(version) available"
        case .idle, .failed, .unavailable: "v\(AppInfo.version)"
        }
    }

    // MARK: - content shell

    private var content: some View {
        VStack(spacing: 0) {
            switch model.pane {
            case .home:
                HomeView(model: model)
            case .modes:
                paneScroll("Modes") { modesPane }
            case .models:
                paneScroll("Models") { ModelsCombinedPane(model: model) }
            case .history:
                paneScroll("History") { HistoryPane(model: model) }
            case .stats:
                paneScroll("Stats") { StatsPane(model: model) }
            case .settings:
                paneScroll("Settings") { settingsPane }
            }
            if !model.status.isEmpty {
                hairline(.horizontal)
                Text(model.status)
                    .font(Theme.ui(12))
                    .foregroundStyle(model.statusIsError ? AnyShapeStyle(.red) : AnyShapeStyle(Theme.textSecondary))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
        }
    }

    private func paneScroll(_ title: String, @ViewBuilder body: () -> some View) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(Theme.pageTitle)
                    .kerning(-0.56)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.bottom, 4)
                body()
            }
            .padding(.horizontal, Theme.contentPadding)
            .padding(.top, Theme.contentPadding)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - modes

    private var modesPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("The active mode decides how your dictation is processed after transcription.")
                .font(Theme.ui(12))
                .foregroundStyle(Theme.textSecondary)
            Card {
                ForEach(Array(model.modeNames.enumerated()), id: \.element) { i, name in
                    if i > 0 { Divider().padding(.leading, 14) }
                    Button {
                        model.activeMode = name
                        model.onCommit?()
                    } label: {
                        CardRow(
                            title: name,
                            subtitle: model.llmModes.contains(name)
                                ? "Polished with \(model.selectedModel.isEmpty ? "Ollama" : model.selectedModel)"
                                : "Raw transcription — no LLM"
                        ) {
                            Image(
                                systemName: model.activeMode == name
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                            .foregroundStyle(
                                model.activeMode == name
                                    ? AnyShapeStyle(Theme.accent)
                                    : AnyShapeStyle(Theme.textTertiary)
                            )
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Button("Edit modes.json…") { model.onEditFile?() }
                Text("Prompts and vocabulary live in the config file.")
                    .font(Theme.ui(11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - settings (keyboard shortcuts + sound + updates)

    private var settingsPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Keyboard shortcuts")
            Card {
                CardRow(
                    title: "Push to Talk",
                    subtitle: "Hold to record, release when done"
                ) {
                    HStack(spacing: 8) {
                        resetButton(icon: "arrow.counterclockwise", help: "Reset to right ⌥") {
                            model.pttKey = "alt_r"
                            model.onCommit?()
                        }
                        shortcutChip(key: model.pttKey, field: .ptt)
                    }
                }
                Divider().padding(.leading, 14)
                CardRow(
                    title: "Toggle Recording",
                    subtitle: "Starts and stops recordings"
                ) {
                    HStack(spacing: 8) {
                        if !model.toggleKey.isEmpty {
                            resetButton(icon: "xmark", help: "Remove shortcut") {
                                model.toggleKey = ""
                                model.onCommit?()
                            }
                        }
                        shortcutChip(key: model.toggleKey, field: .toggle)
                    }
                }
            }
            Text(
                "Click a shortcut, then press the key you want — a modifier "
                    + "(⌥ ⌘ ⌃ ⇧), a function key, or a single character."
            )
            .font(Theme.ui(11))
            .foregroundStyle(Theme.textSecondary)

            sectionHeader("Sound")
            Card {
                CardRow(
                    title: "Pause other audio",
                    subtitle: "Pause music and mute system audio while dictating"
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.pauseAudio },
                            set: {
                                model.pauseAudio = $0
                                model.onCommit?()
                            }
                        )
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }

            sectionHeader("Updates")
            Card {
                CardRow(title: "Updates", subtitle: updateSubtitle) {
                    updateTrailing
                }
            }
        }
    }

    private var updateSubtitle: String {
        switch model.updateState {
        case .idle: "Version \(AppInfo.version)"
        case .checking: "Version \(AppInfo.version) — checking for updates…"
        case .upToDate: "Version \(AppInfo.version) — you're up to date"
        case let .available(version, _): "Version \(AppInfo.version) — v\(version) is available"
        case .failed: "Version \(AppInfo.version) — couldn't reach GitHub, try again later"
        case .unavailable: "Version \(AppInfo.version) — update checks need a packaged build"
        }
    }

    @ViewBuilder
    private var updateTrailing: some View {
        switch model.updateState {
        case .checking:
            ProgressView().controlSize(.small)
        case let .available(version, downloadURL):
            Button("Download v\(version)…") {
                NSWorkspace.shared.open(downloadURL ?? UpdateChecker.releasesPage)
            }
            .controlSize(.small)
        case .unavailable:
            EmptyView()
        case .upToDate:
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Check for Updates") { model.onCheckUpdates?() }
                    .controlSize(.small)
            }
        case .idle, .failed:
            Button("Check for Updates") { model.onCheckUpdates?() }
                .controlSize(.small)
        }
    }

    private func resetButton(icon: String, help: String, action: @escaping () -> Void)
        -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func shortcutChip(key: String, field: SettingsModel.RecordingField) -> some View {
        Button {
            model.onRecord?(field)
        } label: {
            Group {
                if model.recordingField == field {
                    Text("Press a key…")
                        .font(Theme.ui(12, .medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                } else if key.isEmpty {
                    Text("Click to set")
                        .font(Theme.ui(12))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
                } else {
                    Keycap(text: keycapLabel(key))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

func keycapLabel(_ name: String) -> String {
    if name.count == 1 { return name.uppercased() }
    return KeyMap.pretty(name) // "right ⌥", "f19", "esc", …
}

// MARK: - models (ASR + Ollama in one pane)

/// The merged Models pane (PRD #103): everything model-shaped in one place —
/// the speech (ASR) catalog on top, the Polish (Ollama) models below. Both
/// sections are the previous panes unchanged in behavior.
struct ModelsCombinedPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("Speech recognition")
                SpeechPane(model: model)
            }
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("Polish (Ollama)")
                ModelsPane(model: model)
            }
        }
    }
}

// MARK: - speech

/// The ASR section (ADR-0006): a curated catalog split into "Your Models"
/// (downloaded) and "Available", mirroring the Ollama `ModelsPane`. Rows lead
/// with language coverage; a downloaded model is a selectable row with a
/// checkmark for the active one, an available model shows a Download button with
/// fractional progress. Selection routes through `onSelectASRModel`, which
/// persists via `setASRModel` and triggers the dispatcher's drop-before-load swap.
struct SpeechPane: View {
    @ObservedObject var model: SettingsModel
    /// Armed by a downloaded row's kebab; drives the delete confirmation alert.
    @State private var pendingDelete: ASRModelCatalog.Entry?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(
                "Choose which speech model transcribes your dictation — it applies to "
                    + "every mode. Parakeet is built in; Whisper reaches ~99 languages and "
                    + "downloads on first use, then runs on-device."
            )
            .font(Theme.ui(12))
            .foregroundStyle(Theme.textSecondary)

            let downloaded = ASRModelCatalog.entries.filter { model.asrDownloaded.contains($0.id) }
            let available = ASRModelCatalog.entries.filter { !model.asrDownloaded.contains($0.id) }

            if !downloaded.isEmpty { section("Your Models", downloaded) }
            if !available.isEmpty { section("Available", available) }

            if !model.asrDownloadError.isEmpty {
                Label(model.asrDownloadError, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.ui(11))
                    .foregroundStyle(.red)
            }
            if !model.asrDeleteError.isEmpty {
                Label(model.asrDeleteError, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.ui(11))
                    .foregroundStyle(.red)
            }
        }
        .alert(
            "Delete \(pendingDelete?.name ?? "")?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { entry in
            Button("Delete", role: .destructive) { model.onDeleteASRModel?(entry.id) }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text(
                ASRModelCatalog.deleteOutcome(for: entry, isActive: model.asrModel == entry.id)
                    .message
            )
        }
    }

    /// A titled card of rows, mirroring the Ollama `ModelsPane`'s Installed /
    /// Model-library split so the pane separates downloaded from available.
    @ViewBuilder
    private func section(_ title: String, _ entries: [ASRModelCatalog.Entry]) -> some View {
        sectionHeader(title)
        Card {
            ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                if i > 0 { Divider().padding(.leading, 14) }
                row(entry)
            }
        }
    }

    /// The select `Button` (title, ratings, checkmark) and the trailing
    /// Download/spinner are siblings, never nested — a disabled select row would
    /// otherwise also disable a nested Download button (cf. `ModelsPane`).
    private func row(_ entry: ASRModelCatalog.Entry) -> some View {
        let downloaded = model.asrDownloaded.contains(entry.id)
        let selected = model.asrModel == entry.id
        let downloading = model.asrDownloading == entry.id
        let deleting = model.asrDeleting == entry.id
        // The built-in default (Parakeet v3) is the permanent fallback and
        // re-downloads at launch, so it is never offered for deletion.
        let deletable = downloaded && !deleting && entry.id != ASRModelCatalog.defaultID
        return HStack(alignment: .center, spacing: 12) {
            Button {
                model.onSelectASRModel?(entry.id)
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(entry.name)  ·  \(entry.languages)")
                            .font(Theme.ui(13, .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(entry.blurb).font(Theme.ui(11)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 16)
                    if deleting {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Deleting…").font(Theme.ui(11)).foregroundStyle(Theme.textSecondary)
                        }
                    } else {
                        ratings(entry)
                        if downloaded {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(
                                    selected
                                        ? AnyShapeStyle(Theme.accent)
                                        : AnyShapeStyle(Theme.textTertiary)
                                )
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!downloaded || deleting)

            if downloading {
                HStack(spacing: 8) {
                    downloadProgress
                    Button {
                        model.onCancelASRDownload?()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel download")
                    .accessibilityLabel("Cancel download for \(entry.name)")
                }
            } else if !downloaded {
                Button("Download") { model.onDownloadASRModel?(entry.id) }
                    .controlSize(.small)
                    .disabled(model.asrDownloading != nil)
            } else if deletable {
                deleteMenu(entry)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// The trailing kebab on a downloaded row: a borderless `ellipsis` whose one
    /// item arms the delete confirmation. A sibling of the select `Button`, never
    /// nested, so opening it can't also select the model (cf. `ModelsPane`).
    private func deleteMenu(_ entry: ASRModelCatalog.Entry) -> some View {
        Menu {
            Button("Delete…", role: .destructive) { pendingDelete = entry }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .controlSize(.small)
        .fixedSize()
        .disabled(model.asrDownloading != nil || model.asrDeleting != nil)
        .accessibilityLabel("More actions for \(entry.name)")
    }

    /// A fractional bar mirroring the Ollama pull UX once the engine reports a
    /// percentage; before the first fraction (or for Parakeet, which reports
    /// none) it degrades to the existing indeterminate spinner (#93). Once the
    /// weights are fetched, the trailing compile-onto-the-ANE phase shows
    /// "Preparing…" so the bar doesn't sit frozen at 100%.
    @ViewBuilder
    private var downloadProgress: some View {
        if model.asrPreparing {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Preparing…").font(Theme.ui(11)).foregroundStyle(Theme.textSecondary)
            }
        } else if let fraction = model.asrDownloadFraction {
            VStack(alignment: .trailing, spacing: 2) {
                ProgressView(value: fraction).frame(width: 110)
                Text("\(Int(fraction * 100))%")
                    .font(Theme.ui(10)).foregroundStyle(Theme.textSecondary)
            }
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Downloading…").font(Theme.ui(11)).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func ratings(_ entry: ASRModelCatalog.Entry) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(entry.size).font(Theme.ui(10)).foregroundStyle(Theme.textSecondary)
            RatingDots(label: "Speed", value: entry.speed)
            RatingDots(label: "Quality", value: entry.quality)
        }
    }
}

// MARK: - Ollama models

/// The Ollama section owns the pending-uninstall selection: the kebab overflow
/// menu on an installed row arms `pendingUninstall`, which drives the
/// confirmation alert. Removal itself is mediated by SettingsController via
/// `onDeleteModel`.
struct ModelsPane: View {
    @ObservedObject var model: SettingsModel
    @State private var pendingUninstall: OllamaClient.InstalledModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(
                "The polish model rewrites your transcript (cleanup, email, bullets). "
                    + "It applies to every mode that uses an LLM. Speed and quality are "
                    + "rated for dictation on Apple Silicon."
            )
            .font(Theme.ui(12))
            .foregroundStyle(Theme.textSecondary)

            if model.installed == nil {
                Card {
                    CardRow(title: "Checking Ollama…", subtitle: nil) { ProgressView().controlSize(.small) }
                }
            } else if model.ollamaDown {
                Card {
                    CardRow(
                        title: "Ollama isn't running",
                        subtitle: "Start the Ollama app (or `brew services start ollama`), then retry."
                    ) {
                        Button("Retry") { model.onRefreshModels?() }.controlSize(.small)
                    }
                }
            } else {
                sectionHeader("Installed")
                Card {
                    ForEach(Array((model.installed ?? []).enumerated()), id: \.element.id) { i, installed in
                        if i > 0 { Divider().padding(.leading, 14) }
                        installedRow(installed)
                    }
                    if !model.selectedModel.isEmpty && !model.selectedModelInstalled {
                        if !(model.installed ?? []).isEmpty { Divider().padding(.leading, 14) }
                        missingSelectedRow
                    }
                }

                sectionHeader("Model library")
                Card {
                    let library = ModelCatalog.entries.filter { entry in
                        !(model.installed ?? []).contains { $0.name == entry.name }
                    }
                    if library.isEmpty {
                        CardRow(title: "All recommended models are installed", subtitle: nil) {
                            EmptyView()
                        }
                    }
                    ForEach(Array(library.enumerated()), id: \.element.id) { i, entry in
                        if i > 0 { Divider().padding(.leading, 14) }
                        libraryRow(entry)
                    }
                }

                sectionHeader("Other")
                Card {
                    CardRow(
                        title: "Install by name",
                        subtitle: "Any model from ollama.com/library, e.g. qwen2.5:14b"
                    ) {
                        HStack(spacing: 8) {
                            TextField("model:tag", text: $model.customModel)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                            installButton(
                                for: model.customModel.trimmingCharacters(in: .whitespaces)
                            )
                        }
                    }
                }

                if !model.pullError.isEmpty {
                    Label(model.pullError, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.ui(11))
                        .foregroundStyle(.red)
                }
                if !model.deleteError.isEmpty {
                    Label(model.deleteError, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.ui(11))
                        .foregroundStyle(.red)
                }
            }
        }
        .alert(
            "Uninstall \(pendingUninstall?.name ?? "")?",
            isPresented: Binding(
                get: { pendingUninstall != nil },
                set: { if !$0 { pendingUninstall = nil } }
            ),
            presenting: pendingUninstall
        ) { target in
            Button("Uninstall", role: .destructive) { model.onDeleteModel?(target.name) }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            Text(uninstallMessage(for: target))
        }
    }

    /// Body of the confirmation alert: the space freed, plus the raw-text
    /// warning when the row is the model Polish currently uses.
    private func uninstallMessage(for target: OllamaClient.InstalledModel) -> String {
        var message = target.sizeText.isEmpty
            ? "This permanently removes \(target.name) from Ollama."
            : "This permanently removes \(target.name) and frees \(target.sizeText)."
        if target.name == model.selectedModel {
            message += " It's your current Polish model, so dictation will insert "
                + "raw text until you choose another."
        }
        return message
    }

    private func modelRatings(_ name: String) -> some View {
        Group {
            if let entry = ModelCatalog.entry(for: name) {
                VStack(alignment: .trailing, spacing: 3) {
                    RatingDots(label: "Speed", value: entry.speed)
                    RatingDots(label: "Quality", value: entry.quality)
                }
            }
        }
    }

    /// The installed row is two independent, non-nested controls sharing the
    /// card row's padding: the row-body select `Button` (title, ratings,
    /// checkmark) and, at the trailing edge, the kebab overflow `Menu`. Keeping
    /// the `Menu` a sibling of the `Button` — never nested inside it — avoids the
    /// macOS click-bleed where opening the menu would also select the model.
    private func installedRow(_ installed: OllamaClient.InstalledModel) -> some View {
        let entry = ModelCatalog.entry(for: installed.name)
        let selected = installed.name == model.selectedModel
        let deleting = model.deletingModel == installed.name
        return HStack(alignment: .center, spacing: 12) {
            Button {
                model.onSelectModel?(installed.name)
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(installed.name
                            + (installed.sizeText.isEmpty ? "" : "  ·  \(installed.sizeText)"))
                            .font(Theme.ui(13, .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if let blurb = entry?.blurb, !blurb.isEmpty {
                            Text(blurb).font(Theme.ui(11)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Spacer(minLength: 16)
                    if deleting {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Uninstalling…")
                                .font(Theme.ui(11))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    } else {
                        modelRatings(installed.name)
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(
                                selected
                                    ? AnyShapeStyle(Theme.accent)
                                    : AnyShapeStyle(Theme.textTertiary)
                            )
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(deleting)

            if !deleting {
                uninstallMenu(for: installed)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// The trailing kebab: a borderless, chevron-less `ellipsis` whose only item
    /// arms the destructive uninstall confirmation. Disabled while any model is
    /// pulling or being deleted so a conflicting op can't start.
    private func uninstallMenu(for installed: OllamaClient.InstalledModel) -> some View {
        Menu {
            Button("Uninstall…", role: .destructive) { pendingUninstall = installed }
        } label: {
            // The bare `ellipsis` glyph is wide but only a few points tall, so on
            // its own it gives a thin, hard-to-hit target under `.plain`. A square
            // frame plus a rectangular content shape widens the click area to a
            // comfortable 28pt without resizing the glyph; it fits inside the row's
            // height so it doesn't change row layout.
            Image(systemName: "ellipsis")
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .controlSize(.small)
        .fixedSize()
        .disabled(model.pullingModel != nil || model.deletingModel != nil)
        .accessibilityLabel("More actions for \(installed.name)")
    }

    private var missingSelectedRow: some View {
        CardRow(
            title: model.selectedModel,
            subtitle: "Configured in modes.json but not installed — polishing falls back "
                + "to the raw transcript until it is."
        ) {
            HStack(spacing: 12) {
                modelRatings(model.selectedModel)
                installButton(for: model.selectedModel)
            }
        }
    }

    private func libraryRow(_ entry: ModelCatalog.Entry) -> some View {
        CardRow(title: "\(entry.name)  ·  \(entry.size)", subtitle: entry.blurb) {
            HStack(spacing: 12) {
                modelRatings(entry.name)
                installButton(for: entry.name)
            }
        }
    }

    @ViewBuilder
    private func installButton(for name: String) -> some View {
        if model.pullingModel == name {
            VStack(alignment: .trailing, spacing: 2) {
                ProgressView(value: model.pullFraction)
                    .frame(width: 110)
                Text(pullProgressText)
                    .font(Theme.ui(10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        } else {
            Button("Install") { model.onInstallModel?(name) }
                .controlSize(.small)
                .disabled(name.isEmpty || model.pullingModel != nil)
        }
    }

    private var pullProgressText: String {
        if let fraction = model.pullFraction {
            return "\(Int(fraction * 100))% — \(model.pullStatus)"
        }
        return model.pullStatus
    }
}
