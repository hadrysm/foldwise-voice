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
                // The top safe-area inset is AppKit's titlebar strip, where
                // the traffic lights are vertically centered — a bar of
                // exactly that height shares its center with them on any
                // macOS. In fullscreen the inset is zero (the lights
                // auto-hide), so fall back to a fixed height.
                titlebar(
                    height: geo.safeAreaInsets.top > 0
                        ? geo.safeAreaInsets.top
                        : Theme.titlebarHeight
                )
                hairline(.horizontal)
                HStack(spacing: 0) {
                    sidebar
                    hairline(.vertical)
                    content
                }
            }
            .background(Theme.windowBackground)
            // Draw the custom titlebar in the real titlebar strip, sharing
            // its row with the traffic lights, instead of below the hosting
            // view's safe-area inset.
            .ignoresSafeArea(.container, edges: .top)
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

    private func titlebar(height: CGFloat) -> some View {
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
        .frame(height: height)
        .background(Theme.sidebarBackground)
    }

    /// The standard macOS "toggle sidebar" glyph: a rounded rect with an
    /// inner vertical divider, sized as a peer of the traffic lights.
    private var sidebarToggleGlyph: some View {
        RoundedRectangle(cornerRadius: 4.5)
            .strokeBorder(Theme.textFaint, lineWidth: 1.5)
            .frame(width: 21, height: 16)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Theme.textFaint)
                    .frame(width: 1.5)
                    .padding(.vertical, 1.5)
                    .offset(x: 6)
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
