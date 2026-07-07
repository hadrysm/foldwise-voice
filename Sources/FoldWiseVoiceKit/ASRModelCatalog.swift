// Curated catalog of ASR models the app can transcribe with (ADR-0006),
// mirroring `ModelCatalog` for Ollama. Ids are our own stable vocabulary
// (`parakeet-v3`), independent of the engines' internal checkpoint names, so a
// stored id survives even if a library renames its weights. Slice 1 ships
// Parakeet only; Whisper entries land with the WhisperKit engine.

import Foundation

enum ASRModelCatalog {
    /// Which ASR engine (ADR-0005) runs a catalog entry. Each case maps to one
    /// `Transcribing` conformer behind the dispatcher.
    enum Engine: Equatable {
        case parakeet
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
}
