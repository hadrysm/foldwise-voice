import CoreML
import FluidAudio
import Foundation

struct ParakeetASRModelAdapter: ASRModelFamilyAdapting {
    typealias Availability = @Sendable (ASRModelCatalog.ParakeetVariant) -> Bool
    typealias ModelDirectory = @Sendable (ASRModelCatalog.ParakeetVariant) -> URL?
    typealias ModelsExist = @Sendable (URL, ASRModelCatalog.ParakeetVariant) -> Bool
    typealias Download = @Sendable (
        ASRModelCatalog.ParakeetVariant,
        @escaping @Sendable (Double) -> Void
    ) async throws -> Void
    typealias RepositoryDownload = @Sendable (
        Repo,
        URL,
        String?,
        @escaping @Sendable (Double) -> Void
    ) async throws -> Void
    typealias CompiledModelValidation = @Sendable (URL) -> Bool

    let modelIDs: Set<String> = ["parakeet-v3", "parakeet-v2"]
    private let availability: Availability
    private let download: Download

    init(
        availability: @escaping Availability,
        download: @escaping Download
    ) {
        self.availability = availability
        self.download = download
    }

    init(
        modelDirectory: @escaping ModelDirectory,
        modelsExist: @escaping ModelsExist,
        compiledModelIsUsable: @escaping CompiledModelValidation = {
            ASRModelDataValidation.canLoadCompiledModel(at: $0)
        },
        download: @escaping Download
    ) {
        self.download = download
        availability = { variant in
            guard let directory = modelDirectory(variant), modelsExist(directory, variant) else {
                return false
            }
            let requiredModels: Set<String> = switch variant {
            case .v2:
                ModelNames.ASR.requiredModels
            case .v3:
                ModelNames.ASR.requiredModelsV3()
            }
            return requiredModels.allSatisfy {
                ASRModelDataValidation.containsUsableCompiledModel(
                    named: $0,
                    under: directory,
                    validate: compiledModelIsUsable
                )
            } && ASRModelDataValidation.containsValidVocabulary(
                named: ModelNames.ASR.vocabularyFile,
                under: directory
            )
        }
    }

    init() {
        self.init(
            modelDirectory: ASRModelLibraryStorage.parakeetModelDirectory,
            modelsExist: ASRModelLibraryStorage.parakeetModelsExist,
            download: { try await Self.downloadFromLibrary($0, $1) }
        )
    }

    static func downloadFromLibrary(
        _ variant: ASRModelCatalog.ParakeetVariant,
        _ progress: @escaping @Sendable (Double) -> Void,
        modelDirectory: @escaping ModelDirectory = ASRModelLibraryStorage.parakeetModelDirectory,
        downloadRepository: @escaping RepositoryDownload = ASRModelLibraryStorage.downloadParakeet
    ) async throws {
        guard let directory = modelDirectory(variant) else {
            throw ASRModelAdapterError.modelDirectoryUnavailable
        }
        let repository: Repo
        let downloadVariant: String?
        switch variant {
        case .v2:
            repository = .parakeetV2
            downloadVariant = nil
        case .v3:
            repository = .parakeetV3
            downloadVariant = ParakeetEncoderPrecision.int8.rawValue
        }
        try await downloadRepository(
            repository,
            directory.deletingLastPathComponent(),
            downloadVariant,
            progress
        )
    }

    func isModelDataAvailable(for id: String) -> Bool {
        guard let variant = variant(for: id) else { return false }
        return availability(variant)
    }

    func downloadModelData(
        for id: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let variant = variant(for: id) else { throw ASRModelAdapterError.unknownModel(id) }
        try await download(variant, progress)
    }

    func makeEngine(for id: String) throws -> Transcribing {
        guard let variant = variant(for: id) else { throw ASRModelAdapterError.unknownModel(id) }
        return Transcriber(version: variant)
    }

    private func variant(for id: String) -> ASRModelCatalog.ParakeetVariant? {
        guard let entry = ASRModelCatalog.entry(for: id),
              case let .parakeet(version) = entry.engine else { return nil }
        return version
    }
}

struct WhisperASRModelAdapter: ASRModelFamilyAdapting {
    typealias ModelDirectory = @Sendable (String) -> URL?
    typealias TokenizerDirectory = @Sendable (URL, String) -> URL
    typealias Download = @Sendable (
        String,
        @escaping @Sendable (Double) -> Void
    ) async throws -> Void
    typealias WeightDownload = @Sendable (
        String,
        @escaping @Sendable (Double) -> Void
    ) async throws -> URL
    typealias TokenizerDownload = @Sendable (
        String,
        URL,
        @escaping @Sendable (Double) -> Void
    ) async throws -> Void
    typealias ModelValidation = @Sendable (URL) -> Bool

    let modelIDs: Set<String> = [
        "whisper-large-v3-turbo", "whisper-small", "whisper-large-v3",
    ]
    private let modelDirectory: ModelDirectory
    private let tokenizerDirectory: TokenizerDirectory
    private let compiledModelIsUsable: ModelValidation
    private let packageIsUsable: ModelValidation
    private let download: Download

    init(
        modelDirectory: @escaping ModelDirectory,
        tokenizerDirectory: @escaping TokenizerDirectory = ASRModelLibraryStorage.tokenizerDirectory,
        compiledModelIsUsable: @escaping ModelValidation = {
            ASRModelDataValidation.canLoadCompiledModel(at: $0)
        },
        packageIsUsable: @escaping ModelValidation = {
            ASRModelDataValidation.canCompileModelPackage(at: $0)
        },
        download: @escaping Download
    ) {
        self.modelDirectory = modelDirectory
        self.tokenizerDirectory = tokenizerDirectory
        self.compiledModelIsUsable = compiledModelIsUsable
        self.packageIsUsable = packageIsUsable
        self.download = download
    }

    init() {
        modelDirectory = ASRModelLibraryStorage.whisperModelDirectory
        tokenizerDirectory = ASRModelLibraryStorage.tokenizerDirectory
        compiledModelIsUsable = { ASRModelDataValidation.canLoadCompiledModel(at: $0) }
        packageIsUsable = { ASRModelDataValidation.canCompileModelPackage(at: $0) }
        download = { try await Self.downloadFromLibrary($0, $1) }
    }

    static func downloadFromLibrary(
        _ variant: String,
        _ progress: @escaping @Sendable (Double) -> Void,
        downloadWeights: @escaping WeightDownload = ASRModelLibraryStorage.downloadWhisperWeights,
        downloadTokenizer: @escaping TokenizerDownload = ASRModelLibraryStorage.downloadWhisperTokenizer
    ) async throws {
        let directory = try await downloadWeights(variant) { progress($0 * 0.95) }
        try await downloadTokenizer(tokenizerRepository(for: variant), directory) {
            progress(0.95 + ($0 * 0.05))
        }
    }

    func isModelDataAvailable(for id: String) -> Bool {
        guard let variant = variant(for: id), let directory = modelDirectory(variant) else {
            return false
        }
        let modelsAreUsable = ["MelSpectrogram", "AudioEncoder", "TextDecoder"].allSatisfy { component in
            let compiled = directory.appendingPathComponent("\(component).mlmodelc")
            let package = directory.appendingPathComponent("\(component).mlpackage")
            return ASRModelDataValidation.containsUsableCompiledModel(
                at: compiled,
                validate: compiledModelIsUsable
            ) || packageIsUsable(package)
        }
        guard modelsAreUsable else { return false }
        let tokenizer = tokenizerDirectory(directory, Self.tokenizerRepository(for: variant))
        return ASRModelDataValidation.containsUsableTokenizer(at: tokenizer)
    }

    func downloadModelData(
        for id: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let variant = variant(for: id) else { throw ASRModelAdapterError.unknownModel(id) }
        try await download(variant, progress)
    }

    func makeEngine(for id: String) throws -> Transcribing {
        guard let variant = variant(for: id) else { throw ASRModelAdapterError.unknownModel(id) }
        return WhisperTranscriber(variant: variant)
    }

    private func variant(for id: String) -> String? {
        guard let entry = ASRModelCatalog.entry(for: id),
              case let .whisper(variant) = entry.engine else { return nil }
        return variant
    }

    private static func tokenizerRepository(for variant: String) -> String {
        variant.contains("small") ? "openai/whisper-small" : "openai/whisper-large-v3"
    }
}

private enum ASRModelDataValidation {
    static func containsUsableCompiledModel(
        named name: String,
        under directory: URL,
        validate: (URL) -> Bool
    ) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        ) else { return false }
        for case let url as URL in enumerator where url.lastPathComponent == name {
            if containsUsableCompiledModel(at: url, validate: validate) { return true }
        }
        return false
    }

    static func containsUsableCompiledModel(at url: URL, validate: (URL) -> Bool) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }
        return validate(url)
    }

    static func containsValidVocabulary(named name: String, under directory: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        ) else { return false }
        for case let url as URL in enumerator where url.lastPathComponent == name {
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let dictionary = json as? [String: String],
               !dictionary.isEmpty,
               dictionary.keys.allSatisfy({ Int($0) != nil }) { return true }
            if let array = json as? [String], !array.isEmpty { return true }
        }
        return false
    }

    static func containsUsableTokenizer(at directory: URL) -> Bool {
        guard let config = jsonDictionary(at: directory.appendingPathComponent("config.json")),
              config["model_type"] as? String == "whisper",
              let tokenizerConfig = jsonDictionary(
                  at: directory.appendingPathComponent("tokenizer_config.json")
              ),
              let tokenizerClass = tokenizerConfig["tokenizer_class"] as? String,
              tokenizerClass.replacingOccurrences(of: "Fast", with: "") == "WhisperTokenizer",
              let tokenizer = jsonDictionary(at: directory.appendingPathComponent("tokenizer.json")),
              let model = tokenizer["model"] as? [String: Any],
              model["type"] as? String == "BPE",
              let vocabulary = model["vocab"] as? [String: Any],
              !vocabulary.isEmpty,
              vocabulary.values.allSatisfy({ $0 is Int }),
              let merges = model["merges"] as? [Any],
              !merges.isEmpty else { return false }
        return merges.allSatisfy(isUsableMerge)
    }

    private static func jsonDictionary(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func isUsableMerge(_ value: Any) -> Bool {
        if let pair = value as? [String] {
            return pair.count == 2 && pair.allSatisfy { !$0.isEmpty }
        }
        guard let merge = value as? String else { return false }
        let pair = merge.split(separator: " ", omittingEmptySubsequences: false)
        return pair.count == 2 && pair.allSatisfy { !$0.isEmpty }
    }

    static func canLoadCompiledModel(at url: URL) -> Bool {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        return autoreleasepool {
            (try? MLModel(contentsOf: url, configuration: configuration)) != nil
        }
    }

    static func canCompileModelPackage(at url: URL) -> Bool {
        (try? MLModel.compileModel(at: url)) != nil
    }
}

private enum ASRModelAdapterError: LocalizedError {
    case unknownModel(String)
    case modelDirectoryUnavailable

    var errorDescription: String? {
        switch self {
        case let .unknownModel(id): "Unknown ASR model: \(id)"
        case .modelDirectoryUnavailable: "Couldn't locate the ASR model directory."
        }
    }
}
