// PROTOTYPE ONLY — selected outcome of the Wayfinder comparison ticket.
// Compact model list + detail inspector, with state controls kept outside the proposed UI.
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
    @State private var didExportSnapshots = false
    private let allowsSnapshotExport: Bool

    init(allowsSnapshotExport: Bool = true) {
        self.allowsSnapshotExport = allowsSnapshotExport
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

            InspectorVariant(pressure: pressure)
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
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            window.orderOut(nil)
            NSApp.terminate(nil)
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        window.orderOut(nil)
        if let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: output.appendingPathComponent("selected-c.png"))
        }
        NSApp.terminate(nil)
    }
}

// MARK: - Selected structure: compact list and detail inspector

private struct InspectorVariant: View {
    let pressure: PressureState
    @State private var selectedID = "parakeet-tdt-v3"

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
                compactList.frame(minWidth: 310, idealWidth: 370)
                detail.frame(minWidth: 330, idealWidth: 500)
            }
        }
        .padding(.bottom, 72)
    }

    private var compactList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                compactFamily(.speech)
                compactFamily(.polish)
            }
            .padding(18)
        }
        .background(PrototypeTheme.sidebarBackground.opacity(0.46))
    }

    private func compactFamily(_ family: ModelFamily) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            FamilyHeading(family: family, compact: true)
            ForEach(PrototypeModel.catalog.filter { $0.family == family }) { model in
                Button { selectedID = model.id } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            if family == .speech, model.isInstalled {
                                Image(systemName: model.isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(model.isSelected
                                        ? PrototypeTheme.accent
                                        : PrototypeTheme.textTertiary)
                            } else {
                                Circle()
                                    .fill(model.isInstalled ? PrototypeTheme.textSecondary : PrototypeTheme.hairline)
                                    .frame(width: 7, height: 7)
                                    .padding(.horizontal, 4.5)
                            }
                            Text(model.name)
                                .font(PrototypeTheme.ui(12.5, .semibold))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(model.size).font(PrototypeTheme.ui(9.5)).foregroundStyle(PrototypeTheme.textSecondary)
                        }
                        HStack(spacing: 10) {
                            Text(model.fit).lineLimit(1)
                            Spacer()
                            if model.speed > 0 {
                                Text("S \(model.speed)")
                            }
                            if model.quality > 0 {
                                Text("Q \(model.quality)")
                            }
                        }
                        .font(PrototypeTheme.ui(9.5))
                        .foregroundStyle(PrototypeTheme.textSecondary)
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

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: selected.family.symbol)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(PrototypeTheme.accent)
                        .frame(width: 34, height: 34)
                        .background(PrototypeTheme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selected.name).font(PrototypeTheme.ui(19, .semibold))
                        Text(selected.family.rawValue)
                            .font(PrototypeTheme.ui(10, .bold))
                            .textCase(.uppercase)
                            .kerning(0.8)
                            .foregroundStyle(PrototypeTheme.textTertiary)
                    }
                    Spacer()
                    ModelAction(model: selected, pressure: pressure, prominent: true)
                }

                Text(selected.blurb)
                    .font(PrototypeTheme.ui(12))
                    .foregroundStyle(PrototypeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 0) {
                    DetailFact(label: "Footprint", value: selected.size)
                    DetailFact(label: "Speed", value: selected.speed > 0 ? "\(selected.speed) / 5" : "Not rated")
                    DetailFact(label: "Quality", value: selected.quality > 0 ? "\(selected.quality) / 5" : "Not rated")
                }
                .prototypeCard()

                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Best fit")
                    Text(selected.fit).font(PrototypeTheme.ui(13, .semibold))
                }

                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel(selected.family == .speech ? "How selection works" : "How assignment works")
                    Text(selected.family.purpose)
                        .font(PrototypeTheme.ui(11.5))
                        .foregroundStyle(PrototypeTheme.textSecondary)
                    if selected.family == .speech {
                        Text(
                            "Downloading makes a model available. Selecting it is a separate, "
                                + "cancelable switch for future Dictation sessions."
                        )
                        .font(PrototypeTheme.ui(11.5))
                        .foregroundStyle(PrototypeTheme.textSecondary)
                    } else {
                        Text("Installing changes the local inventory only. It does not change any Mode.")
                            .font(PrototypeTheme.ui(11.5))
                            .foregroundStyle(PrototypeTheme.textSecondary)
                    }
                }

                if selected.family == .polish {
                    Button("Install another Ollama model…") {}
                        .controlSize(.small)
                }
            }
            .padding(26)
            .padding(.bottom, 30)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
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

private struct DetailFact: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(PrototypeTheme.ui(9.5, .bold))
                .textCase(.uppercase)
                .kerning(0.5)
                .foregroundStyle(PrototypeTheme.textTertiary)
            Text(value).font(PrototypeTheme.ui(12.5, .semibold))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
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
