// Curated catalog of ASR models the app can transcribe with (ADR-0006),
// mirroring `ModelCatalog` for Ollama. Ids are our own stable vocabulary
// (`parakeet-v3`, `whisper-large-v3-turbo`), independent of the engines'
// internal checkpoint names, so a stored id survives even if a library renames
// its weights. Each entry names the engine that runs it; a Whisper entry also
// carries the exact WhisperKit variant to download.

import Foundation

enum ASRModelCatalog {
    /// Which ASR engine (ADR-0005) runs a catalog entry, and the model variant
    /// it needs. Each case maps to one `Transcribing` conformer behind the
    /// dispatcher; `.whisper` carries the exact `argmaxinc/whisperkit-coreml`
    /// variant folder name so `WhisperKit(model:)` resolves it verbatim.
    enum Engine: Equatable {
        case parakeet
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
        let blurb: String
    }

    /// The out-of-box default: Parakeet TDT v3, already warmed at launch.
    static let defaultID = "parakeet-v3"

    static let entries: [Entry] = [
        Entry(
            id: "parakeet-v3", engine: .parakeet, name: "Parakeet TDT v3",
            languages: "25 languages", size: "600 MB", speed: 5, quality: 4,
            blurb: "The built-in default. Runs on the Neural Engine for instant, "
                + "power-efficient dictation across 25 European languages plus Japanese."
        ),
        Entry(
            id: "whisper-large-v3-turbo",
            engine: .whisper(variant: "openai_whisper-large-v3-v20240930_turbo_632MB"),
            name: "Whisper large-v3-turbo", languages: "~99 languages", size: "632 MB",
            speed: 3, quality: 4,
            blurb: "OpenAI's Whisper, near-large-v3 accuracy at a fraction of the size. "
                + "Downloads on first use, then runs on the Neural Engine across ~99 languages."
        ),
    ]

    /// Resolve a stored id to its catalog entry, or `nil` for an unknown id —
    /// e.g. an old `mlx-community/...` fossil from the app's Python/MLX era.
    static func entry(for id: String) -> Entry? {
        entries.first { $0.id == id }
    }

    /// The engine that should transcribe for a stored id. An unknown or fossil
    /// id falls back to the default engine (Parakeet) *without* the stored
    /// string being rewritten (ADR-0006) — the fallback is a read-time decision.
    static func engine(forSelected id: String) -> Engine {
        entry(for: id)?.engine ?? .parakeet
    }

    /// Pure outcome for a download attempt: map the engine's raw failure (nil on
    /// success) to the user-facing error the Speech pane shows, or nil to leave
    /// the previous selection intact. Mirrors `OllamaClient.deleteOutcome`.
    static func downloadError(for entry: Entry, failure: String?) -> String? {
        guard let failure, !failure.isEmpty else { return nil }
        return "Couldn't download \(entry.name): \(failure)"
    }
}
