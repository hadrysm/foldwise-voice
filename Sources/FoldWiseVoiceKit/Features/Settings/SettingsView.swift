import AppKit
import SwiftUI

@MainActor
final class PaneFirstMeaningfulFrameView: NSView {
    var pane: SettingsModel.Pane
    var performance: PaneNavigationPerformance
    var onDraw: @MainActor () -> Void

    init(
        pane: SettingsModel.Pane,
        performance: PaneNavigationPerformance,
        onDraw: @escaping @MainActor () -> Void = {}
    ) {
        self.pane = pane
        self.performance = performance
        self.onDraw = onDraw
        super.init(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let pane = pane
        let performance = performance
        let onDraw = onDraw
        DispatchQueue.main.async {
            performance.firstMeaningfulFrame(for: pane)
            onDraw()
        }
    }
}

private struct PaneFirstMeaningfulFrameMarker: NSViewRepresentable {
    let pane: SettingsModel.Pane
    let performance: PaneNavigationPerformance
    let onDraw: @MainActor () -> Void

    func makeNSView(context: Context) -> PaneFirstMeaningfulFrameView {
        PaneFirstMeaningfulFrameView(
            pane: pane,
            performance: performance,
            onDraw: onDraw
        )
    }

    func updateNSView(_ view: PaneFirstMeaningfulFrameView, context: Context) {
        view.pane = pane
        view.performance = performance
        view.onDraw = onDraw
        view.needsDisplay = true
    }
}

extension View {
    func paneFirstMeaningfulFrame(
        _ pane: SettingsModel.Pane,
        performance: PaneNavigationPerformance,
        isReady: Bool = true,
        onDraw: @escaping @MainActor () -> Void = {}
    ) -> some View {
        overlay(alignment: .topLeading) {
            if isReady {
                PaneFirstMeaningfulFrameMarker(
                    pane: pane,
                    performance: performance,
                    onDraw: onDraw
                )
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

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

private struct SettingsContentObservationScope<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
    }
}

private struct SettingsDestinationObservationScope<Input, Content: View>: View {
    let input: Input
    @ViewBuilder let content: (Input) -> Content

    var body: some View {
        content(input)
    }
}

private struct PaneScrollLayout: Layout {
    func makeCache(subviews _: Subviews) -> ModeVerticalLayoutCache {
        ModeVerticalLayoutCache()
    }

    func updateCache(
        _ cache: inout ModeVerticalLayoutCache,
        subviews _: Subviews
    ) {
        cache = ModeVerticalLayoutCache()
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ModeVerticalLayoutCache
    ) -> CGSize {
        ModeVerticalLayout.size(
            proposal: proposal,
            subviews: subviews,
            spacing: 16,
            cache: &cache
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache: inout ModeVerticalLayoutCache
    ) {
        ModeVerticalLayout.place(
            in: bounds,
            subviews: subviews,
            spacing: 16,
            cache: &cache
        )
    }
}

private struct RenderBoxPrewarm: View {
    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            context.fill(
                Path(roundedRect: bounds, cornerRadius: 0.5),
                with: .color(Theme.canvas)
            )
            context.draw(
                Text("A")
                    .font(Theme.ui(1))
                    .foregroundStyle(Theme.canvas),
                at: CGPoint(x: bounds.midX, y: bounds.midY)
            )
            if let symbol = context.resolveSymbol(id: "prewarm-symbol") {
                context.draw(
                    symbol,
                    at: CGPoint(x: bounds.midX, y: bounds.midY)
                )
            }
        } symbols: {
            Image(systemName: "checkmark")
                .font(.system(size: 1))
                .foregroundStyle(Theme.canvas)
                .tag("prewarm-symbol")
        }
        .frame(width: 1, height: 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct SettingsView: View {
    var model: SettingsModel
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
                    SettingsContentObservationScope {
                        sidebar
                    }
                    EmberHairline(axis: .vertical)
                    SettingsContentObservationScope {
                        content
                    }
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
        .background(alignment: .topLeading) {
            RenderBoxPrewarm()
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
        Group {
            if sidebarMode == .expanded {
                expandedSidebar
                    .frame(width: Theme.sidebarWidth)
            } else {
                railSidebar
                    .frame(width: Theme.railWidth)
            }
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
            model.selectPane(pane)
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
            model.selectPane(pane)
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
        Group {
            if let message = model.configurationRecoveryMessage {
                VStack(spacing: 0) {
                    recoveryBanner(message)
                    EmberHairline(axis: .horizontal)
                    destinationShell
                }
            } else {
                destinationShell
            }
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

    private var destinationShell: some View {
        destination
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .disabled(configurationPaneIsReadOnly)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("continuous-frame.destination")
            .accessibilityValue(
                configurationPaneIsReadOnly ? "Read-only" : "Available"
            )
            .opacity(configurationPaneIsReadOnly ? 0.54 : 1)
    }

    @ViewBuilder
    private var destination: some View {
        switch model.pane {
        case .home:
            HomeView(interface: model.homePaneInterface)
        case .modes:
            paneScroll("Modes") {
                SettingsDestinationObservationScope(input: model.modesPaneInterface) {
                    modesPane($0)
                }
            }
            .paneFirstMeaningfulFrame(.modes, performance: model.panePerformance)
        case .models:
            ModelsCombinedPane(interface: model.modelsPaneInterface)
                .paneFirstMeaningfulFrame(.models, performance: model.panePerformance)
        case .history:
            paneScroll("History") { HistoryPane(interface: model.historyPaneInterface) }
        case .stats:
            paneScroll("Stats") { StatsPane(interface: model.statsPaneInterface) }
        case .settings:
            paneScroll("Settings") {
                SettingsDestinationObservationScope(input: model.preferencesPaneInterface) {
                    settingsPane($0)
                }
            }
            .paneFirstMeaningfulFrame(.settings, performance: model.panePerformance)
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
            PaneScrollLayout {
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

    private func modesPane(_ modesModel: ModesPaneInterface) -> some View {
        ModesPaneLayout {
            Text("Choose how the next Dictation session should shape your words.")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
            Button("Add Mode", systemImage: "plus") { modesModel.addMode() }
                .buttonStyle(EmberButtonStyle(kind: .primary))
                .accessibilityHint("Opens a new unsaved Mode draft")
            modeLibrary(modesModel)
            modeDetail(modesModel)
        }
    }

    private func modeLibrary(_ modesModel: ModesPaneInterface) -> some View {
        ModeLibraryLayout {
            EmberSectionLabel("Dictation selection")
            EmberSurface {
                CommandLedgerSelectionRow(
                    item: modesModel.modeSelection.systemItem
                ) {
                    modesModel.selectMode(modesModel.modeSelection.systemItem.id)
                }
            }
            EmberSectionLabel("Your Modes · Cycle order")
                .padding(.top, 4)
            if modesModel.modeSelection.editableItems.isEmpty {
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
                        Button("Add Mode") { modesModel.addMode() }
                            .buttonStyle(EmberButtonStyle(kind: .quiet))
                            .padding(.top, 4)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .contain)
            } else {
                EmberSurface {
                    ModeLibraryRowsLayout {
                        ForEach(
                            Array(modesModel.modeSelection.editableItems.enumerated()),
                            id: \.element.id
                        ) { index, item in
                            if index > 0 {
                                EmberHairline(axis: .horizontal)
                                    .padding(.leading, 14)
                            }
                            CommandLedgerSelectionRow(item: item) {
                                modesModel.selectMode(item.id)
                            }
                        }
                    }
                }
            }
        }
    }

    private func modeDetail(_ modesModel: ModesPaneInterface) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            EmberSectionLabel("Mode details")
            if let mode = modesModel.selectedEditableMode,
               let item = modesModel.selectedEditableModeItem,
               let id = mode.id,
               let modeIndex = modesModel.modes.firstIndex(where: { $0.id == id }) {
                let actions = ModeLibraryActionPresentation(
                    modeName: mode.name,
                    index: modeIndex,
                    modeCount: modesModel.modes.count
                )
                EmberSurface {
                    ModeDetailContentLayout {
                        Image(systemName: item.icon)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .accessibilityHidden(true)
                        Text(mode.name)
                            .font(Theme.ui(20, .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                        Text(mode.transformation == .inPlace ? "Keep wording" : "Reshape")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textSecondary)
                        ModeDetailHeaderActions(
                            editLabel: "Edit \(mode.name)",
                            duplicateLabel: actions.duplicateLabel,
                            onEdit: { modesModel.editMode(id) },
                            onDuplicate: { modesModel.duplicateMode(id) }
                        )
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
                        ZStack(alignment: .topLeading) {
                            if let installed = modesModel.installed,
                               !installed.contains(where: { $0.name == mode.llmModel }) {
                                unavailableModelNotice(
                                    mode.llmModel ?? "This model",
                                    interface: modesModel
                                )
                            }
                        }
                        EmberHairline(axis: .horizontal)
                        ModeDetailActions(presentation: actions) { action in
                            switch action {
                            case .moveUp:
                                modesModel.moveMode(id, .up)
                            case .moveDown:
                                modesModel.moveMode(id, .down)
                            case .delete:
                                modesModel.requestModeDeletion(id)
                            }
                        }
                        .frame(height: 28)
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
        ModeDetailFieldLayout {
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

    private func unavailableModelNotice(
        _ name: String,
        interface modesModel: ModesPaneInterface
    ) -> some View {
        EmberStatusNotice(
            kind: .warning,
            title: "\(name) is unavailable",
            detail: "Polish falls back to raw text.",
            actionTitle: "Open Models"
        ) {
            modesModel.selectPane(.models)
        }
        .padding(.vertical, 8)
        .accessibilityHint(
            "Open Models to install \(name)."
        )
    }

    // MARK: - settings (keyboard shortcuts + input + sound + appearance + updates)

    private func settingsPane(_ preferencesModel: PreferencesPaneInterface) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SignalLedgerSection(title: "Permissions", symbolName: "hand.raised") {
                SignalLedgerRow(
                    title: "Microphone and Accessibility",
                    detail: permissionSummary(preferencesModel)
                ) {
                    if preferencesModel.permissionRecovery.snapshot.hasFullRecovery {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .font(Theme.compactData)
                            .foregroundStyle(Theme.success)
                    } else {
                        Button("Open guide…") {
                            preferencesModel.openPermissionRecovery()
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
                            preferencesModel.pttKey = "alt_r"
                            preferencesModel.commit(.shortcuts)
                        }
                        shortcutChip(
                            key: preferencesModel.pttKey,
                            field: .ptt,
                            interface: preferencesModel
                        )
                    }
                }
                SignalLedgerDivider()
                SignalLedgerRow(
                    title: "Toggle Recording",
                    detail: "Starts and stops Dictation sessions"
                ) {
                    HStack(spacing: 8) {
                        if !preferencesModel.toggleKey.isEmpty {
                            resetButton(icon: "xmark", help: "Remove shortcut") {
                                preferencesModel.toggleKey = ""
                                preferencesModel.commit(.shortcuts)
                            }
                        }
                        shortcutChip(
                            key: preferencesModel.toggleKey,
                            field: .toggle,
                            interface: preferencesModel
                        )
                    }
                }
                SignalLedgerDivider()
                SignalLedgerRow(
                    title: "Cycle Modes",
                    detail: "Selects the next Mode for the next Dictation session"
                ) {
                    HStack(spacing: 8) {
                        if !preferencesModel.cycleKey.isEmpty {
                            resetButton(icon: "xmark", help: "Remove shortcut") {
                                preferencesModel.cycleKey = ""
                                preferencesModel.commit(.shortcuts)
                            }
                        }
                        shortcutChip(
                            key: preferencesModel.cycleKey,
                            field: .cycle,
                            interface: preferencesModel
                        )
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
                if preferencesModel.shortcutListenerHealth == .focusedAppOnly {
                    SignalLedgerFeedback(
                        kind: .warning,
                        title: "Global shortcuts need permission",
                        detail: "They currently work only while FoldWise is focused.",
                        actionTitle: "Open System Settings…",
                        action: preferencesModel.openShortcutPermissions
                    )
                    .accessibilityIdentifier("settings.shortcuts.permission")
                }
                ownedFeedback(
                    .shortcuts,
                    identifier: "settings.shortcuts.feedback",
                    interface: preferencesModel
                )
            }

            SignalLedgerSection(title: "Input", symbolName: "mic") {
                inputDeviceRoster(preferencesModel)
                if let notice = inputDeviceNotice(preferencesModel) {
                    SignalLedgerFeedback(
                        kind: notice.kind,
                        title: notice.title,
                        detail: notice.detail
                    )
                    .accessibilityIdentifier("settings.input.lifecycle")
                }
                ownedFeedback(
                    .input,
                    identifier: "settings.input.feedback",
                    interface: preferencesModel
                )
            }

            SignalLedgerSection(title: "Sound", symbolName: "speaker.wave.2") {
                SignalLedgerRow(
                    title: "Pause other audio",
                    detail: "Pause music and mute system audio while dictating"
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { preferencesModel.pauseAudio },
                            set: {
                                preferencesModel.pauseAudio = $0
                                preferencesModel.commit(.sound)
                            }
                        )
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(Theme.accent)
                    .labelsHidden()
                }
                ownedFeedback(
                    .sound,
                    identifier: "settings.sound.feedback",
                    interface: preferencesModel
                )
            }

            SignalLedgerSection(
                title: "Appearance",
                symbolName: "circle.lefthalf.filled"
            ) {
                appearanceChoices(preferencesModel)
                    .padding(12)
                ownedFeedback(
                    .appearance,
                    identifier: "settings.appearance.feedback",
                    interface: preferencesModel
                )
            }

            SignalLedgerSection(
                title: "Updates",
                symbolName: "arrow.triangle.2.circlepath"
            ) {
                SignalLedgerRow(title: "FoldWise Voice", detail: updateSubtitle) {
                    updateTrailing(preferencesModel)
                }
            }
        }
    }

    private func permissionSummary(_ preferencesModel: PreferencesPaneInterface) -> String {
        if preferencesModel.permissionRecovery.snapshot.hasFullRecovery {
            return "Full Dictation capability is available"
        }
        if preferencesModel.permissionRecovery.snapshot.hasShortcutFallback {
            return "Text stays on the clipboard until Accessibility is restored"
        }
        return "Review the permissions needed for full Dictation capability"
    }

    @ViewBuilder
    private func appearanceChoices(
        _ preferencesModel: PreferencesPaneInterface
    ) -> some View {
        if SettingsAppearanceLayout.forContentWidth(
            settingsContentWidth(preferencesModel)
        ) == .horizontal {
            HStack(spacing: 8) {
                appearanceChoiceButtons(preferencesModel)
            }
        } else {
            VStack(spacing: 8) {
                appearanceChoiceButtons(preferencesModel)
            }
        }
    }

    private func appearanceChoiceButtons(
        _ preferencesModel: PreferencesPaneInterface
    ) -> some View {
        ForEach(AppearanceTilePresentation.all) { tile in
            SignalLedgerAppearanceChoice(
                presentation: tile,
                isSelected: preferencesModel.appearance == tile.preference
            ) {
                preferencesModel.appearance = tile.preference
                preferencesModel.commit(.appearance)
            }
        }
    }

    private func settingsContentWidth(
        _ preferencesModel: PreferencesPaneInterface
    ) -> Double {
        let sidebarWidth = preferencesModel.sidebarMode == .expanded
            ? Double(Theme.sidebarWidth)
            : Double(Theme.railWidth)
        let padding = ThemeLayoutPolicy.destinationPadding(
            windowWidth: preferencesModel.windowWidth
        )
        return preferencesModel.windowWidth - sidebarWidth - 1 - Double(padding * 2)
    }

    private var destinationPadding: CGFloat {
        ThemeLayoutPolicy.destinationPadding(windowWidth: model.windowWidth)
    }

    @ViewBuilder
    private func inputDeviceRoster(
        _ preferencesModel: PreferencesPaneInterface
    ) -> some View {
        inputDeviceButton(
            uid: nil,
            icon: "macbook",
            title: "System Default",
            detail: preferencesModel.inputState.systemDefault.map {
                "\($0.name) — follows macOS"
            } ?? "No macOS default input is available",
            unavailable: false,
            interface: preferencesModel
        )
        ForEach(preferencesModel.inputState.devices) { device in
            SignalLedgerDivider()
            inputDeviceButton(
                uid: device.uid,
                icon: "mic",
                title: device.name,
                detail: device.uid == preferencesModel.inputState.effectiveDevice?.uid
                    ? "Connected — in use"
                    : "Connected",
                unavailable: false,
                interface: preferencesModel
            )
        }
        if let preferredUID = preferencesModel.inputState.preferredUID,
           !preferencesModel.inputState.devices.contains(where: { $0.uid == preferredUID }) {
            SignalLedgerDivider()
            inputDeviceButton(
                uid: preferredUID,
                icon: "mic.slash",
                title: preferencesModel.inputState.preferredName ?? "Previously selected device",
                detail: "Not connected — Preferred",
                unavailable: true,
                interface: preferencesModel
            )
        }
    }

    private func inputDeviceButton(
        uid: String?,
        icon: String,
        title: String,
        detail: String,
        unavailable: Bool,
        interface preferencesModel: PreferencesPaneInterface
    ) -> some View {
        let selected = preferencesModel.inputState.preferredUID == uid
        return Button {
            guard !unavailable else { return }
            preferencesModel.selectInputDevice(uid)
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

    private func inputDeviceNotice(
        _ preferencesModel: PreferencesPaneInterface
    ) -> (
        kind: EmberStatusKind,
        title: String,
        detail: String
    )? {
        switch preferencesModel.inputState.status {
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

    private func updateTrailing(_ preferencesModel: PreferencesPaneInterface) -> some View {
        Button("Check for Updates") { preferencesModel.checkForUpdates() }
            .buttonStyle(EmberButtonStyle(kind: .quiet))
            .disabled(!preferencesModel.canCheckForUpdates)
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

    private func shortcutChip(
        key: String,
        field: SettingsModel.RecordingField,
        interface preferencesModel: PreferencesPaneInterface
    ) -> some View {
        Button {
            preferencesModel.record(field)
        } label: {
            HStack(spacing: 5) {
                if preferencesModel.recordingField == field {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Text(shortcutLabel(key: key, field: field, interface: preferencesModel))
                    .font(Theme.compactData)
            }
            .foregroundStyle(
                shortcutColor(key: key, field: field, interface: preferencesModel)
            )
            .padding(.horizontal, 9)
            .frame(minHeight: 28)
            .emberControlSurface()
            .overlay {
                if preferencesModel.recordingField == field {
                    RoundedRectangle(cornerRadius: Theme.controlRadius)
                        .strokeBorder(Theme.accent, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(EmberPlainButtonStyle())
        .accessibilityLabel("\(field.command.title) shortcut")
        .accessibilityValue(
            shortcutAccessibilityValue(
                key: key,
                field: field,
                interface: preferencesModel
            )
        )
        .accessibilityHint(
            preferencesModel.recordingField == field
                ? "Press a key to assign it. The captured key will not run a command."
                : "Activate to capture a key. Activate again to cancel."
        )
    }

    private func shortcutLabel(
        key: String,
        field: SettingsModel.RecordingField,
        interface preferencesModel: PreferencesPaneInterface
    ) -> String {
        if preferencesModel.recordingField == field {
            return "Press a key…"
        }
        if key.isEmpty {
            return "Click to set"
        }
        return keycapLabel(key)
    }

    private func shortcutColor(
        key: String,
        field: SettingsModel.RecordingField,
        interface preferencesModel: PreferencesPaneInterface
    ) -> Color {
        if preferencesModel.recordingField == field {
            return Theme.accent
        }
        return key.isEmpty ? Theme.textSecondary : Theme.textPrimary
    }

    @ViewBuilder
    private func ownedFeedback(
        _ owner: SettingsFeedbackOwner,
        identifier: String,
        interface preferencesModel: PreferencesPaneInterface
    ) -> some View {
        if !preferencesModel.status.isEmpty, preferencesModel.statusOwner == owner {
            SignalLedgerFeedback(
                kind: preferencesModel.statusIsError ? .error : .success,
                title: preferencesModel.status
            )
            .accessibilityIdentifier(identifier)
        }
    }

    private func shortcutAccessibilityValue(
        key: String,
        field: SettingsModel.RecordingField,
        interface preferencesModel: PreferencesPaneInterface
    ) -> String {
        if preferencesModel.recordingField == field {
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
            Canvas { context, size in
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .color(rowBackground)
                )
                if item.isSelected {
                    context.fill(
                        Path(CGRect(
                            x: 0,
                            y: 0,
                            width: Theme.selectionIngressWidth,
                            height: size.height
                        )),
                        with: .color(Theme.accent)
                    )
                }
                if let icon = context.resolveSymbol(id: "mode-icon") {
                    context.draw(
                        icon,
                        at: CGPoint(x: 26, y: size.height / 2)
                    )
                }
                context.draw(
                    Text(item.name)
                        .font(Theme.ui(12, item.isSelected ? .semibold : .medium))
                        .foregroundStyle(Theme.textPrimary),
                    at: CGPoint(x: 46, y: 18),
                    anchor: .leading
                )
                context.draw(
                    Text(item.summary)
                        .font(Theme.compactData)
                        .foregroundStyle(Theme.textSecondary),
                    at: CGPoint(x: 46, y: 35),
                    anchor: .leading
                )
                if let selection = context.resolveSymbol(id: "selection") {
                    context.draw(
                        selection,
                        at: CGPoint(x: size.width - 24, y: size.height / 2)
                    )
                }
            } symbols: {
                Image(systemName: item.icon)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(
                        size: 15,
                        weight: item.isSelected ? .semibold : .medium
                    ))
                    .foregroundStyle(
                        item.isSelected ? Theme.accent : Theme.textTertiary
                    )
                    .tag("mode-icon")
                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        item.isSelected ? Theme.accent : Theme.textTertiary
                    )
                    .tag("selection")
            }
            .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
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

private struct ModeVerticalLayoutCache {
    var width: CGFloat?
    var sizes: [CGSize] = []
}

private enum ModeVerticalLayout {
    static func size(
        proposal: ProposedViewSize,
        subviews: LayoutSubviews,
        spacing: CGFloat,
        cache: inout ModeVerticalLayoutCache
    ) -> CGSize {
        let width = proposal.width
            ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max()
            ?? 0
        let sizes = subviews.map {
            $0.sizeThatFits(ProposedViewSize(width: width, height: nil))
        }
        cache.width = width
        cache.sizes = sizes
        return CGSize(
            width: width,
            height: sizes.reduce(0) { $0 + $1.height }
                + spacing * CGFloat(max(0, sizes.count - 1))
        )
    }

    static func place(
        in bounds: CGRect,
        subviews: LayoutSubviews,
        spacing: CGFloat,
        cache: inout ModeVerticalLayoutCache
    ) {
        let sizes: [CGSize]
        if cache.width == bounds.width, cache.sizes.count == subviews.count {
            sizes = cache.sizes
        } else {
            sizes = subviews.map {
                $0.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            }
            cache.width = bounds.width
            cache.sizes = sizes
        }
        var y = bounds.minY
        for (subview, size) in zip(subviews, sizes) {
            subview.place(
                at: CGPoint(x: bounds.minX, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: size.height)
            )
            y += size.height + spacing
        }
    }
}

private struct ModeLibraryLayout: Layout {
    func makeCache(subviews _: Subviews) -> ModeVerticalLayoutCache {
        ModeVerticalLayoutCache()
    }

    func updateCache(
        _ cache: inout ModeVerticalLayoutCache,
        subviews _: Subviews
    ) {
        cache = ModeVerticalLayoutCache()
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ModeVerticalLayoutCache
    ) -> CGSize {
        ModeVerticalLayout.size(
            proposal: proposal,
            subviews: subviews,
            spacing: 8,
            cache: &cache
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache: inout ModeVerticalLayoutCache
    ) {
        ModeVerticalLayout.place(
            in: bounds,
            subviews: subviews,
            spacing: 8,
            cache: &cache
        )
    }
}

private struct ModeLibraryRowsLayout: Layout {
    func makeCache(subviews _: Subviews) -> ModeVerticalLayoutCache {
        ModeVerticalLayoutCache()
    }

    func updateCache(
        _ cache: inout ModeVerticalLayoutCache,
        subviews _: Subviews
    ) {
        cache = ModeVerticalLayoutCache()
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ModeVerticalLayoutCache
    ) -> CGSize {
        ModeVerticalLayout.size(
            proposal: proposal,
            subviews: subviews,
            spacing: 0,
            cache: &cache
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache: inout ModeVerticalLayoutCache
    ) {
        ModeVerticalLayout.place(
            in: bounds,
            subviews: subviews,
            spacing: 0,
            cache: &cache
        )
    }
}

private struct ModeDetailFieldLayout: Layout {
    func makeCache(subviews _: Subviews) -> ModeVerticalLayoutCache {
        ModeVerticalLayoutCache()
    }

    func updateCache(
        _ cache: inout ModeVerticalLayoutCache,
        subviews _: Subviews
    ) {
        cache = ModeVerticalLayoutCache()
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ModeVerticalLayoutCache
    ) -> CGSize {
        ModeVerticalLayout.size(
            proposal: proposal,
            subviews: subviews,
            spacing: 3,
            cache: &cache
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache: inout ModeVerticalLayoutCache
    ) {
        ModeVerticalLayout.place(
            in: bounds,
            subviews: subviews,
            spacing: 3,
            cache: &cache
        )
    }
}

private struct ModesPaneLayout: Layout {
    struct Cache {
        var width: CGFloat?
        var addButton = CGSize.zero
        var description = CGSize.zero
    }

    private let headerSpacing: CGFloat = 16
    private let columnSpacing: CGFloat = 14
    private let libraryWidth: CGFloat = 310

    func makeCache(subviews _: Subviews) -> Cache {
        Cache()
    }

    func updateCache(_ cache: inout Cache, subviews _: Subviews) {
        cache = Cache()
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        let width = proposal.width ?? 880
        guard subviews.count == 4 else {
            return proposal.replacingUnspecifiedDimensions()
        }
        let addButton = subviews[1].sizeThatFits(.unspecified)
        let description = subviews[0].sizeThatFits(ProposedViewSize(
            width: max(0, width - addButton.width - headerSpacing),
            height: nil
        ))
        cache.width = width
        cache.addButton = addButton
        cache.description = description
        let headerHeight = max(description.height, addButton.height)
        let library = subviews[2].sizeThatFits(ProposedViewSize(
            width: libraryWidth,
            height: nil
        ))
        let detail = subviews[3].sizeThatFits(ProposedViewSize(
            width: max(0, width - libraryWidth - columnSpacing),
            height: nil
        ))
        return CGSize(
            width: width,
            height: headerHeight + headerSpacing + max(library.height, detail.height)
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        guard subviews.count == 4 else { return }
        let addButton = cache.width == bounds.width
            ? cache.addButton
            : subviews[1].sizeThatFits(.unspecified)
        let descriptionWidth = max(0, bounds.width - addButton.width - headerSpacing)
        let description = cache.width == bounds.width
            ? cache.description
            : subviews[0].sizeThatFits(ProposedViewSize(
                width: descriptionWidth,
                height: nil
            ))
        let headerHeight = max(description.height, addButton.height)
        subviews[0].place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: descriptionWidth, height: headerHeight)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.maxX, y: bounds.minY),
            anchor: .topTrailing,
            proposal: ProposedViewSize(addButton)
        )
        let contentY = bounds.minY + headerHeight + headerSpacing
        subviews[2].place(
            at: CGPoint(x: bounds.minX, y: contentY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: libraryWidth, height: nil)
        )
        subviews[3].place(
            at: CGPoint(x: bounds.minX + libraryWidth + columnSpacing, y: contentY),
            anchor: .topLeading,
            proposal: ProposedViewSize(
                width: max(0, bounds.width - libraryWidth - columnSpacing),
                height: nil
            )
        )
    }
}

private struct ModeDetailContentLayout: Layout {
    struct Cache {
        var width: CGFloat?
        var fieldSizes: [CGSize] = []
        var noticeSize = CGSize.zero
    }

    private let minimumHeight: CGFloat = 338

    func makeCache(subviews _: Subviews) -> Cache {
        Cache()
    }

    func updateCache(_ cache: inout Cache, subviews _: Subviews) {
        cache = Cache()
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        let width = proposal.width ?? 480
        guard subviews.count == 11 else {
            return proposal.replacingUnspecifiedDimensions()
        }
        let fieldSizes = (5 ... 7).map {
            subviews[$0].sizeThatFits(ProposedViewSize(
                width: width,
                height: nil
            ))
        }
        let noticeSize = subviews[8].sizeThatFits(ProposedViewSize(
            width: width,
            height: nil
        ))
        cache.width = width
        cache.fieldSizes = fieldSizes
        cache.noticeSize = noticeSize
        let fieldHeights = fieldSizes.map(\.height)
        let noticeHeight = noticeSize.height
        let contentHeight = 68
            + fieldHeights.reduce(0, +)
            + CGFloat(fieldHeights.count - 1) * 14
            + (noticeHeight > 0 ? noticeHeight + 10 : 0)
            + 56
        return CGSize(
            width: width,
            height: max(minimumHeight, contentHeight)
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        guard subviews.count == 11 else { return }
        let headerActionsWidth: CGFloat = 144
        let titleX = bounds.minX + 42
        let titleWidth = max(0, bounds.width - 42 - headerActionsWidth - 10)
        subviews[0].place(
            at: CGPoint(x: bounds.minX + 16, y: bounds.minY + 16),
            anchor: .center,
            proposal: ProposedViewSize(width: 32, height: 32)
        )
        subviews[1].place(
            at: CGPoint(x: titleX, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: titleWidth, height: nil)
        )
        subviews[2].place(
            at: CGPoint(x: titleX, y: bounds.minY + 29),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: titleWidth, height: nil)
        )
        subviews[3].place(
            at: CGPoint(x: bounds.maxX, y: bounds.minY),
            anchor: .topTrailing,
            proposal: ProposedViewSize(width: headerActionsWidth, height: 28)
        )
        subviews[4].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + 52),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: nil)
        )
        var fieldY = bounds.minY + 68
        let fieldSizes = cache.width == bounds.width && cache.fieldSizes.count == 3
            ? cache.fieldSizes
            : (5 ... 7).map {
                subviews[$0].sizeThatFits(ProposedViewSize(
                    width: bounds.width,
                    height: nil
                ))
            }
        for (index, size) in zip(5 ... 7, fieldSizes) {
            subviews[index].place(
                at: CGPoint(x: bounds.minX, y: fieldY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: size.height)
            )
            fieldY += size.height + 14
        }
        let notice = cache.width == bounds.width
            ? cache.noticeSize
            : subviews[8].sizeThatFits(ProposedViewSize(
                width: bounds.width,
                height: nil
            ))
        if notice.height > 0 {
            subviews[8].place(
                at: CGPoint(x: bounds.minX, y: fieldY - 4),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: notice.height)
            )
        }
        subviews[9].place(
            at: CGPoint(x: bounds.minX, y: bounds.maxY - 42),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: nil)
        )
        subviews[10].place(
            at: CGPoint(x: bounds.minX, y: bounds.maxY - 28),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: 28)
        )
    }
}

enum ModeDetailControlID: Hashable {
    case edit
    case duplicate
    case moveUp
    case moveDown
    case delete
}

struct ModeDetailControlSurface {
    let frame: CGRect
    let trailingInset: CGFloat?
    let isHovered: Bool
    let isFocused: Bool
    let isEnabled: Bool

    init(
        frame: CGRect,
        isHovered: Bool,
        isFocused: Bool,
        isEnabled: Bool
    ) {
        self.frame = frame
        trailingInset = nil
        self.isHovered = isHovered
        self.isFocused = isFocused
        self.isEnabled = isEnabled
    }

    init(
        trailingInset: CGFloat,
        width: CGFloat,
        height: CGFloat,
        isHovered: Bool,
        isFocused: Bool,
        isEnabled: Bool
    ) {
        frame = CGRect(x: 0, y: 0, width: width, height: height)
        self.trailingInset = trailingInset
        self.isHovered = isHovered
        self.isFocused = isFocused
        self.isEnabled = isEnabled
    }

    func resolvedFrame(in size: CGSize) -> CGRect {
        guard let trailingInset else { return frame }
        return CGRect(
            x: size.width - trailingInset - frame.width,
            y: frame.minY,
            width: frame.width,
            height: frame.height
        )
    }
}

struct ModeDetailControlChrome: View {
    let surfaces: [ModeDetailControlSurface]
    var increaseContrastOverride: Bool?
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    init(
        surfaces: [ModeDetailControlSurface],
        increaseContrast: Bool? = nil
    ) {
        self.surfaces = surfaces
        increaseContrastOverride = increaseContrast
    }

    var body: some View {
        Canvas { context, size in
            for surface in surfaces {
                let frame = surface.resolvedFrame(in: size)
                let path = Path(
                    roundedRect: frame,
                    cornerRadius: Theme.controlRadius
                )
                let opacity = surface.isEnabled ? 1.0 : 0.46
                context.fill(
                    path,
                    with: .color(
                        (surface.isHovered ? Theme.hover : Theme.surface)
                            .opacity(opacity)
                    )
                )
                context.stroke(
                    path,
                    with: .color(
                        Theme.essentialBorderColor(
                            increaseContrast: usesStrongBoundary
                        )
                        .opacity(opacity)
                    ),
                    lineWidth: Theme.essentialBorderWidth(
                        increaseContrast: usesStrongBoundary
                    )
                )
                if surface.isFocused {
                    let focusFrame = frame.insetBy(dx: 2, dy: 2)
                    let focusPath = Path(
                        roundedRect: focusFrame,
                        cornerRadius: max(0, Theme.controlRadius - 2)
                    )
                    context.stroke(
                        focusPath,
                        with: .color(Theme.canvas),
                        lineWidth: Theme.focusGap + Theme.focusRingWidth
                    )
                    context.stroke(
                        focusPath,
                        with: .color(Theme.accent),
                        lineWidth: Theme.focusRingWidth
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var usesStrongBoundary: Bool {
        increaseContrastOverride ?? (colorSchemeContrast == .increased)
    }
}

private struct ModeDetailHeaderActions: View {
    let editLabel: String
    let duplicateLabel: String
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    @State private var hoveredControl: ModeDetailControlID?
    @FocusState private var focusedControl: ModeDetailControlID?

    var body: some View {
        ZStack {
            ModeDetailControlChrome(surfaces: [
                surface(.edit, frame: CGRect(x: 0, y: 0, width: 52, height: 28)),
                surface(.duplicate, frame: CGRect(x: 60, y: 0, width: 84, height: 28)),
            ])

            HStack(spacing: 8) {
                Button("Edit", action: onEdit)
                    .frame(width: 52, height: 28)
                    .focusEffectDisabled()
                    .focused($focusedControl, equals: .edit)
                    .onHover { setHover(.edit, isHovering: $0) }
                    .accessibilityLabel(editLabel)
                Button("Duplicate", action: onDuplicate)
                    .frame(width: 84, height: 28)
                    .focusEffectDisabled()
                    .focused($focusedControl, equals: .duplicate)
                    .onHover { setHover(.duplicate, isHovering: $0) }
                    .accessibilityLabel(duplicateLabel)
            }
            .font(Theme.ui(10.5, .semibold))
            .foregroundStyle(Theme.textPrimary)
            .buttonStyle(EmberPlainButtonStyle())
        }
        .frame(width: 144, height: 28)
    }

    private func surface(
        _ control: ModeDetailControlID,
        frame: CGRect
    ) -> ModeDetailControlSurface {
        ModeDetailControlSurface(
            frame: frame,
            isHovered: hoveredControl == control,
            isFocused: focusedControl == control,
            isEnabled: true
        )
    }

    private func setHover(_ control: ModeDetailControlID, isHovering: Bool) {
        if isHovering {
            hoveredControl = control
        } else if hoveredControl == control {
            hoveredControl = nil
        }
    }
}

private struct ModeDetailActions: View {
    let presentation: ModeLibraryActionPresentation
    let onAction: (ModeDetailAction) -> Void
    @State private var hoveredControl: ModeDetailControlID?
    @FocusState private var focusedControl: ModeDetailControlID?

    var body: some View {
        ZStack {
            ModeDetailControlChrome(surfaces: [
                surface(
                    .moveUp,
                    frame: CGRect(x: 0, y: 0, width: 92, height: 28),
                    isEnabled: presentation.canMoveUp
                ),
                surface(
                    .moveDown,
                    frame: CGRect(x: 100, y: 0, width: 108, height: 28),
                    isEnabled: presentation.canMoveDown
                ),
                trailingSurface(.delete, width: 68),
            ])

            HStack(spacing: 8) {
                actionButton(
                    "Move up",
                    symbolName: "arrow.up",
                    action: .moveUp,
                    control: .moveUp,
                    width: 92,
                    isEnabled: presentation.canMoveUp,
                    accessibilityLabel: presentation.moveUpLabel
                )
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                actionButton(
                    "Move down",
                    symbolName: "arrow.down",
                    action: .moveDown,
                    control: .moveDown,
                    width: 108,
                    isEnabled: presentation.canMoveDown,
                    accessibilityLabel: presentation.moveDownLabel
                )
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                Spacer()
                actionButton(
                    "Delete",
                    action: .delete,
                    control: .delete,
                    width: 68,
                    accessibilityLabel: presentation.deleteLabel,
                    accessibilityHint: presentation.deleteHint
                )
                .foregroundStyle(Theme.error)
            }
        }
        .frame(height: 28)
    }

    private func actionButton(
        _ title: String,
        symbolName: String? = nil,
        action: ModeDetailAction,
        control: ModeDetailControlID,
        width: CGFloat,
        isEnabled: Bool = true,
        accessibilityLabel: String,
        accessibilityHint: String? = nil
    ) -> some View {
        Button {
            onAction(action)
        } label: {
            if let symbolName {
                Label(title, systemImage: symbolName)
            } else {
                Text(title)
            }
        }
        .font(Theme.ui(10.5, .semibold))
        .frame(width: width, height: 28)
        .contentShape(Rectangle())
        .buttonStyle(EmberPlainButtonStyle())
        .focusEffectDisabled()
        .focused($focusedControl, equals: control)
        .onHover { setHover(control, isHovering: $0) }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.46)
        .foregroundStyle(action == .delete ? Theme.error : Theme.textPrimary)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint ?? "")
    }

    private func surface(
        _ control: ModeDetailControlID,
        frame: CGRect,
        isEnabled: Bool
    ) -> ModeDetailControlSurface {
        ModeDetailControlSurface(
            frame: frame,
            isHovered: hoveredControl == control,
            isFocused: focusedControl == control,
            isEnabled: isEnabled
        )
    }

    private func trailingSurface(
        _ control: ModeDetailControlID,
        width: CGFloat
    ) -> ModeDetailControlSurface {
        ModeDetailControlSurface(
            trailingInset: 0,
            width: width,
            height: 28,
            isHovered: hoveredControl == control,
            isFocused: focusedControl == control,
            isEnabled: true
        )
    }

    private func setHover(_ control: ModeDetailControlID, isHovering: Bool) {
        if isHovering {
            hoveredControl = control
        } else if hoveredControl == control {
            hoveredControl = nil
        }
    }
}

private enum ModeDetailAction: Equatable {
    case moveUp
    case moveDown
    case delete
}

func keycapLabel(_ name: String) -> String {
    if name.count == 1 {
        return name.uppercased()
    }
    return KeyMap.pretty(name) // "right ⌥", "f19", "esc", …
}
