import Foundation
import SwiftUI

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
                "Install Polish models here, then assign one to each Mode in its editor. "
                    + "Speed and quality are rated for dictation on Apple Silicon."
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
    /// warning when one or more Modes reference this model.
    private func uninstallMessage(for target: OllamaClient.InstalledModel) -> String {
        var message = target.sizeText.isEmpty
            ? "This permanently removes \(target.name) from Ollama."
            : "This permanently removes \(target.name) and frees \(target.sizeText)."
        let affected = model.modes.filter { $0.llmModel == target.name }.map(\.name)
        if !affected.isEmpty {
            message += " It's used by \(affected.joined(separator: ", ")), so those Modes "
                + "will use raw text until another model is assigned."
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

    /// Installed models are inventory, not a shared selection. Assignment lives
    /// in the Mode editor; this row therefore exposes information and uninstall only.
    private func installedRow(_ installed: OllamaClient.InstalledModel) -> some View {
        let entry = ModelCatalog.entry(for: installed.name)
        let deleting = model.deletingModel == installed.name
        return HStack(alignment: .center, spacing: 12) {
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
