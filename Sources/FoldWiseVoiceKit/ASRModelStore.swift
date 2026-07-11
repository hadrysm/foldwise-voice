// Resolves and frees the on-disk weight caches for the ASR engines (slice 5,
// PRD #90). This is the one library-coupled seam — it turns a catalog entry
// into the directory its downloaded weights live in — so the Speech pane can
// reclaim disk space. FluidAudio exposes a public cache-directory accessor;
// WhisperKit downloads via the Hugging Face Hub convention into
// ~/Documents/huggingface/models. Both couplings live here alone, so if a
// library moves its files this is the only place to revise.

import FluidAudio
import Foundation
import WhisperKit

enum ASRModelStore {
    /// Bridge our catalog tag to FluidAudio's checkpoint enum. Central so the
    /// Parakeet loader (`Transcriber`) and this store agree on the mapping.
    static func fluidAudioVersion(_ variant: ASRModelCatalog.ParakeetVariant) -> AsrModelVersion {
        switch variant {
        case .v2: .v2
        case .v3: .v3
        }
    }

    /// The directory holding a catalog entry's downloaded weights, or nil if it
    /// can't be resolved. Parakeet uses FluidAudio's public cache accessor;
    /// Whisper follows WhisperKit's Hugging Face Hub default,
    /// `~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/<variant>`.
    static func modelDirectory(
        for engine: ASRModelCatalog.Engine,
        userDocumentsDirectory: URL? = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first
    ) -> URL? {
        switch engine {
        case let .parakeet(version):
            return AsrModels.defaultCacheDirectory(for: fluidAudioVersion(version))
        case let .whisper(variant):
            guard let userDocumentsDirectory else { return nil }
            return userDocumentsDirectory
                .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
                .appendingPathComponent(variant)
        }
    }

    /// Remove a downloaded model's weights, returning a user-facing error string
    /// or nil on success. Already-absent weights are the goal state, so they map
    /// to success — mirroring Ollama's "404 on delete is success" rule.
    static func delete(
        _ engine: ASRModelCatalog.Engine,
        userDocumentsDirectory: URL? = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first,
        removeItem: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
    ) -> String? {
        guard let dir = modelDirectory(
            for: engine, userDocumentsDirectory: userDocumentsDirectory
        ) else {
            return "Couldn't locate the model files to delete."
        }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: dir.path) else { return nil }
        do {
            try removeItem(dir)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
