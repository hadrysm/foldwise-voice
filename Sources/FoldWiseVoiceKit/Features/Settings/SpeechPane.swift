import SwiftUI

// MARK: - speech

/// The ASR section (ADR-0006): a curated catalog split into "Your Models"
/// (downloaded) and "Available", mirroring the Ollama `ModelsPane`. Rows lead
/// with language coverage; a downloaded model is a selectable row with a
/// checkmark for the active one, an available model shows a Download button with
/// fractional progress. Catalog descriptions and availability arrive from the
/// ASR lifecycle snapshot rather than being reconstructed by this surface.
struct SpeechPane: View {
    @ObservedObject var model: SettingsModel
    /// Armed by a downloaded row's kebab; drives the delete confirmation alert.
    @State private var pendingDelete: ASRModelDescriptor?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(
                "Choose which speech model transcribes your dictation — it applies to "
                    + "every mode. Parakeet is built in; Whisper reaches ~99 languages and "
                    + "downloads on first use, then runs on-device."
            )
            .font(Theme.ui(12))
            .foregroundStyle(Theme.textSecondary)

            let downloaded = model.asrCatalog.filter(\.isAvailable)
            let available = model.asrCatalog.filter { !$0.isAvailable }

            if !downloaded.isEmpty { section("Your Models", downloaded) }
            if !available.isEmpty { section("Available", available) }

            if let modelID = model.asrSwitching {
                operationStatus("Switching to \(modelName(modelID))…", allowsCancellation: true)
            } else if let modelID = model.asrRestoring {
                operationStatus("Restoring \(modelName(modelID))…", allowsCancellation: false)
            }

            if let recovery = model.asrRecoveryMessage {
                Label(recovery, systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(Theme.ui(11))
                    .foregroundStyle(Theme.textSecondary)
            }

            if !model.asrDownloadError.isEmpty {
                HStack(spacing: 8) {
                    Label(model.asrDownloadError, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.ui(11))
                        .foregroundStyle(.red)
                    if model.canRetryASRBootstrap {
                        Button("Retry") { model.onRetryASRBootstrap?() }
                            .controlSize(.small)
                    }
                }
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
                deleteConfirmation(for: entry)
            )
        }
    }

    /// A titled card of rows, mirroring the Ollama `ModelsPane`'s Installed /
    /// Model-library split so the pane separates downloaded from available.
    @ViewBuilder
    private func section(_ title: String, _ entries: [ASRModelDescriptor]) -> some View {
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
    private func row(_ entry: ASRModelDescriptor) -> some View {
        let downloaded = entry.isAvailable
        let selected = model.asrModel == entry.id
        let downloading = model.asrDownloading == entry.id
        let deleting = model.asrDeleting == entry.id
        let managementBusy = model.hasActiveASRManagementOperation
        // The built-in default (Parakeet v3) is the permanent fallback and
        // re-downloads at launch, so it is never offered for deletion.
        let deletable = downloaded && !deleting && entry.allowsDeletion
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
            .disabled(!downloaded || deleting || managementBusy)

            if downloading {
                HStack(spacing: 8) {
                    downloadProgress
                    if !model.isASRBootstrapping {
                        Button {
                            model.onCancelASROperation?()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .help("Cancel download")
                        .accessibilityLabel("Cancel download for \(entry.name)")
                    }
                }
            } else if !downloaded {
                Button("Download") { model.onDownloadASRModel?(entry.id) }
                    .controlSize(.small)
                    .disabled(managementBusy)
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
    private func deleteMenu(_ entry: ASRModelDescriptor) -> some View {
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
        .disabled(model.hasActiveASRManagementOperation)
        .accessibilityLabel("More actions for \(entry.name)")
    }

    @ViewBuilder
    private var downloadProgress: some View {
        if let fraction = model.asrDownloadFraction {
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

    private func ratings(_ entry: ASRModelDescriptor) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(entry.size).font(Theme.ui(10)).foregroundStyle(Theme.textSecondary)
            RatingDots(label: "Speed", value: entry.speed)
            RatingDots(label: "Quality", value: entry.quality)
        }
    }

    private func operationStatus(_ text: String, allowsCancellation: Bool) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).font(Theme.ui(11)).foregroundStyle(Theme.textSecondary)
            if allowsCancellation {
                Button("Cancel") { model.onCancelASROperation?() }
                    .controlSize(.small)
            }
        }
    }

    private func modelName(_ id: String) -> String {
        model.asrCatalog.first { $0.id == id }?.name ?? id
    }

    private func deleteConfirmation(for entry: ASRModelDescriptor) -> String {
        var message = "This removes \(entry.name)'s downloaded weights and frees \(entry.size)."
        if model.asrModel == entry.id {
            message += " It's your current speech model, so dictation falls back to "
                + "Parakeet until you pick another."
        }
        return message
    }
}
