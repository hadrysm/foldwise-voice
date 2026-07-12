// Curated catalog of ASR models the app can transcribe with (ADR-0006),
// mirroring `ModelCatalog` for Ollama. Ids are our own stable vocabulary
// (`parakeet-v3`, `whisper-large-v3-turbo`), independent of the engines'
// internal checkpoint names, so a stored id survives even if a library renames
// its weights. Each entry names the engine that runs it; a Whisper entry also
// carries the exact WhisperKit variant to download.

import Foundation

enum ASRModelCatalog {
    /// Which FluidAudio Parakeet checkpoint an entry loads. v3 is the
    /// multilingual (25-language) default; v2 is NVIDIA's English-only sibling.
    /// A dedicated tag keeps FluidAudio's `AsrModelVersion` out of the catalog.
    enum ParakeetVariant: Equatable {
        case v2
        case v3
    }

    /// Which ASR engine (ADR-0005) runs a catalog entry, and the model variant
    /// it needs. Each case maps to one `Transcribing` conformer behind the
    /// dispatcher; `.parakeet` carries the FluidAudio checkpoint and `.whisper`
    /// the exact `argmaxinc/whisperkit-coreml` variant folder name so the
    /// engine resolves it verbatim.
    enum Engine: Equatable {
        case parakeet(version: ParakeetVariant)
        case whisper(variant: String)
    }

    struct Entry: Identifiable {
        let id: String
        let engine: Engine
        let name: String
        /// Language-coverage headline — the row's lead detail (ADR-0006).
        let languages: String
        let size: String
        let speed: Int // 1…5, higher = faster transcription
        let quality: Int // 1…5, higher = more accurate
        /// Hardcoded, currently inert capability flags (ADR-0006): stored honestly
        /// from the engines' docs, but nothing consumes them yet — no streaming
        /// or translate UI ships in this feature.
        let streaming: Bool
        let translate: Bool
        let blurb: String
    }

    /// The out-of-box default: Parakeet TDT v3, already warmed at launch.
    static let defaultID = "parakeet-v3"

    /// Curated, all-honest roster (ADR-0006): Parakeet v3/v2 plus a multilingual
    /// Whisper size tier. No Whisper `.en` variants and no tiny/base — they would
    /// only make Whisper look worse than Parakeet without adding language reach.
    /// Language lists and translate flags come from the engines' own docs;
    /// Parakeet has no X→English translate path, Whisper does.
    static let entries: [Entry] = [
        Entry(
            id: "parakeet-v3", engine: .parakeet(version: .v3), name: "Parakeet TDT v3",
            languages: "25 languages", size: "600 MB", speed: 5, quality: 4,
            streaming: false, translate: false,
            blurb: "The built-in default. Runs on the Neural Engine for instant, "
                + "power-efficient dictation across 25 European languages plus Japanese."
        ),
        Entry(
            id: "parakeet-v2", engine: .parakeet(version: .v2), name: "Parakeet TDT v2",
            languages: "English", size: "600 MB", speed: 5, quality: 4,
            streaming: false, translate: false,
            blurb: "NVIDIA's English-only Parakeet — the same instant Neural-Engine "
                + "speed as v3. Pick it if you only dictate in English."
        ),
        Entry(
            id: "whisper-large-v3-turbo",
            engine: .whisper(variant: "openai_whisper-large-v3-v20240930_turbo_632MB"),
            name: "Whisper large-v3-turbo", languages: "~99 languages", size: "632 MB",
            speed: 3, quality: 4, streaming: false, translate: true,
            blurb: "OpenAI's Whisper, near-large-v3 accuracy at a fraction of the size. "
                + "Downloads on first use, then runs on-device across ~99 languages."
        ),
        Entry(
            id: "whisper-small", engine: .whisper(variant: "openai_whisper-small"),
            name: "Whisper small", languages: "~99 languages", size: "483 MB",
            speed: 4, quality: 3, streaming: false, translate: true,
            blurb: "The lightest multilingual Whisper — faster and smaller than the large "
                + "models, with lower accuracy. A good fit for quick notes across ~99 languages."
        ),
        Entry(
            id: "whisper-large-v3",
            engine: .whisper(variant: "openai_whisper-large-v3_947MB"),
            name: "Whisper large-v3", languages: "~99 languages", size: "947 MB",
            speed: 2, quality: 5, streaming: false, translate: true,
            blurb: "Full Whisper large-v3 — the most accurate option, at the cost of size "
                + "and speed. Downloads on first use, then runs on-device."
        ),
    ]

    private static let aliases = [
        "openai_whisper-large-v3-v20240930_turbo_632mb": "whisper-large-v3-turbo",
    ]

    /// Resolve a stored id to its catalog entry, or `nil` for an unknown id —
    /// e.g. an old `mlx-community/...` fossil from the app's Python/MLX era.
    static func entry(for id: String) -> Entry? {
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let canonical = aliases[normalized] ?? normalized
        return entries.first { $0.id == canonical }
    }

    /// The engine that should transcribe for a stored id. An unknown or fossil
    /// id falls back to the default engine (Parakeet v3) *without* the stored
    /// string being rewritten (ADR-0006) — the fallback is a read-time decision.
    static func engine(forSelected id: String) -> Engine {
        entry(for: id)?.engine ?? .parakeet(version: .v3)
    }

    /// Pure outcome for a download attempt: map the engine's raw failure (nil on
    /// success) to the user-facing error the Speech pane shows, or nil to leave
    /// the previous selection intact. Mirrors `OllamaClient.deleteOutcome`.
    static func downloadError(for entry: Entry, failure: String?) -> String? {
        guard let failure, !failure.isEmpty else { return nil }
        return "Couldn't download \(entry.name): \(failure)"
    }

    /// Pure outcome of deleting a downloaded ASR model: the confirmation-dialog
    /// body and whether the active selection must fall back to the default
    /// engine. Deleting the active model drops dictation back to Parakeet until
    /// the user picks another (ADR-0006). Tested with no I/O, mirroring
    /// `OllamaClient.deleteOutcome`; the on-disk removal lives in `ASRModelStore`.
    static func deleteOutcome(for entry: Entry, isActive: Bool) -> DeleteOutcome {
        var message = "This removes \(entry.name)'s downloaded weights and frees \(entry.size)."
        if isActive {
            message += " It's your current speech model, so dictation falls back to "
                + "Parakeet until you pick another."
        }
        return DeleteOutcome(message: message, fallsBackToDefault: isActive)
    }

    struct DeleteOutcome: Equatable {
        /// Body of the delete confirmation dialog.
        let message: String
        /// True when the deleted model was active, so the caller must re-select
        /// the default (Parakeet) to keep dictation working.
        let fallsBackToDefault: Bool
    }
}
