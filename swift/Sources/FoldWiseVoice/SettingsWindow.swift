// Settings window: SuperWhisper-style sidebar navigation with card panes —
// Home (status), Modes, Models (pick/install Ollama models with speed &
// quality guidance), Configuration (keyboard shortcuts), Sound.
// Every change saves straight to modes.json; there is no Save button.

import AppKit
import SwiftUI

// MARK: - model catalog

/// Curated guidance for common Ollama models, rated for this app's job:
/// fast, faithful cleanup/rewriting of dictated text on Apple Silicon.
enum ModelCatalog {
    struct Entry: Identifiable {
        let name: String
        let size: String
        let speed: Int  // 1…5, higher = faster polish turnaround
        let quality: Int  // 1…5, higher = better cleanup/rewrites
        let blurb: String
        var id: String { name }
    }

    static let entries: [Entry] = [
        Entry(
            name: "gemma3:1b", size: "815 MB", speed: 5, quality: 2,
            blurb: "The smallest download here. Quick punctuation and filler "
                + "cleanup on any Mac; too small for faithful Email rewrites."),
        Entry(
            name: "llama3.2:1b", size: "1.3 GB", speed: 5, quality: 2,
            blurb: "Tiny and near-instant. Fine for punctuation and filler removal; "
                + "struggles with bigger rewrites like Email or Bullets."),
        Entry(
            name: "llama3.2:3b", size: "2.0 GB", speed: 4, quality: 3,
            blurb: "The default — best balance for dictation. Fast enough to feel "
                + "instant and solid at following the mode prompts."),
        Entry(
            name: "qwen2.5:3b", size: "1.9 GB", speed: 4, quality: 3,
            blurb: "On par with Llama 3.2 3B for cleanup, with stronger "
                + "multilingual dictation."),
        Entry(
            name: "gemma2:2b", size: "1.6 GB", speed: 4, quality: 2,
            blurb: "Google's compact model. Snappy at simple cleanup; less strict "
                + "about \"output only the text\" prompts."),
        Entry(
            name: "phi4-mini:3.8b", size: "2.5 GB", speed: 4, quality: 3,
            blurb: "Microsoft's small model. Follows the mode prompts closely and "
                + "handles multilingual dictation well for its size."),
        Entry(
            name: "gemma3:4b", size: "3.3 GB", speed: 4, quality: 4,
            blurb: "Google's current small model — the best cleanup quality below "
                + "the 7B tier, with strong multilingual support."),
        Entry(
            name: "qwen2.5:7b", size: "4.7 GB", speed: 3, quality: 4,
            blurb: "Noticeably better Email and Bullets rewrites. A beat slower; "
                + "comfortable on 16 GB+ Macs."),
        Entry(
            name: "llama3.1:8b", size: "4.9 GB", speed: 2, quality: 4,
            blurb: "High-quality rewriting and prompt adherence. Slower to respond; "
                + "wants ~8 GB of memory free."),
        Entry(
            name: "mistral:7b", size: "4.4 GB", speed: 3, quality: 3,
            blurb: "Solid all-rounder, but older instruction tuning than Qwen or "
                + "Llama at the same size."),
    ]

    /// Exact match first, then match on the part before ':' so
    /// "llama3.2:3b-instruct-q4_K_M" still gets guidance.
    static func entry(for name: String) -> Entry? {
        entries.first { $0.name == name }
            ?? entries.first { base($0.name) == base(name) }
    }

    private static func base(_ name: String) -> String {
        name.split(separator: ":").first.map(String.init) ?? name
    }
}

// MARK: - observable state

@MainActor
final class SettingsModel: ObservableObject {
    enum Pane: String, CaseIterable, Identifiable {
        case home = "Home"
        case modes = "Modes"
        case models = "Models"
        case configuration = "Configuration"
        case sound = "Sound"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .home: "house.fill"
            case .modes: "sparkles"
            case .models: "shippingbox.fill"
            case .configuration: "gearshape.fill"
            case .sound: "speaker.wave.2.fill"
            }
        }

        var tint: Color {
            switch self {
            case .home: .orange
            case .modes: .blue
            case .models: .purple
            case .configuration: .gray
            case .sound: .teal
            }
        }

        var title: String {
            switch self {
            case .home: "FoldWise Voice"
            case .modes: "Modes"
            case .models: "Ollama Models"
            case .configuration: "Keyboard Shortcuts"
            case .sound: "Sound"
            }
        }
    }

    enum RecordingField { case ptt, toggle }

    @Published var pane: Pane = .home
    @Published var activeMode = ""
    @Published var selectedModel = ""
    @Published var installed: [OllamaClient.InstalledModel]? = nil  // nil = checking, [] = Ollama down
    @Published var pullingModel: String? = nil
    @Published var pullStatus = ""
    @Published var pullFraction: Double? = nil
    @Published var pullError = ""
    @Published var customModel = ""
    @Published var pttKey = ""
    @Published var toggleKey = ""
    @Published var pauseAudio = true
    @Published var axTrusted = false
    @Published var status = ""
    @Published var statusIsError = false
    @Published var recordingField: RecordingField? = nil

    var modeNames: [String] = []
    var llmModes: Set<String> = []

    // wired by SettingsController
    var onCommit: (() -> Void)?
    var onRecord: ((RecordingField) -> Void)?
    var onSelectModel: ((String) -> Void)?
    var onInstallModel: ((String) -> Void)?
    var onRefreshModels: (() -> Void)?
    var onEditFile: (() -> Void)?

    var ollamaDown: Bool { installed?.isEmpty ?? false }

    /// False only when we can see Ollama's model list and ours isn't in it.
    var selectedModelInstalled: Bool {
        guard let installed, !installed.isEmpty else { return true }
        return installed.contains { $0.name == selectedModel }
    }
}

// MARK: - shared building blocks

private struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct CardRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 16)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct Keycap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .frame(minWidth: 14)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
    }
}

private struct RatingDots: View {
    let label: String
    let value: Int  // of 5
    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            HStack(spacing: 2.5) {
                ForEach(0..<5, id: \.self) { i in
                    Circle()
                        .fill(i < value ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
                        .frame(width: 4.5, height: 4.5)
                }
            }
        }
    }
}

private func sectionHeader(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .padding(.leading, 4)
}

// MARK: - main view

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

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
                Text("Version \(appVersion)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .padding(.horizontal, 10)
        .padding(.top, 34)  // clear the traffic lights
        .frame(width: 192)
        .background(VisualEffect(material: .sidebar))
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
            in: RoundedRectangle(cornerRadius: 8))
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
                    case .models: modelsPane
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
                        ? "No LLM mode configured" : model.selectedModel
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
                            NSWorkspace.shared.open(
                                URL(
                                    string:
                                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                                )!)
                        }
                        .controlSize(.small)
                    }
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
                                    ? "checkmark.circle.fill" : "circle"
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

    // MARK: models

    private var modelsPane: some View {
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
                    ForEach(Array((model.installed ?? []).enumerated()), id: \.element.id) {
                        i, installed in
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
                                for: model.customModel.trimmingCharacters(in: .whitespaces))
                        }
                    }
                }

                if !model.pullError.isEmpty {
                    Label(model.pullError, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            }
        }
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

    private func installedRow(_ installed: OllamaClient.InstalledModel) -> some View {
        let entry = ModelCatalog.entry(for: installed.name)
        let selected = installed.name == model.selectedModel
        return Button {
            model.onSelectModel?(installed.name)
        } label: {
            CardRow(
                title: installed.name
                    + (installed.sizeText.isEmpty ? "" : "  ·  \(installed.sizeText)"),
                subtitle: entry?.blurb
            ) {
                HStack(spacing: 12) {
                    modelRatings(installed.name)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? .blue : .secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        }
    }

    private func resetButton(icon: String, help: String, action: @escaping () -> Void)
        -> some View
    {
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
        return KeyMap.pretty(name)  // "right ⌥", "f19", "esc", …
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
                        })
                )
                .toggleStyle(.switch)
                .labelsHidden()
            }
        }
    }
}

// MARK: - controller

@MainActor
final class SettingsController {
    private let config: Config
    private let onSaved: () -> Void
    private let model = SettingsModel()
    private var window: NSWindow?
    private var keyMonitor: Any?
    private var statusClearTask: Task<Void, Never>?
    private var closeObserver: NSObjectProtocol?

    init(config: Config, onSaved: @escaping () -> Void) {
        self.config = config
        self.onSaved = onSaved
        wire()
    }

    func show() {
        if window == nil { build() }
        populate()
        // Accessory apps never own the menu bar; become a regular app while
        // settings is open so the menu bar shows FoldWise Voice, not whatever
        // app was frontmost before.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func wire() {
        model.onCommit = { [weak self] in self?.commit() }
        model.onRecord = { [weak self] field in self?.startRecording(field) }
        model.onSelectModel = { [weak self] name in self?.selectModel(name) }
        model.onInstallModel = { [weak self] name in self?.installModel(name) }
        model.onRefreshModels = { [weak self] in self?.refreshModels() }
        model.onEditFile = { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.open(self.config.path)
        }
    }

    private func build() {
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        let win = NSWindow(contentViewController: hosting)
        win.title = "FoldWise Voice Settings"
        win.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.center()
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: win, queue: .main
        ) { _ in
            // Back to menu-bar-only once settings closes.
            Task { @MainActor in NSApp.setActivationPolicy(.accessory) }
        }
        window = win
    }

    private func populate() {
        model.modeNames = config.modeOrder
        model.llmModes = Set(config.modeOrder.filter { config.modes[$0]?.usesLLM == true })
        model.activeMode = config.activeMode
        model.selectedModel = config.llmModel ?? ""
        model.pttKey = config.hotkey
        model.toggleKey = config.toggleHotkey ?? ""
        model.pauseAudio = config.pauseAudio
        model.axTrusted = TextInserter.accessibilityTrusted()
        model.status = ""
        refreshModels()
    }

    private func refreshModels() {
        model.installed = nil
        Task { @MainActor in
            self.model.installed = await OllamaClient.listModels()
        }
    }

    // MARK: - Ollama models

    private func selectModel(_ name: String) {
        model.selectedModel = name
        commit()
    }

    /// Pull `name` from the Ollama library, then make it the polish model.
    private func installModel(_ name: String) {
        guard model.pullingModel == nil, !name.isEmpty else { return }
        model.pullingModel = name
        model.pullError = ""
        model.pullStatus = "contacting Ollama…"
        model.pullFraction = nil
        Task { @MainActor in
            let error = await OllamaClient.pull(model: name) { status, fraction in
                Task { @MainActor in
                    self.model.pullStatus = status
                    self.model.pullFraction = fraction
                }
            }
            self.model.pullingModel = nil
            if let error {
                self.model.pullError = "Couldn't install \(name): \(error)"
            } else {
                self.model.customModel = ""
                self.model.selectedModel = name
                self.commit()
                self.refreshModels()
            }
        }
    }

    // MARK: - key recording

    private func startRecording(_ field: SettingsModel.RecordingField) {
        stopRecording()
        model.recordingField = field
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
            [weak self] event in
            guard let self else { return event }
            var name: String?
            if event.type == .flagsChanged {
                // Capture modifiers on press only (flag bit present).
                let keycode = CGKeyCode(event.keyCode)
                let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
                guard KeyMap.isModifierDown(keycode: keycode, flags: flags) == true else {
                    return nil
                }
                name = KeyMap.codeToName[keycode]
            } else {
                name = KeyMap.codeToName[CGKeyCode(event.keyCode)]
                    ?? event.charactersIgnoringModifiers?.lowercased()
            }
            if let name, !name.isEmpty {
                switch field {
                case .ptt: self.model.pttKey = name
                case .toggle: self.model.toggleKey = name
                }
                self.commit()
            }
            self.stopRecording()
            return nil  // swallow the keystroke
        }
    }

    private func stopRecording() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        model.recordingField = nil
    }

    // MARK: - save (called on every change — there is no Save button)

    private func commit() {
        let ptt = model.pttKey.trimmingCharacters(in: .whitespaces)
        let toggle = model.toggleKey.trimmingCharacters(in: .whitespaces)
        do {
            _ = try KeyMap.parse(ptt)
            if !toggle.isEmpty { _ = try KeyMap.parse(toggle) }
        } catch {
            setStatus("⚠️ \(error.localizedDescription)", isError: true)
            return
        }

        if !model.selectedModel.isEmpty {
            config.setLLMModel(model.selectedModel)
        }
        config.setActiveMode(model.activeMode)
        config.hotkey = ptt
        config.toggleHotkey = toggle.isEmpty ? nil : toggle
        config.pauseAudio = model.pauseAudio
        do {
            try config.save()
        } catch {
            setStatus("⚠️ save failed: \(error.localizedDescription)", isError: true)
            return
        }
        setStatus("Saved ✓", isError: false, clearAfter: 2)
        onSaved()
    }

    private func setStatus(_ text: String, isError: Bool, clearAfter seconds: Double? = nil) {
        statusClearTask?.cancel()
        model.status = text
        model.statusIsError = isError
        guard let seconds else { return }
        statusClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.model.status = ""
        }
    }
}
