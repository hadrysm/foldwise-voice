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

struct AppearanceTilePresentation: Identifiable, Equatable {
    let preference: AppearancePreference
    let title: String
    let symbolName: String
    let detail: String

    var id: AppearancePreference {
        preference
    }

    static let all = [
        AppearanceTilePresentation(
            preference: .system,
            title: "System",
            symbolName: "circle.lefthalf.filled",
            detail: "Follows macOS as it changes"
        ),
        AppearanceTilePresentation(
            preference: .light,
            title: "Light",
            symbolName: "sun.max",
            detail: "Always uses the light appearance"
        ),
        AppearanceTilePresentation(
            preference: .dark,
            title: "Dark",
            symbolName: "moon",
            detail: "Always uses the dark appearance"
        ),
    ]
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

/// The single piece of selection chrome that moves between navigation rows.
/// Keeping it separate from row content gives the sidebar Motion-style layout
/// animation without transitioning the destination views themselves.
private struct SidebarSelectionChrome: View {
    let showsCheckmark: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.controlRadius)
            .fill(Theme.raised)
            .overlay(alignment: .leading) {
                EmberIngress(color: Theme.accent)
                    .frame(height: 22)
            }
            .overlay(alignment: .trailing) {
                if showsCheckmark {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .padding(.trailing, Theme.sidebarRowContentInset)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var presentationResetGeneration = 0
    @FocusState private var focusedNavigationPane: SettingsModel.Pane?

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
                EmberHairline(axis: .horizontal)
                HStack(spacing: 0) {
                    sidebar
                    EmberHairline(axis: .vertical)
                    content
                }
            }
            .background(Theme.canvas)
            // Draw the custom titlebar in the real titlebar strip, sharing
            // its row with the traffic lights, instead of below the hosting
            // view's safe-area inset.
            .ignoresSafeArea(.container, edges: .top)
            .onAppear {
                updateWindowWidth(geo.size.width)
            }
            .onChange(of: geo.size.width) { _, width in
                updateWindowWidth(width)
            }
        }
        .overlayPreferenceValue(RailTileBoundsKey.self) { anchors in
            railTooltip(anchors)
        }
        .onChange(of: sidebarMode) { _, mode in
            if mode == .expanded {
                clearRailHover()
            }
        }
        .onChange(of: accessibilityReduceMotion) { _, reduceMotion in
            if reduceMotion {
                resetAnimatedPresentations()
            }
        }
        .frame(minWidth: 880, minHeight: 640)
        .sheet(isPresented: permissionRecoveryPresented) {
            PermissionRecoveryGuide(model: model)
        }
        .sheet(isPresented: modeEditorPresented) {
            ModeEditorSheet(model: model)
        }
        .alert(
            model.modePendingDeletion?.title ?? "Delete Mode?",
            isPresented: modeDeletionPresented,
            presenting: model.modePendingDeletion
        ) { _ in
            Button("Delete", role: .destructive) { model.onConfirmModeDeletion?() }
            Button("Cancel", role: .cancel) { model.onCancelModeDeletion?() }
        } message: { deletion in
            Text(deletion.message)
        }
    }

    private var modeEditorPresented: Binding<Bool> {
        Binding(
            get: { model.modeEditor != nil },
            set: { isPresented in
                if !isPresented {
                    model.onCancelModeEditor?()
                }
            }
        )
    }

    private var permissionRecoveryPresented: Binding<Bool> {
        Binding(
            get: { model.permissionRecovery.isPresented },
            set: { isPresented in
                if !isPresented {
                    model.onDismissPermissionRecovery?()
                }
            }
        )
    }

    private var modeDeletionPresented: Binding<Bool> {
        Binding(
            get: { model.modePendingDeletion != nil },
            set: { _ in
                // Alert actions own dismissal so a failed delete remains available for retry.
            }
        )
    }

    private var sidebarMode: SidebarMode {
        model.sidebar.mode(forWidth: model.windowWidth)
    }

    // MARK: - titlebar

    private func titlebar(height: CGFloat) -> some View {
        HStack(spacing: 12) {
            // Clear the traffic lights drawn by the fullSizeContentView window.
            Spacer().frame(width: 70)
            Button {
                toggleSidebar()
            } label: {
                sidebarToggleGlyph
            }
            .buttonStyle(.plain)
            .keyboardShortcut("\\", modifiers: .command)
            .help("Toggle sidebar (⌘\\)")
            .disabled(model.configurationReadOnly)
            .accessibilityIdentifier("continuous-frame.sidebar-toggle")
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .padding(.leading, 10)
                .accessibilityHidden(true)
            HStack(spacing: 0) {
                Text("FoldWise")
                    .foregroundStyle(Theme.accent)
                Text(" Voice")
                    .foregroundStyle(Theme.textPrimary)
            }
            .font(Theme.ui(12.5, .semibold))
            Spacer()
        }
        .frame(height: height)
        .background(Theme.navigation)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("continuous-frame.titlebar")
    }

    /// The standard macOS "toggle sidebar" glyph: a rounded rect with an
    /// inner vertical divider, sized as a peer of the traffic lights.
    private var sidebarToggleGlyph: some View {
        RoundedRectangle(cornerRadius: 4.5)
            .strokeBorder(Theme.textTertiary, lineWidth: 1.5)
            .frame(width: 21, height: 16)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Theme.textTertiary)
                    .frame(width: 1.5)
                    .padding(.vertical, 1.5)
                    .offset(x: 6)
            }
            .contentShape(Rectangle())
    }

    // MARK: - sidebar

    private var sidebar: some View {
        ZStack(alignment: .topLeading) {
            expandedSidebar
                .frame(width: Theme.sidebarWidth)
                .opacity(sidebarMode == .expanded ? 1 : 0)
                .allowsHitTesting(sidebarMode == .expanded)
                .accessibilityHidden(sidebarMode != .expanded)
            railSidebar
                .frame(width: Theme.railWidth)
                .opacity(sidebarMode == .rail ? 1 : 0)
                .allowsHitTesting(sidebarMode == .rail)
                .accessibilityHidden(sidebarMode != .rail)
        }
        .frame(
            width: sidebarMode == .expanded ? Theme.sidebarWidth : Theme.railWidth,
            alignment: .topLeading
        )
        .background(Theme.navigation)
        .clipped()
        .id(presentationResetGeneration)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("continuous-frame.navigation")
    }

    private var expandedSidebar: some View {
        ZStack(alignment: .topLeading) {
            sidebarSelectionChrome(
                width: Theme.sidebarWidth - Theme.sidebarHorizontalInset * 2,
                showsCheckmark: true
            )
            VStack(alignment: .leading, spacing: Theme.sidebarRowSpacing) {
                ForEach(SettingsModel.Pane.allCases) { pane in
                    navRow(pane)
                }
                Spacer()
                footer
            }
            .padding(.horizontal, Theme.sidebarHorizontalInset)
            .padding(.vertical, Theme.sidebarVerticalInset)
        }
    }

    private func navRow(_ pane: SettingsModel.Pane) -> some View {
        let active = model.pane == pane
        let disabled = !model.isPaneAvailable(pane)
        return Button {
            model.pane = pane
        } label: {
            HStack(spacing: 9) {
                Image(systemName: pane.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(active ? Theme.accent : Theme.textTertiary)
                    .frame(width: 18)
                Text(pane.rawValue)
                    .font(active ? Theme.navActive : Theme.nav)
                    .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, Theme.sidebarRowContentInset)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.sidebarRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focused($focusedNavigationPane, equals: pane)
        .emberFocusRing(focusedNavigationPane == pane)
        .disabled(disabled)
        .opacity(disabled ? 0.46 : 1)
        .accessibilityLabel(pane.rawValue)
        .accessibilityValue(active ? "Selected" : "Not selected")
        .accessibilityIdentifier(
            "continuous-frame.navigation.\(pane.rawValue.lowercased())"
        )
    }

    private var railSidebar: some View {
        ZStack(alignment: .topLeading) {
            sidebarSelectionChrome(
                width: Theme.railWidth - Theme.sidebarHorizontalInset * 2,
                showsCheckmark: false
            )
            VStack(alignment: .leading, spacing: Theme.sidebarRowSpacing) {
                ForEach(SettingsModel.Pane.allCases) { pane in
                    railTile(pane)
                }
                Spacer()
                footer
            }
            .padding(.horizontal, Theme.sidebarHorizontalInset)
            .padding(.vertical, Theme.sidebarVerticalInset)
        }
    }

    private func railTile(_ pane: SettingsModel.Pane) -> some View {
        let active = model.pane == pane
        let disabled = !model.isPaneAvailable(pane)
        return Button {
            model.pane = pane
        } label: {
            Image(systemName: pane.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(active ? Theme.accent : Theme.textTertiary)
                .frame(width: Theme.sidebarRowHeight, height: Theme.sidebarRowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focused($focusedNavigationPane, equals: pane)
        .emberFocusRing(focusedNavigationPane == pane)
        .anchorPreference(key: RailTileBoundsKey.self, value: .bounds) { [pane: $0] }
        .accessibilityLabel(pane.rawValue)
        .accessibilityValue(active ? "Selected" : "Not selected")
        .accessibilityIdentifier(
            "continuous-frame.navigation.\(pane.rawValue.lowercased())"
        )
        .disabled(disabled)
        .opacity(disabled ? 0.46 : 1)
        .onHover { hovering in
            if hovering {
                model.hoveredRailPane = pane
            } else if model.hoveredRailPane == pane {
                model.hoveredRailPane = nil
            }
        }
    }

    private func sidebarSelectionChrome(
        width: CGFloat,
        showsCheckmark: Bool
    ) -> some View {
        SidebarSelectionChrome(showsCheckmark: showsCheckmark)
            .frame(width: width, height: Theme.sidebarRowHeight)
            .offset(
                x: Theme.sidebarHorizontalInset,
                y: sidebarSelectionOffset
            )
            .animation(
                Theme.sidebarSelectionAnimation(reduceMotion: accessibilityReduceMotion),
                value: model.pane
            )
    }

    private var sidebarSelectionOffset: CGFloat {
        let index = SettingsModel.Pane.allCases.firstIndex(of: model.pane) ?? 0
        return Theme.sidebarVerticalInset
            + CGFloat(index) * (Theme.sidebarRowHeight + Theme.sidebarRowSpacing)
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
                    .foregroundStyle(Theme.canvas)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Theme.textPrimary,
                        in: RoundedRectangle(cornerRadius: Theme.controlRadius)
                    )
                    .fixedSize()
                    .offset(x: rect.maxX + 10, y: rect.midY - 12)
                    .transition(.opacity.combined(with: .offset(x: -4)))
                    .allowsHitTesting(false)
            }
        }
        .animation(
            Theme.ordinaryAnimation(reduceMotion: accessibilityReduceMotion),
            value: model.hoveredRailPane
        )
        .id(presentationResetGeneration)
    }

    private func toggleSidebar() {
        guard !model.configurationReadOnly else { return }
        if sidebarMode == .rail {
            clearRailHover()
        }
        if accessibilityReduceMotion {
            model.sidebar.toggle(width: model.windowWidth)
        } else {
            withAnimation(Theme.ordinaryAnimation(reduceMotion: false)) {
                model.sidebar.toggle(width: model.windowWidth)
            }
        }
        model.onCommit?(.global)
    }

    private func clearRailHover() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            model.hoveredRailPane = nil
        }
    }

    private func updateWindowWidth(_ width: CGFloat) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            model.windowWidth = width
            model.sidebar.widthChanged(to: width)
        }
    }

    private func resetAnimatedPresentations() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            // Rebuilding these two subtrees cancels any transition that was
            // already in flight when Reduce Motion became active.
            presentationResetGeneration += 1
        }
    }

    /// Version footer pinned to the sidebar's bottom.
    private var footer: some View {
        Group {
            if sidebarMode == .expanded {
                VStack(alignment: .leading, spacing: 3) {
                    Text(footerText)
                        .font(Theme.ui(11))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 11)
                .padding(.bottom, 8)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.success)
                    .frame(width: Theme.sidebarRowHeight, height: 30)
                    .background(
                        Theme.raised,
                        in: RoundedRectangle(cornerRadius: Theme.controlRadius)
                    )
                    .help(footerText)
                    .accessibilityLabel(footerText)
                    .padding(.bottom, 8)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("continuous-frame.footer")
    }

    private var footerText: String {
        "v\(AppInfo.version)"
    }

    // MARK: - content shell

    private var content: some View {
        VStack(spacing: 0) {
            if let message = model.configurationRecoveryMessage {
                recoveryBanner(message)
                EmberHairline(axis: .horizontal)
            }
            ZStack {
                destination
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .disabled(configurationPaneIsReadOnly)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("continuous-frame.destination")
            .accessibilityValue(
                configurationPaneIsReadOnly ? "Read-only" : "Available"
            )
            .opacity(configurationPaneIsReadOnly ? 0.54 : 1)
        }
        .background(Theme.canvas)
        .overlay(alignment: .bottomTrailing) {
            if globalToastIsVisible {
                GlobalStatusToast(title: model.status, isError: model.statusIsError)
                    .padding(16)
                    .accessibilityIdentifier("continuous-frame.status")
                    .transition(GlobalStatusToastMotion.transition)
                    .id(presentationResetGeneration)
            }
        }
        .animation(
            Theme.ordinaryAnimation(reduceMotion: accessibilityReduceMotion),
            value: globalToastIsVisible
        )
    }

    @ViewBuilder
    private var destination: some View {
        switch model.pane {
        case .home:
            HomeView(model: model)
        case .modes:
            paneScroll("Modes") { modesPane }
        case .models:
            ModelsCombinedPane(model: model)
        case .history:
            paneScroll("History") { HistoryPane(model: model) }
        case .stats:
            paneScroll("Stats") { StatsPane(model: model) }
        case .settings:
            paneScroll("Settings") { settingsPane }
        }
    }

    private var configurationPaneIsReadOnly: Bool {
        !model.isPaneAvailable(model.pane)
    }

    private var globalToastIsVisible: Bool {
        !model.status.isEmpty && model.statusOwner == .global
    }

    private func recoveryBanner(_ message: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            EmberIngress(color: Theme.warning, width: Theme.noticeIngressWidth)
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Configuration recovery")
                    .font(Theme.ui(12, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(
                    "\(message) Voice to Text remains available. "
                        + "Configuration changes are disabled."
                )
                .font(Theme.ui(10.5))
                .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button("Quit") { model.onQuitRecovery?() }
                .buttonStyle(EmberButtonStyle(kind: .quiet))
                .accessibilityIdentifier("continuous-frame.recovery.quit")
            Button("Reset Configuration") { model.onResetConfiguration?() }
                .buttonStyle(EmberButtonStyle(kind: .primary))
                .accessibilityIdentifier("continuous-frame.recovery.reset")
        }
        .padding(.trailing, 14)
        .padding(.vertical, 11)
        .background(Theme.raised)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("continuous-frame.recovery")
    }

    private func paneScroll(_ title: String, @ViewBuilder body: () -> some View) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(Theme.display)
                    .tracking(Theme.displayTracking)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.bottom, 4)
                body()
            }
            .padding(.horizontal, destinationPadding)
            .padding(.top, destinationPadding)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - modes

    private var modesPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("Choose how the next Dictation session should shape your words.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button("Add Mode", systemImage: "plus") { model.onAddMode?() }
                    .buttonStyle(EmberButtonStyle(kind: .primary))
                    .accessibilityHint("Opens a new unsaved Mode draft")
            }
            HStack(alignment: .top, spacing: 14) {
                modeLibrary
                    .frame(width: 310)
                modeDetail
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var modeLibrary: some View {
        VStack(alignment: .leading, spacing: 8) {
            EmberSectionLabel("Dictation selection")
            EmberSurface {
                CommandLedgerSelectionRow(
                    item: model.modeSelection.systemItem
                ) {
                    model.onSelectMode?(model.modeSelection.systemItem.id)
                }
            }
            EmberSectionLabel("Your Modes · Cycle order")
                .padding(.top, 4)
            if model.modeSelection.editableItems.isEmpty {
                EmberSurface {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .accessibilityHidden(true)
                        Text("No Modes yet")
                            .font(Theme.ui(13, .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Voice to Text remains ready. Add a Mode when you want Polish.")
                            .font(Theme.ui(11))
                            .foregroundStyle(Theme.textSecondary)
                        Button("Add Mode") { model.onAddMode?() }
                            .buttonStyle(EmberButtonStyle(kind: .quiet))
                            .padding(.top, 4)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .contain)
            } else {
                EmberSurface {
                    VStack(spacing: 0) {
                        ForEach(
                            Array(model.modeSelection.editableItems.enumerated()),
                            id: \.element.id
                        ) { index, item in
                            if index > 0 {
                                EmberHairline(axis: .horizontal)
                                    .padding(.leading, 14)
                            }
                            CommandLedgerSelectionRow(item: item) {
                                model.onSelectMode?(item.id)
                            }
                        }
                    }
                }
            }
        }
    }

    private var modeDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            EmberSectionLabel("Mode details")
            if let mode = model.selectedEditableMode,
               let item = model.selectedEditableModeItem,
               let id = mode.id,
               let modeIndex = model.modes.firstIndex(where: { $0.id == id }) {
                let actions = ModeLibraryActionPresentation(
                    modeName: mode.name,
                    index: modeIndex,
                    modeCount: model.modes.count
                )
                EmberSurface {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            Image(systemName: item.icon)
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 32)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.name)
                                    .font(Theme.ui(20, .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(2)
                                Text(mode.transformation == .inPlace ? "Keep wording" : "Reshape")
                                    .font(Theme.body)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            HStack(spacing: 8) {
                                Button("Edit") { model.onEditMode?(id) }
                                    .buttonStyle(EmberButtonStyle(kind: .quiet))
                                    .accessibilityLabel("Edit \(mode.name)")
                                Button("Duplicate") { model.onDuplicateMode?(id) }
                                    .buttonStyle(EmberButtonStyle(kind: .quiet))
                                    .accessibilityLabel(actions.duplicateLabel)
                            }
                        }
                        EmberHairline(axis: .horizontal)
                        modeDetailField(
                            "AI model",
                            mode.llmModel ?? "Unavailable",
                            monospaced: true
                        )
                        modeDetailField("Polish instructions", mode.systemPrompt ?? "")
                        modeDetailField(
                            "Preserved vocabulary",
                            mode.vocab.isEmpty ? "None" : mode.vocab.joined(separator: " · "),
                            monospaced: true
                        )
                        if let installed = model.installed,
                           !installed.contains(where: { $0.name == mode.llmModel }) {
                            unavailableModelNotice(mode.llmModel ?? "This model")
                        }
                        Spacer(minLength: 12)
                        EmberHairline(axis: .horizontal)
                        HStack(spacing: 8) {
                            Button("Move up", systemImage: "arrow.up") {
                                model.onMoveMode?(id, .up)
                            }
                            .buttonStyle(EmberButtonStyle(kind: .quiet))
                            .disabled(!actions.canMoveUp)
                            .accessibilityLabel(actions.moveUpLabel)
                            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                            Button("Move down", systemImage: "arrow.down") {
                                model.onMoveMode?(id, .down)
                            }
                            .buttonStyle(EmberButtonStyle(kind: .quiet))
                            .disabled(!actions.canMoveDown)
                            .accessibilityLabel(actions.moveDownLabel)
                            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                            Spacer()
                            Button("Delete", role: .destructive) {
                                model.onRequestModeDeletion?(id)
                            }
                            .buttonStyle(EmberButtonStyle(kind: .destructive))
                            .accessibilityLabel(actions.deleteLabel)
                            .accessibilityHint(actions.deleteHint)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 370, alignment: .topLeading)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Details for \(mode.name)")
            } else {
                EmberSurface {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .accessibilityHidden(true)
                        Text("Choose a Mode")
                            .font(Theme.ui(13, .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(
                            "Voice to Text is selected for the next Dictation session. "
                                + "Select a Mode to review or edit its Polish instructions."
                        )
                        .font(Theme.ui(11))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityIdentifier("modes.inspector.voice-to-text-detail")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 370, alignment: .topLeading)
                }
            }
        }
    }

    private func modeDetailField(
        _ label: String,
        _ value: String,
        monospaced: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Theme.sectionLabel)
                .tracking(Theme.sectionTracking)
                .foregroundStyle(Theme.textTertiary)
                .textCase(.uppercase)
            Text(value)
                .font(monospaced ? Theme.data : Theme.body)
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    private func unavailableModelNotice(_ name: String) -> some View {
        EmberStatusNotice(
            kind: .warning,
            title: "\(name) is unavailable",
            detail: "Polish falls back to raw text.",
            actionTitle: "Open Models"
        ) {
            model.pane = .models
        }
        .padding(.vertical, 8)
        .accessibilityHint(
            "Open Models to install \(name)."
        )
    }

    // MARK: - settings (keyboard shortcuts + input + sound + appearance + updates)

    private var settingsPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            SignalLedgerSection(title: "Permissions", symbolName: "hand.raised") {
                SignalLedgerRow(
                    title: "Microphone and Accessibility",
                    detail: permissionSummary
                ) {
                    if model.permissionRecovery.snapshot.hasFullRecovery {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .font(Theme.compactData)
                            .foregroundStyle(Theme.success)
                    } else {
                        Button("Open guide…") {
                            model.onOpenPermissionRecovery?()
                        }
                        .buttonStyle(EmberButtonStyle(kind: .quiet))
                        .accessibilityIdentifier("settings.permission-recovery")
                    }
                }
            }

            SignalLedgerSection(title: "Keyboard shortcuts", symbolName: "command") {
                SignalLedgerRow(
                    title: "Push to Talk",
                    detail: "Hold to record, release when done"
                ) {
                    HStack(spacing: 8) {
                        resetButton(icon: "arrow.counterclockwise", help: "Reset to right ⌥") {
                            model.pttKey = "alt_r"
                            model.onCommit?(.shortcuts)
                        }
                        shortcutChip(key: model.pttKey, field: .ptt)
                    }
                }
                SignalLedgerDivider()
                SignalLedgerRow(
                    title: "Toggle Recording",
                    detail: "Starts and stops Dictation sessions"
                ) {
                    HStack(spacing: 8) {
                        if !model.toggleKey.isEmpty {
                            resetButton(icon: "xmark", help: "Remove shortcut") {
                                model.toggleKey = ""
                                model.onCommit?(.shortcuts)
                            }
                        }
                        shortcutChip(key: model.toggleKey, field: .toggle)
                    }
                }
                SignalLedgerDivider()
                SignalLedgerRow(
                    title: "Cycle Modes",
                    detail: "Selects the next Mode for the next Dictation session"
                ) {
                    HStack(spacing: 8) {
                        if !model.cycleKey.isEmpty {
                            resetButton(icon: "xmark", help: "Remove shortcut") {
                                model.cycleKey = ""
                                model.onCommit?(.shortcuts)
                            }
                        }
                        shortcutChip(key: model.cycleKey, field: .cycle)
                    }
                }
                Text(
                    "Click a shortcut, then press a modifier, function key, "
                        + "or single character."
                )
                .font(Theme.ui(10.5))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                if model.shortcutListenerHealth == .focusedAppOnly {
                    SignalLedgerFeedback(
                        kind: .warning,
                        title: "Global shortcuts need permission",
                        detail: "They currently work only while FoldWise is focused.",
                        actionTitle: "Open System Settings…",
                        action: model.onOpenShortcutPermissions
                    )
                    .accessibilityIdentifier("settings.shortcuts.permission")
                }
                ownedFeedback(.shortcuts, identifier: "settings.shortcuts.feedback")
            }

            SignalLedgerSection(title: "Input", symbolName: "mic") {
                inputDeviceRoster
                if let notice = inputDeviceNotice {
                    SignalLedgerFeedback(
                        kind: notice.kind,
                        title: notice.title,
                        detail: notice.detail
                    )
                    .accessibilityIdentifier("settings.input.lifecycle")
                }
                ownedFeedback(.input, identifier: "settings.input.feedback")
            }

            SignalLedgerSection(title: "Sound", symbolName: "speaker.wave.2") {
                SignalLedgerRow(
                    title: "Pause other audio",
                    detail: "Pause music and mute system audio while dictating"
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.pauseAudio },
                            set: {
                                model.pauseAudio = $0
                                model.onCommit?(.sound)
                            }
                        )
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(Theme.accent)
                    .labelsHidden()
                }
                ownedFeedback(.sound, identifier: "settings.sound.feedback")
            }

            SignalLedgerSection(
                title: "Appearance",
                symbolName: "circle.lefthalf.filled"
            ) {
                appearanceChoices
                    .padding(12)
                ownedFeedback(.appearance, identifier: "settings.appearance.feedback")
            }

            SignalLedgerSection(
                title: "Updates",
                symbolName: "arrow.triangle.2.circlepath"
            ) {
                SignalLedgerRow(title: "FoldWise Voice", detail: updateSubtitle) {
                    updateTrailing
                }
            }
        }
    }

    private var permissionSummary: String {
        if model.permissionRecovery.snapshot.hasFullRecovery {
            return "Full Dictation capability is available"
        }
        if model.permissionRecovery.snapshot.hasShortcutFallback {
            return "Text stays on the clipboard until Accessibility is restored"
        }
        return "Review the permissions needed for full Dictation capability"
    }

    @ViewBuilder
    private var appearanceChoices: some View {
        if SettingsAppearanceLayout.forContentWidth(settingsContentWidth) == .horizontal {
            HStack(spacing: 8) {
                appearanceChoiceButtons
            }
        } else {
            VStack(spacing: 8) {
                appearanceChoiceButtons
            }
        }
    }

    private var appearanceChoiceButtons: some View {
        ForEach(AppearanceTilePresentation.all) { tile in
            SignalLedgerAppearanceChoice(
                presentation: tile,
                isSelected: model.appearance == tile.preference
            ) {
                model.appearance = tile.preference
                model.onCommit?(.appearance)
            }
        }
    }

    private var settingsContentWidth: Double {
        let sidebarWidth = sidebarMode == .expanded
            ? Double(Theme.sidebarWidth)
            : Double(Theme.railWidth)
        return model.windowWidth - sidebarWidth - 1 - Double(destinationPadding * 2)
    }

    private var destinationPadding: CGFloat {
        ThemeLayoutPolicy.destinationPadding(windowWidth: model.windowWidth)
    }

    @ViewBuilder
    private var inputDeviceRoster: some View {
        inputDeviceButton(
            uid: nil,
            icon: "macbook",
            title: "System Default",
            detail: model.inputState.systemDefault.map {
                "\($0.name) — follows macOS"
            } ?? "No macOS default input is available",
            unavailable: false
        )
        ForEach(model.inputState.devices) { device in
            SignalLedgerDivider()
            inputDeviceButton(
                uid: device.uid,
                icon: "mic",
                title: device.name,
                detail: device.uid == model.inputState.effectiveDevice?.uid
                    ? "Connected — in use"
                    : "Connected",
                unavailable: false
            )
        }
        if let preferredUID = model.inputState.preferredUID,
           !model.inputState.devices.contains(where: { $0.uid == preferredUID }) {
            SignalLedgerDivider()
            inputDeviceButton(
                uid: preferredUID,
                icon: "mic.slash",
                title: model.inputState.preferredName ?? "Previously selected device",
                detail: "Not connected — Preferred",
                unavailable: true
            )
        }
    }

    private func inputDeviceButton(
        uid: String?, icon: String, title: String, detail: String, unavailable: Bool
    ) -> some View {
        let selected = model.inputState.preferredUID == uid
        return Button {
            guard !unavailable else { return }
            model.onSelectInputDevice?(uid)
        } label: {
            HStack(spacing: 0) {
                EmberIngress(color: selected ? Theme.accent : .clear)
                    .frame(height: 24)
                HStack(spacing: 10) {
                    Image(systemName: selected ? "record.circle.fill" : icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(selected ? Theme.accent : Theme.textTertiary)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(Theme.ui(12.5, .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(detail)
                            .font(Theme.ui(10))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 12)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Theme.accent : Theme.textTertiary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(EmberPlainButtonStyle(cornerRadius: Theme.surfaceRadius))
        .frame(maxWidth: .infinity)
        .disabled(unavailable)
        .opacity(unavailable ? 0.46 : 1)
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityHint(unavailable ? "\(detail). Unavailable." : detail)
    }

    private var inputDeviceNotice: (
        kind: EmberStatusKind,
        title: String,
        detail: String
    )? {
        switch model.inputState.status {
        case .ready:
            nil
        case let .fallback(preferred, effective):
            (
                .warning,
                "Preferred input is disconnected",
                "\(preferred) is unavailable. Using \(effective) until it returns."
            )
        case let .restored(device):
            (
                .success,
                "Preferred input restored",
                "\(device) is connected again and has been restored."
            )
        case let .deferred(current, next):
            (
                .warning,
                "Input changes after this Dictation session",
                "Using \(current) now; \(next) will be used next."
            )
        case let .unavailable(message):
            (.error, "No input device is available", message)
        }
    }

    private var updateSubtitle: String {
        "Version \(AppInfo.version)"
    }

    private var updateTrailing: some View {
        Button("Check for Updates") { model.onCheckUpdates?() }
            .buttonStyle(EmberButtonStyle(kind: .quiet))
            .disabled(!model.canCheckForUpdates)
            .accessibilityIdentifier("settings.updates.check")
    }

    private func resetButton(icon: String, help: String, action: @escaping () -> Void)
        -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 26, height: 26)
                .emberControlSurface()
        }
        .buttonStyle(EmberPlainButtonStyle())
        .help(help)
    }

    private func shortcutChip(key: String, field: SettingsModel.RecordingField) -> some View {
        Button {
            model.onRecord?(field)
        } label: {
            HStack(spacing: 5) {
                if model.recordingField == field {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Text(shortcutLabel(key: key, field: field))
                    .font(Theme.compactData)
            }
            .foregroundStyle(shortcutColor(key: key, field: field))
            .padding(.horizontal, 9)
            .frame(minHeight: 28)
            .emberControlSurface()
            .overlay {
                if model.recordingField == field {
                    RoundedRectangle(cornerRadius: Theme.controlRadius)
                        .strokeBorder(Theme.accent, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(EmberPlainButtonStyle())
        .accessibilityLabel("\(field.command.title) shortcut")
        .accessibilityValue(shortcutAccessibilityValue(key: key, field: field))
        .accessibilityHint(
            model.recordingField == field
                ? "Press a key to assign it. The captured key will not run a command."
                : "Activate to capture a key. Activate again to cancel."
        )
    }

    private func shortcutLabel(
        key: String,
        field: SettingsModel.RecordingField
    ) -> String {
        if model.recordingField == field {
            return "Press a key…"
        }
        if key.isEmpty {
            return "Click to set"
        }
        return keycapLabel(key)
    }

    private func shortcutColor(
        key: String,
        field: SettingsModel.RecordingField
    ) -> Color {
        if model.recordingField == field {
            return Theme.accent
        }
        return key.isEmpty ? Theme.textSecondary : Theme.textPrimary
    }

    @ViewBuilder
    private func ownedFeedback(
        _ owner: SettingsFeedbackOwner,
        identifier: String
    ) -> some View {
        if !model.status.isEmpty, model.statusOwner == owner {
            SignalLedgerFeedback(
                kind: model.statusIsError ? .error : .success,
                title: model.status
            )
            .accessibilityIdentifier(identifier)
        }
    }

    private func shortcutAccessibilityValue(
        key: String,
        field: SettingsModel.RecordingField
    ) -> String {
        if model.recordingField == field {
            return "Capturing"
        }
        if key.isEmpty {
            return "Not assigned"
        }
        return "Assigned to \(keycapLabel(key))"
    }
}

enum GlobalStatusToastMotion {
    static let insertionOffset: CGFloat = 20
    static let removalOffset: CGFloat = 12
    static let insertionScale = 0.96
    static let removalScale = 0.98

    static var transition: AnyTransition {
        .asymmetric(
            insertion: .offset(x: 0, y: insertionOffset)
                .combined(with: .scale(scale: insertionScale, anchor: .bottomTrailing))
                .combined(with: .opacity),
            removal: .offset(x: 0, y: removalOffset)
                .combined(with: .scale(scale: removalScale, anchor: .bottomTrailing))
                .combined(with: .opacity)
        )
    }
}

struct GlobalStatusToast: View {
    let title: String
    let isError: Bool
    var increaseContrastOverride: Bool?

    var body: some View {
        EmberSurface(level: .raised, increaseContrast: increaseContrastOverride) {
            HStack(spacing: 8) {
                Image(systemName: isError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                    .foregroundStyle(isError ? Theme.error : Theme.success)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Theme.ui(12, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
            }
            .padding(.leading, 14)
            .padding(.trailing, 16)
            .frame(minWidth: 112, maxWidth: 320, minHeight: 40, alignment: .leading)
            .fixedSize(horizontal: true, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isError ? "Error" : "Success"): \(title)")
    }
}

private struct SignalLedgerAppearanceChoice: View {
    let presentation: AppearanceTilePresentation
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: presentation.symbolName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.title)
                        .font(Theme.ui(12.5, .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(presentation.detail)
                        .font(Theme.ui(9.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
            .background(
                isSelected ? Theme.raised : Theme.canvas,
                in: RoundedRectangle(cornerRadius: Theme.controlRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .strokeBorder(
                        isSelected
                            ? Theme.accent
                            : Theme.essentialBorderColor(
                                increaseContrast: colorSchemeContrast == .increased
                            ),
                        lineWidth: Theme.essentialBorderWidth(
                            increaseContrast: colorSchemeContrast == .increased
                        )
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(EmberPlainButtonStyle())
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.title)
        .accessibilityHint(presentation.detail)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityIdentifier(
            "settings.appearance.\(presentation.preference.rawValue.lowercased())"
        )
    }
}

struct CommandLedgerSelectionRow: View {
    let item: ModeSelectionItem
    let onSelect: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 0) {
                EmberIngress(color: item.isSelected ? Theme.accent : .clear)
                HStack(spacing: 10) {
                    Image(systemName: item.icon)
                        .font(.system(size: 15, weight: item.isSelected ? .semibold : .medium))
                        .foregroundStyle(
                            item.isSelected ? Theme.accent : Theme.textTertiary
                        )
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(Theme.ui(12, item.isSelected ? .semibold : .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(item.summary)
                            .font(Theme.compactData)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 12)
                    Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(
                            item.isSelected ? Theme.accent : Theme.textTertiary
                        )
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(EmberPlainButtonStyle(cornerRadius: Theme.surfaceRadius))
        .onHover { isHovering = $0 }
        .animation(
            Theme.ordinaryAnimation(reduceMotion: accessibilityReduceMotion),
            value: isHovering
        )
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityValue(item.accessibilityValue)
        .accessibilityHint(item.accessibilityHint)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var rowBackground: Color {
        if item.isSelected {
            return Theme.raised
        }
        return isHovering ? Theme.hover : Theme.surface
    }

    private var accessibilityIdentifier: String {
        switch item.id {
        case .voiceToText:
            "modes.selection.voice-to-text"
        case let .mode(id):
            "modes.selection.\(id)"
        }
    }
}

func keycapLabel(_ name: String) -> String {
    if name.count == 1 {
        return name.uppercased()
    }
    return KeyMap.pretty(name) // "right ⌥", "f19", "esc", …
}
