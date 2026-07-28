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

    /// Which cache-aware streaming checkpoint a Streaming ASR model loads
    /// (ADR-0009). The chunk tier is part of the identity because it is what the
    /// engine's first-text cadence and its download are: EOU at 320 ms is a
    /// different artifact set from EOU at 160 ms, not a runtime option.
    enum StreamingVariant: Equatable {
        case parakeetEou320
    }

    /// Which ASR engine (ADR-0005) runs a catalog entry, and the model variant
    /// it needs. Each case maps through its family adapter to a lifecycle-owned
    /// `Transcribing` engine; `.parakeet` carries the FluidAudio checkpoint,
    /// `.whisper` the exact `argmaxinc/whisperkit-coreml` variant folder name,
    /// and `.streaming` the cache-aware checkpoint whose engine also conforms to
    /// `StreamCapableTranscribing`.
    enum Engine: Equatable {
        case parakeet(version: ParakeetVariant)
        case whisper(variant: String)
        case streaming(variant: StreamingVariant)
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
        /// Whether this model transcribes while the user speaks (ADR-0009).
        /// Presentation only: it is what the Models pane says, while the engine's
        /// conformance is what Dictation actually does. `ASRModelStreamingContract`
        /// holds the two to account for every entry.
        let streaming: Bool
        /// Hardcoded, currently inert (ADR-0006): stored honestly from the
        /// engines' docs, but no translate UI ships yet.
        let translate: Bool
        let blurb: String
    }

    /// The out-of-box default: Parakeet TDT v3, already warmed at launch.
    static let defaultID = "parakeet-v3"

    /// Curated, all-honest roster (ADR-0006): Parakeet v3/v2, one Streaming ASR
    /// model, plus a multilingual Whisper size tier. No Whisper `.en` variants and
    /// no tiny/base — they would only make Whisper look worse than Parakeet
    /// without adding language reach. Language lists and translate flags come from
    /// the engines' own docs; Parakeet has no X→English translate path, Whisper
    /// does. Sizes are decimal MB of what the pinned downloader actually
    /// transfers, which for EOU 320 is roughly twice what it needs.
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
            id: "parakeet-eou-320", engine: .streaming(variant: .parakeetEou320),
            name: "Parakeet EOU 320", languages: "English", size: "448 MB",
            speed: 5, quality: 3, streaming: true, translate: false,
            blurb: "Transcribes while you speak, so words appear before you release the "
                + "hotkey. English only. Its raw output is lowercase and unpunctuated — "
                + "Voice to Text inserts it exactly that way, and a Mode's Polish can "
                + "restore capitalization. It needs about 224 MB of weights, but the "
                + "downloader transfers about 448 MB."
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
}
