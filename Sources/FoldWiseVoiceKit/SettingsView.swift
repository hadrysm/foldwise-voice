// Settings window content: SuperWhisper-style sidebar navigation with card
// panes — Home (status), Modes, Models (pick/install Ollama models with speed
// & quality guidance), Configuration (keyboard shortcuts), Sound.
// Every change saves straight to modes.json; there is no Save button.

import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    private static let accessibilitySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )

    /// Set in Info.plist by scripts/build_swift_app.py from version.txt;
    /// absent when running the bare binary (swift run).
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "dev"
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .frame(width: 780, height: 560)
    }

    // MARK: sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsModel.Pane.allCases) { pane in
                sidebarRow(pane)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 1) {
                Text("FoldWise Voice")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    Text("Version \(appVersion)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    sidebarUpdateControl
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .padding(.horizontal, 10)
        .padding(.top, 34) // clear the traffic lights
        .frame(width: 192)
        .background(VisualEffect(material: .sidebar))
    }

    /// Compact companion to the Updates row: a tiny refresh button next to
    /// the sidebar version label, sharing the same updateState.
    @ViewBuilder
    private var sidebarUpdateControl: some View {
        switch model.updateState {
        case .checking:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.5)
                .frame(width: 12, height: 12)
        case let .available(version, downloadURL):
            Button("Get v\(version)") {
                NSWorkspace.shared.open(downloadURL ?? UpdateChecker.releasesPage)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.accentColor)
        case .unavailable:
            EmptyView()
        case .idle, .upToDate, .failed:
            Button {
                model.onCheckUpdates?()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Check for updates")
        }
    }

    private func sidebarRow(_ pane: SettingsModel.Pane) -> some View {
        Button {
            model.pane = pane
        } label: {
            HStack(spacing: 9) {
                Image(systemName: pane.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 23, height: 23)
                    .background(pane.tint.gradient, in: RoundedRectangle(cornerRadius: 6))
                Text(pane.rawValue).font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            model.pane == pane ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    // MARK: content shell

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(model.pane.title)
                        .font(.system(size: 17, weight: .semibold))
                        .padding(.bottom, 2)
                    switch model.pane {
                    case .home: homePane
                    case .modes: modesPane
                    case .models: ModelsPane(model: model)
                    case .configuration: configurationPane
                    case .sound: soundPane
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 44)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !model.status.isEmpty {
                Divider()
                Text(model.status)
                    .font(.callout)
                    .foregroundStyle(model.statusIsError ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
        }
    }

    // MARK: home

    private var homePane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card {
                CardRow(
                    title: "Speech recognition",
                    subtitle: "Parakeet TDT v3 — fully on-device (Apple Neural Engine)"
                ) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Divider().padding(.leading, 14)
                CardRow(
                    title: "Polish model",
                    subtitle: model.selectedModel.isEmpty
                        ? "No LLM mode configured"
                        : model.selectedModel
                ) {
                    if model.ollamaDown {
                        Label("Ollama offline", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.orange)
                    } else if !model.selectedModelInstalled {
                        Button("Not installed — fix…") { model.pane = .models }
                            .controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
                Divider().padding(.leading, 14)
                CardRow(
                    title: "Accessibility",
                    subtitle: model.axTrusted
                        ? "Granted — dictation is pasted into the focused app"
                        : "Missing — text lands on the clipboard only"
                ) {
                    if model.axTrusted {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Open Accessibility…") {
                            if let url = Self.accessibilitySettingsURL {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .controlSize(.small)
                    }
                }
                Divider().padding(.leading, 14)
                CardRow(title: "Updates", subtitle: updateSubtitle) {
                    updateTrailing
                }
            }

            sectionHeader("Quick start")
            Card {
                CardRow(
                    title: "Hold \(KeyMap.pretty(model.pttKey)) and speak",
                    subtitle: "Release the key and the text is inserted where your cursor is. "
                        + (model.toggleKey.isEmpty
                            ? "Set a toggle key in Configuration for hands-free dictation."
                            : "Or tap \(KeyMap.pretty(model.toggleKey)) to start and stop.")
                ) {
                    Keycap(text: keycapLabel(model.pttKey))
                }
            }
        }
    }

    private var updateSubtitle: String {
        switch model.updateState {
        case .idle: "Version \(appVersion)"
        case .checking: "Version \(appVersion) — checking for updates…"
        case .upToDate: "Version \(appVersion) — you're up to date"
        case let .available(version, _): "Version \(appVersion) — v\(version) is available"
        case .failed: "Version \(appVersion) — couldn't reach GitHub, try again later"
        case .unavailable: "Version \(appVersion) — update checks need a packaged build"
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

    // MARK: modes

    private var modesPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("The active mode decides how your dictation is processed after transcription.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
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
                            .foregroundStyle(model.activeMode == name ? .blue : .secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Button("Edit modes.json…") { model.onEditFile?() }
                Text("Prompts and vocabulary live in the config file.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: configuration (keyboard shortcuts)

    private var configurationPane: some View {
        VStack(alignment: .leading, spacing: 16) {
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
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            sectionHeader("Recording bar")
            Card {
                CardRow(
                    title: "Style",
                    subtitle: "How the floating dictation bar looks"
                ) {
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.hudStyle },
                            set: {
                                model.hudStyle = $0
                                model.onCommit?()
                            }
                        )
                    ) {
                        ForEach(HUDStyle.allCases) { style in
                            Text(style.displayName).tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }

    private func resetButton(icon: String, help: String, action: @escaping () -> Void)
        -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
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
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                } else if key.isEmpty {
                    Text("Click to set")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
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

    private func keycapLabel(_ name: String) -> String {
        if name.count == 1 { return name.uppercased() }
        return KeyMap.pretty(name) // "right ⌥", "f19", "esc", …
    }

    // MARK: sound

    private var soundPane: some View {
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
    }
}

// MARK: models

/// The Models pane owns the pending-uninstall selection: the kebab overflow
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
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

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
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
                if !model.deleteError.isEmpty {
                    Label(model.deleteError, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
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
                            .font(.system(size: 13, weight: .semibold))
                        if let blurb = entry?.blurb, !blurb.isEmpty {
                            Text(blurb).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 16)
                    if deleting {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Uninstalling…")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        modelRatings(installed.name)
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected ? .blue : .secondary)
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
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
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
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
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
