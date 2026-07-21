// PROTOTYPE ONLY — selected comparison-ledger grammar for the compact list + inspector.
// State controls stay outside the proposed product UI.
// Run with `swift run ModelsViewPrototype`; rewrite properly during implementation.

import AppKit
import SwiftUI

@main
struct ModelsViewPrototypeApp: App {
    var body: some Scene {
        WindowGroup("Models comparison prototype") {
            PrototypeShell()
                .frame(minWidth: 880, minHeight: 640)
        }
        .defaultSize(width: 1180, height: 800)
        .windowResizability(.contentMinSize)
    }
}

/// Mirrors the existing Theme.swift base tokens exactly. These stay local to the
/// throwaway target so the prototype cannot create a second production visual system.
private enum PrototypeTheme {
    static let windowBackground = dynamic(light: 0xFCFBF8, dark: 0x161411)
    static let sidebarBackground = dynamic(light: 0xF7F5F0, dark: 0x1B1815)
    static let hairline = dynamic(light: 0xE9E5DC, dark: 0x2C2822)
    static let textPrimary = dynamic(light: 0x1B1813, dark: 0xF2EFE8)
    static let textSecondary = dynamic(light: 0x6E675A, dark: 0x9B9482)
    static let textTertiary = dynamic(light: 0x8F887A, dark: 0x87816F)
    static let accent = dynamic(light: 0xC24A22, dark: 0xE06A3E)
    static let activeNavBackground = dynamic(light: 0xFCFBF8, dark: 0x26221C)
    static let cardBackground = dynamic(light: 0xF7F5F0, dark: 0x1B1815)

    static let pageTitle = Font.system(size: 28, weight: .semibold)
    static let sectionLabel = Font.system(size: 11, weight: .bold)
    static let contentPadding: CGFloat = 36
    static let cardRadius: CGFloat = 8

    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

private enum ModelFamily: String {
    case speech = "Speech recognition"
    case polish = "Polish"

    var symbol: String {
        switch self {
        case .speech: "waveform"
        case .polish: "wand.and.stars"
        }
    }

    var purpose: String {
        switch self {
        case .speech: "One global selection transcribes every Dictation session."
        case .polish: "Installed here, then assigned separately in each Mode."
        }
    }
}

private struct PrototypeModel: Identifiable {
    let id: String
    let family: ModelFamily
    let name: String
    let fit: String
    let size: String
    let speed: Int
    let quality: Int
    let blurb: String
    let availability: String
    let isSelected: Bool
    let isInstalled: Bool

    static let catalog: [PrototypeModel] = [
        PrototypeModel(
            id: "parakeet-tdt-v3", family: .speech, name: "Parakeet TDT v3",
            fit: "25 languages · best for English", size: "600 MB", speed: 5, quality: 4,
            blurb: "Fast, accurate transcription on Apple Silicon. The built-in default and permanent fallback.",
            availability: "Ready", isSelected: true, isInstalled: true
        ),
        PrototypeModel(
            id: "whisper-large-v3-turbo", family: .speech, name: "Whisper large-v3-turbo",
            fit: "~99 languages · strongest reach", size: "1.6 GB", speed: 3, quality: 5,
            blurb: "The best multilingual accuracy in the catalog. A larger download with a slower first load.",
            availability: "Ready", isSelected: false, isInstalled: true
        ),
        PrototypeModel(
            id: "whisper-small", family: .speech, name: "Whisper small",
            fit: "~99 languages · compact", size: "500 MB", speed: 4, quality: 3,
            blurb: "A compact multilingual option when language coverage matters more than maximum accuracy.",
            availability: "Download", isSelected: false, isInstalled: false
        ),
        PrototypeModel(
            id: "qwen2.5:3b", family: .polish, name: "qwen2.5:3b",
            fit: "In-place + expanding Modes", size: "1.9 GB", speed: 4, quality: 3,
            blurb: "The default — sticks strictly to output-only prompts, with stronger multilingual dictation.",
            availability: "Installed", isSelected: false, isInstalled: true
        ),
        PrototypeModel(
            id: "gemma3:4b", family: .polish, name: "gemma3:4b",
            fit: "High-quality cleanup", size: "3.3 GB", speed: 4, quality: 4,
            blurb: "Google's current small model — the best cleanup quality below "
                + "the 7B tier, with strong multilingual support.",
            availability: "Install", isSelected: false, isInstalled: false
        ),
        PrototypeModel(
            id: "qwen2.5:7b", family: .polish, name: "qwen2.5:7b",
            fit: "Email + Bullets", size: "4.7 GB", speed: 3, quality: 4,
            blurb: "Noticeably better Email and Bullets rewrites. A beat slower; "
                + "comfortable on Macs with 16 GB or more.",
            availability: "Install", isSelected: false, isInstalled: false
        ),
        PrototypeModel(
            id: "custom", family: .polish,
            name: "acme-labs/very-long-instruction-model:Q4_K_M",
            fit: "External model · guidance unavailable", size: "8.2 GB", speed: 0, quality: 0,
            blurb: "No FoldWise comparison guidance is available for this custom Ollama model.",
            availability: "Installed", isSelected: false, isInstalled: true
        ),
    ]
}

private enum PressureState: String, CaseIterable, Identifiable {
    case baseline = "Baseline"
    case activity = "In progress"
    case recovery = "Recovery"

    var id: String {
        rawValue
    }
}

private struct PrototypeShell: View {
    @State private var pressure: PressureState = .baseline
    @State private var selectedID = "parakeet-tdt-v3"
    @State private var didExportSnapshots = false
    private let allowsSnapshotExport: Bool

    init(
        allowsSnapshotExport: Bool = true,
        initialPressure: PressureState = .baseline
    ) {
        self.allowsSnapshotExport = allowsSnapshotExport
        _pressure = State(initialValue: initialPressure)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(PrototypeTheme.hairline).frame(width: 1)
            main
        }
        .background(PrototypeTheme.windowBackground)
        .foregroundStyle(PrototypeTheme.textPrimary)
        .overlay(alignment: .bottomTrailing) { prototypeStateMenu }
        .onAppear { exportSnapshotsIfRequested() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 9) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(PrototypeTheme.accent)
                Text("FoldWise Voice").font(PrototypeTheme.ui(13.5, .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 20)

            ForEach([
                ("house", "Home"), ("slider.horizontal.3", "Modes"),
                ("square.stack.3d.up", "Models"), ("clock", "History"),
                ("chart.bar", "Stats"), ("gearshape", "Settings"),
            ], id: \.1) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.0).frame(width: 18)
                    Text(item.1)
                }
                .font(PrototypeTheme.ui(13.5, item.1 == "Models" ? .semibold : .medium))
                .foregroundStyle(item.1 == "Models" ? PrototypeTheme.textPrimary : PrototypeTheme.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 36)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    item.1 == "Models" ? PrototypeTheme.activeNavBackground : .clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
            }
            Spacer()
            Text("PROTOTYPE · NOT PRODUCT UI")
                .font(PrototypeTheme.ui(9, .bold))
                .kerning(0.8)
                .foregroundStyle(PrototypeTheme.textTertiary)
                .padding(.horizontal, 10)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 14)
        .frame(width: 190)
        .background(PrototypeTheme.sidebarBackground)
    }

    private var main: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Models")
                        .font(PrototypeTheme.pageTitle)
                        .kerning(-0.56)
                    Text("Compare what runs each stage, then manage its local data.")
                        .font(PrototypeTheme.ui(12))
                        .foregroundStyle(PrototypeTheme.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, PrototypeTheme.contentPadding)
            .padding(.top, 28)
            .padding(.bottom, 18)

            Divider()

            SelectedModelsGrammar(pressure: pressure, selectedID: $selectedID)
                .id(pressure.rawValue)
        }
    }

    private var prototypeStateMenu: some View {
        Menu {
            ForEach(PressureState.allCases) { state in
                Button {
                    pressure = state
                } label: {
                    if pressure == state {
                        Label(state.rawValue, systemImage: "checkmark")
                    } else {
                        Text(state.rawValue)
                    }
                }
            }
        } label: {
            Label("Prototype state: \(pressure.rawValue)", systemImage: "testtube.2")
                .font(PrototypeTheme.ui(11, .semibold))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(PrototypeTheme.textPrimary, in: Capsule())
        }
        .foregroundStyle(PrototypeTheme.windowBackground)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .padding(16)
    }

    @MainActor
    private func exportSnapshotsIfRequested() {
        guard allowsSnapshotExport, !didExportSnapshots,
              let directory = ProcessInfo.processInfo.environment["MODELS_PROTOTYPE_EXPORT_DIR"],
              !directory.isEmpty
        else { return }
        didExportSnapshots = true

        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let view = PrototypeShell(allowsSnapshotExport: false)
            .frame(width: 1180, height: 800)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 1180, height: 800)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: output.appendingPathComponent("selected-comparison-ledger.png"))
            }
        }
        window.orderOut(nil)
        NSApp.terminate(nil)
    }
}

// MARK: - Selected grammar: aligned comparison evidence, operations in the inspector

private struct SelectedModelsGrammar: View {
    let pressure: PressureState
    @Binding var selectedID: String

    private var selected: PrototypeModel {
        PrototypeModel.catalog.first { $0.id == selectedID } ?? PrototypeModel.catalog[0]
    }

    var body: some View {
        VStack(spacing: 0) {
            StateNotice(pressure: pressure)
                .padding(.horizontal, PrototypeTheme.contentPadding)
                .padding(.vertical, 16)
            Divider()
            HSplitView {
                ledgerList.frame(minWidth: 340, idealWidth: 430)
                ledgerInspector.frame(minWidth: 270, idealWidth: 380)
            }
        }
        .padding(.bottom, 72)
    }

    private var ledgerList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ledgerFamily(.speech)
                ledgerFamily(.polish)
            }
            .padding(18)
        }
        .background(PrototypeTheme.sidebarBackground.opacity(0.46))
    }

    private func ledgerFamily(_ family: ModelFamily) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            FamilyHeading(family: family, compact: true)
            HStack(spacing: 8) {
                Text("MODEL / FIT").frame(maxWidth: .infinity, alignment: .leading)
                Text("SIZE").frame(width: 42, alignment: .trailing)
                Text("SPD").frame(width: 42, alignment: .center)
                Text("QLTY").frame(width: 42, alignment: .center)
                Text("STATE").frame(width: 64, alignment: .trailing)
            }
            .font(PrototypeTheme.ui(8.5, .bold))
            .kerning(0.45)
            .foregroundStyle(PrototypeTheme.textTertiary)
            .padding(.horizontal, 10)

            ForEach(PrototypeModel.catalog.filter { $0.family == family }) { model in
                Button { selectedID = model.id } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                if family == .speech, model.isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(PrototypeTheme.accent)
                                }
                                Text(model.name)
                                    .font(PrototypeTheme.ui(11.5, .semibold))
                                    .lineLimit(1)
                            }
                            Text(model.fit)
                                .font(PrototypeTheme.ui(9))
                                .foregroundStyle(PrototypeTheme.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(model.size)
                            .font(PrototypeTheme.ui(9.5, .medium))
                            .frame(width: 42, alignment: .trailing)
                        RatingMarks(value: model.speed)
                            .frame(width: 42)
                        RatingMarks(value: model.quality)
                            .frame(width: 42)
                        ModelStateLabel(model: model, pressure: pressure, compact: true)
                            .frame(width: 64, alignment: .trailing)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        selectedID == model.id ? PrototypeTheme.activeNavBackground : .clear,
                        in: RoundedRectangle(cornerRadius: 7)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(selectedID == model.id ? PrototypeTheme.hairline : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var ledgerInspector: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(selected.family.rawValue.uppercased())
                            .font(PrototypeTheme.sectionLabel)
                            .kerning(1.1)
                            .foregroundStyle(PrototypeTheme.textTertiary)
                        Text(selected.name)
                            .font(PrototypeTheme.ui(19, .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        ModelStateLabel(model: selected, pressure: pressure)
                    }

                    Text(selected.blurb)
                        .font(PrototypeTheme.ui(12))
                        .foregroundStyle(PrototypeTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        inspectorLabel(selected.family == .speech ? "Selection model" : "Inventory model")
                        Text(selected.family.purpose)
                            .font(PrototypeTheme.ui(11.5))
                            .foregroundStyle(PrototypeTheme.textSecondary)
                    }

                    Text(
                        "Size and ratings stay in the aligned list; this inspector adds meaning "
                            + "rather than repeating the comparison table."
                    )
                    .font(PrototypeTheme.ui(10.5))
                    .foregroundStyle(PrototypeTheme.textTertiary)
                    .padding(12)
                    .prototypeCard()
                }
                .padding(26)
            }

            Divider()
            HStack(spacing: 10) {
                ModelAction(model: selected, pressure: pressure, prominent: true)
                Spacer()
                DestructiveModelAction(model: selected, compact: true)
            }
            .padding(.horizontal, 26)
            .frame(height: 58)
            .background(PrototypeTheme.windowBackground)
        }
    }

    private func inspectorLabel(_ text: String) -> some View {
        Text(text)
            .font(PrototypeTheme.sectionLabel)
            .kerning(1.1)
            .foregroundStyle(PrototypeTheme.textTertiary)
            .textCase(.uppercase)
    }
}

// MARK: - shared prototype components

private struct FamilyHeading: View {
    let family: ModelFamily
    var compact = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: family.symbol)
                .foregroundStyle(PrototypeTheme.textTertiary)
            Text(family.rawValue)
                .font(PrototypeTheme.sectionLabel)
                .kerning(1.1)
                .textCase(.uppercase)
                .foregroundStyle(PrototypeTheme.textTertiary)
            if !compact {
                Text(family.purpose)
                    .font(PrototypeTheme.ui(10.5))
                    .foregroundStyle(PrototypeTheme.textSecondary)
            }
            Spacer()
            if family == .speech {
                Text("Global selection")
                    .font(PrototypeTheme.ui(9.5, .medium))
                    .foregroundStyle(PrototypeTheme.accent)
            } else {
                Text("Mode inventory")
                    .font(PrototypeTheme.ui(9.5, .medium))
                    .foregroundStyle(PrototypeTheme.textSecondary)
            }
        }
        .padding(.leading, 4)
    }
}

private struct StateNotice: View {
    let pressure: PressureState

    var body: some View {
        switch pressure {
        case .baseline:
            EmptyView()
        case .activity:
            Notice(
                symbol: "arrow.down.circle",
                title: "Two family-local operations are visible",
                message: "Whisper small is downloading (62%); qwen2.5:7b is installing "
                    + "(41% — pulling layers). Competing actions are disabled only within "
                    + "their own family.",
                tone: PrototypeTheme.textSecondary
            )
        case .recovery:
            Notice(
                symbol: "arrow.trianglehead.2.clockwise.rotate.90",
                title: "Saved selection unavailable",
                message: "Whisper small remains your saved Speech recognition selection. "
                    + "Parakeet TDT v3 is effective until you download it again. Ollama isn't "
                    + "running; installed Polish inventory cannot be checked.",
                tone: PrototypeTheme.accent
            )
        }
    }
}

private struct Notice: View {
    let symbol: String
    let title: String
    let message: String
    let tone: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tone).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(PrototypeTheme.ui(12, .semibold))
                Text(message).font(PrototypeTheme.ui(10.5)).foregroundStyle(PrototypeTheme.textSecondary)
            }
            Spacer()
            if title.contains("unavailable") {
                Button("Download again") {}.controlSize(.small)
            }
        }
        .padding(12)
        .prototypeCard()
    }
}

private struct ModelStateLabel: View {
    let model: PrototypeModel
    let pressure: PressureState
    var compact = false

    private var text: String {
        if pressure == .activity, model.id == "whisper-small" {
            return compact ? "62%" : "Downloading · 62%"
        }
        if pressure == .activity, model.id == "qwen2.5:7b" {
            return compact ? "41%" : "Installing · 41%"
        }
        if pressure == .recovery, model.id == "whisper-small" {
            return compact
                ? "Saved · missing"
                : "Saved selection · unavailable"
        }
        if pressure == .recovery, model.id == "parakeet-tdt-v3" {
            return compact ? "Effective" : "Effective fallback"
        }
        if model.family == .speech, model.isSelected {
            return "Selected"
        }
        return model.availability
    }

    private var tone: Color {
        if model.isSelected || (pressure == .recovery && model.id == "parakeet-tdt-v3") {
            return PrototypeTheme.accent
        }
        return PrototypeTheme.textSecondary
    }

    var body: some View {
        Text(text)
            .font(PrototypeTheme.ui(compact ? 8.5 : 10, .semibold))
            .foregroundStyle(tone)
            .lineLimit(1)
            .help(text)
    }
}

private struct RatingMarks: View {
    let value: Int

    var body: some View {
        Text(value > 0 ? "\(value)/5" : "—")
            .font(PrototypeTheme.ui(9.5, .medium))
            .foregroundStyle(value > 0 ? PrototypeTheme.textSecondary : PrototypeTheme.textTertiary)
            .accessibilityLabel(value > 0 ? "\(value) out of 5" : "Not rated")
    }
}

private struct DestructiveModelAction: View {
    let model: PrototypeModel
    var compact = false

    private var canRemove: Bool {
        model.isInstalled && model.id != "parakeet-tdt-v3"
    }

    var body: some View {
        if canRemove {
            Menu {
                Button(model.family == .speech ? "Delete download…" : "Uninstall…", role: .destructive) {}
            } label: {
                if compact {
                    Label("More", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                        .frame(width: 28, height: 28)
                } else {
                    Label(
                        model.family == .speech ? "Delete download…" : "Uninstall…",
                        systemImage: "trash"
                    )
                }
            }
            .menuStyle(.button)
            .menuIndicator(compact ? .hidden : .visible)
            .controlSize(.small)
            .accessibilityLabel(model.family == .speech ? "Model download actions" : "Installed model actions")
        }
    }
}

private struct ModelAction: View {
    let model: PrototypeModel
    let pressure: PressureState
    var prominent = false

    var body: some View {
        if pressure == .activity, model.id == "whisper-small" {
            VStack(alignment: .trailing, spacing: 2) {
                ProgressView(value: 0.62).frame(width: 72)
                Text("62% · Cancel").font(PrototypeTheme.ui(9)).foregroundStyle(PrototypeTheme.textSecondary)
            }
        } else if pressure == .activity, model.id == "qwen2.5:7b" {
            VStack(alignment: .trailing, spacing: 2) {
                ProgressView(value: 0.41).frame(width: 72)
                Text("41% · Pulling").font(PrototypeTheme.ui(9)).foregroundStyle(PrototypeTheme.textSecondary)
            }
        } else if pressure == .recovery, model.id == "whisper-small" {
            Button("Download") {}.controlSize(.small)
        } else if model.family == .speech, model.isInstalled {
            if model.isSelected {
                Text("Selected")
                    .font(PrototypeTheme.ui(10.5, .semibold))
                    .foregroundStyle(PrototypeTheme.accent)
            } else if prominent {
                Button("Select") {}.controlSize(.small).buttonStyle(.borderedProminent)
            } else {
                Button("Select") {}.controlSize(.small)
            }
        } else if model.family == .speech {
            Button("Download") {}.controlSize(.small)
        } else if model.isInstalled {
            Menu { Button("Uninstall…", role: .destructive) {} } label: {
                Image(systemName: "ellipsis").frame(width: 28, height: 28)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        } else if prominent {
            Button("Install") {}.controlSize(.small).buttonStyle(.borderedProminent)
        } else {
            Button("Install") {}.controlSize(.small)
        }
    }
}

private extension View {
    func prototypeCard() -> some View {
        background(PrototypeTheme.cardBackground, in: RoundedRectangle(cornerRadius: PrototypeTheme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: PrototypeTheme.cardRadius)
                    .strokeBorder(PrototypeTheme.hairline, lineWidth: 1)
            )
    }
}
