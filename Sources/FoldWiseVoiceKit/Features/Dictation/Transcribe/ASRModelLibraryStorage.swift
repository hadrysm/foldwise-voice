import FluidAudio
import Foundation
import WhisperKit

enum ASRModelLibraryStorage {
    private struct DeletionFailure: LocalizedError {
        let errorDescription: String?
    }

    static let parakeetModelDirectory: @Sendable (
        ASRModelCatalog.ParakeetVariant
    ) -> URL? = { variant in
        ASRModelStore.modelDirectory(for: .parakeet(version: variant))
    }

    static let parakeetModelsExist: @Sendable (
        URL,
        ASRModelCatalog.ParakeetVariant
    ) -> Bool = { directory, variant in
        AsrModels.modelsExist(
            at: directory,
            version: ASRModelStore.fluidAudioVersion(variant)
        )
    }

    static let downloadParakeet: @Sendable (
        Repo,
        URL,
        String?,
        @escaping @Sendable (Double) -> Void
    ) async throws -> Void = { repository, directory, variant, progress in
        try await DownloadUtils.downloadRepo(
            repository,
            to: directory,
            variant: variant,
            progressHandler: { progress($0.fractionCompleted) }
        )
    }

    static let deleteParakeet: @Sendable (
        ASRModelCatalog.ParakeetVariant
    ) async throws -> Void = { variant in
        try await delete(.parakeet(version: variant))
    }

    static let whisperModelDirectory: @Sendable (String) -> URL? = { variant in
        ASRModelStore.modelDirectory(for: .whisper(variant: variant))
    }

    static let tokenizerDirectory: @Sendable (URL, String) -> URL = { modelDirectory, repository in
        HubApiWrapper(downloadBase: modelDirectory).localRepoLocation(.init(id: repository))
    }

    static let downloadWhisperWeights: @Sendable (
        String,
        @escaping @Sendable (Double) -> Void
    ) async throws -> URL = { variant, progress in
        try await WhisperKit.download(variant: variant) {
            progress($0.fractionCompleted)
        }
    }

    static let downloadWhisperTokenizer: @Sendable (
        String,
        URL,
        @escaping @Sendable (Double) -> Void
    ) async throws -> Void = { repository, destination, progress in
        let hub = HubApiWrapper(downloadBase: destination)
        _ = try await hub.snapshot(
            from: .init(id: repository),
            matching: ["config.json", "tokenizer_config.json", "tokenizer.json"]
        ) {
            progress($0.fractionCompleted)
        }
    }

    static let deleteWhisper: @Sendable (String) async throws -> Void = { variant in
        try await delete(.whisper(variant: variant))
    }

    private static func delete(_ engine: ASRModelCatalog.Engine) async throws {
        let failure = await Task.detached { ASRModelStore.delete(engine) }.value
        if let failure {
            throw DeletionFailure(errorDescription: failure)
        }
    }
}
