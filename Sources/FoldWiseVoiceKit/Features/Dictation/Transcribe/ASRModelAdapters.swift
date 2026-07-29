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
    typealias Delete = @Sendable (ASRModelCatalog.ParakeetVariant) async throws -> Void

    let modelIDs: Set<String> = ["parakeet-v3", "parakeet-v2"]
    private let availability: Availability
    private let download: Download
    private let delete: Delete

    init(
        availability: @escaping Availability,
        download: @escaping Download,
        delete: @escaping Delete = { _ in throw ASRModelAdapterError.deletionUnavailable }
    ) {
        self.availability = availability
        self.download = download
        self.delete = delete
    }

    init(
        modelDirectory: @escaping ModelDirectory,
        modelsExist: @escaping ModelsExist,
        compiledModelIsUsable: @escaping CompiledModelValidation = {
            ASRModelDataValidation.canLoadCompiledModel(at: $0)
        },
        download: @escaping Download,
        delete: @escaping Delete = { _ in throw ASRModelAdapterError.deletionUnavailable }
    ) {
        self.download = download
        self.delete = delete
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
            download: { try await Self.downloadFromLibrary($0, $1) },
            delete: ASRModelLibraryStorage.deleteParakeet
        )
    }

    static func downloadFromLibrary(
        _ variant: ASRModelCatalog.ParakeetVariant,
        _ progress: @escaping @Sendable (Double) -> Void,
        modelDirectory: @escaping ModelDirectory = ASRModelLibraryStorage.parakeetModelDirectory,
        downloadRepository: @escaping RepositoryDownload = ASRModelLibraryStorage.downloadRepository
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

    func removeModelData(for id: String) async throws {
        guard let variant = variant(for: id) else { throw ASRModelAdapterError.unknownModel(id) }
        try await delete(variant)
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
    typealias Delete = @Sendable (String) async throws -> Void

    let modelIDs: Set<String> = [
        "whisper-large-v3-turbo", "whisper-small", "whisper-large-v3",
    ]
    private let modelDirectory: ModelDirectory
    private let tokenizerDirectory: TokenizerDirectory
    private let compiledModelIsUsable: ModelValidation
    private let packageIsUsable: ModelValidation
    private let download: Download
    private let delete: Delete

    init(
        modelDirectory: @escaping ModelDirectory,
        tokenizerDirectory: @escaping TokenizerDirectory = ASRModelLibraryStorage.tokenizerDirectory,
        compiledModelIsUsable: @escaping ModelValidation = {
            ASRModelDataValidation.canLoadCompiledModel(at: $0)
        },
        packageIsUsable: @escaping ModelValidation = {
            ASRModelDataValidation.containsUsableModelPackage(at: $0)
        },
        download: @escaping Download,
        delete: @escaping Delete = { _ in throw ASRModelAdapterError.deletionUnavailable }
    ) {
        self.modelDirectory = modelDirectory
        self.tokenizerDirectory = tokenizerDirectory
        self.compiledModelIsUsable = compiledModelIsUsable
        self.packageIsUsable = packageIsUsable
        self.download = download
        self.delete = delete
    }

    init() {
        modelDirectory = ASRModelLibraryStorage.whisperModelDirectory
        tokenizerDirectory = ASRModelLibraryStorage.tokenizerDirectory
        compiledModelIsUsable = { ASRModelDataValidation.canLoadCompiledModel(at: $0) }
        packageIsUsable = { ASRModelDataValidation.containsUsableModelPackage(at: $0) }
        download = { try await Self.downloadFromLibrary($0, $1) }
        delete = ASRModelLibraryStorage.deleteWhisper
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

    func removeModelData(for id: String) async throws {
        guard let variant = variant(for: id) else { throw ASRModelAdapterError.unknownModel(id) }
        try await delete(variant)
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

/// The engine-family adapter for Streaming ASR models (ADR-0009). It is the only
/// adapter whose engines conform to `StreamCapableTranscribing`, which is what
/// makes a catalog entry's `streaming` flag honest rather than decorative — a
/// contract audit holds the two together for every entry.
///
/// It is a third family rather than a mode of `ParakeetASRModelAdapter` because
/// nothing but the vendor is shared: different repository layout, different
/// required artifacts, and an engine that answers a different protocol.
struct StreamingASRModelAdapter: ASRModelFamilyAdapting {
    typealias Availability = @Sendable (ASRModelCatalog.StreamingVariant) -> Bool
    typealias ModelDirectory = @Sendable (ASRModelCatalog.StreamingVariant) -> URL?
    typealias CompiledModelValidation = @Sendable (URL) -> Bool
    typealias Download = @Sendable (
        ASRModelCatalog.StreamingVariant,
        @escaping @Sendable (Double) -> Void
    ) async throws -> Void
    typealias RepositoryDownload = @Sendable (
        Repo,
        URL,
        String?,
        @escaping @Sendable (Double) -> Void
    ) async throws -> Void
    typealias Delete = @Sendable (ASRModelCatalog.StreamingVariant) async throws -> Void
    typealias MakeManager = @Sendable (
        ASRModelCatalog.StreamingVariant,
        URL
    ) -> any StreamingASRManaging

    let modelIDs: Set<String> = ["parakeet-eou-320", "nemotron-560"]
    private let modelDirectory: ModelDirectory
    private let availability: Availability
    private let download: Download
    private let delete: Delete
    private let makeManager: MakeManager
    private let hostIsAppleSilicon: Bool

    init(
        modelDirectory: @escaping ModelDirectory,
        availability: @escaping Availability,
        download: @escaping Download,
        delete: @escaping Delete = { _ in throw ASRModelAdapterError.deletionUnavailable },
        makeManager: @escaping MakeManager = Self.makeLibraryManager,
        hostIsAppleSilicon: Bool = ASRModelCatalog.hostIsAppleSilicon
    ) {
        self.modelDirectory = modelDirectory
        self.availability = availability
        self.download = download
        self.delete = delete
        self.makeManager = makeManager
        self.hostIsAppleSilicon = hostIsAppleSilicon
    }

    init(
        modelDirectory: @escaping ModelDirectory,
        compiledModelIsUsable: @escaping CompiledModelValidation = {
            ASRModelDataValidation.canLoadCompiledModel(at: $0)
        },
        download: @escaping Download,
        delete: @escaping Delete = { _ in throw ASRModelAdapterError.deletionUnavailable },
        makeManager: @escaping MakeManager = Self.makeLibraryManager,
        hostIsAppleSilicon: Bool = ASRModelCatalog.hostIsAppleSilicon
    ) {
        self.init(
            modelDirectory: modelDirectory,
            availability: { variant in
                guard let directory = modelDirectory(variant) else { return false }
                let required = StreamingASRModelAdapter.requiredArtifacts(for: variant)
                return required.models.allSatisfy {
                    ASRModelDataValidation.containsUsableCompiledModel(
                        named: $0,
                        under: directory,
                        validate: compiledModelIsUsable
                    )
                } && ASRModelDataValidation.containsValidVocabulary(
                    named: required.vocabulary,
                    under: directory
                )
            },
            download: download,
            delete: delete,
            makeManager: makeManager,
            hostIsAppleSilicon: hostIsAppleSilicon
        )
    }

    init(hostIsAppleSilicon: Bool = ASRModelCatalog.hostIsAppleSilicon) {
        self.init(
            modelDirectory: ASRModelLibraryStorage.streamingModelDirectory,
            download: { try await Self.downloadFromLibrary($0, $1) },
            delete: ASRModelLibraryStorage.deleteStreaming,
            hostIsAppleSilicon: hostIsAppleSilicon
        )
    }

    static func downloadFromLibrary(
        _ variant: ASRModelCatalog.StreamingVariant,
        _ progress: @escaping @Sendable (Double) -> Void,
        downloadRepository: @escaping RepositoryDownload = ASRModelLibraryStorage.downloadRepository
    ) async throws {
        try await downloadRepository(
            ASRModelStore.streamingRepository(variant),
            ASRModelStore.streamingDownloadRoot(),
            nil,
            progress
        )
    }

    /// Hardware the engine can't run on is reported the same way missing weights
    /// are, so the lifecycle's existing gates — selection, fallback, and stored
    /// selection left untouched — apply without knowing why a model is out.
    func isModelDataAvailable(for id: String) -> Bool {
        guard let variant = variant(for: id), meetsHardwareRequirement(variant) else { return false }
        return availability(variant)
    }

    func downloadModelData(
        for id: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let variant = variant(for: id) else { throw ASRModelAdapterError.unknownModel(id) }
        try requireSupportedHardware(variant, id: id)
        try await download(variant, progress)
    }

    func makeEngine(for id: String) throws -> Transcribing {
        guard let variant = variant(for: id) else { throw ASRModelAdapterError.unknownModel(id) }
        try requireSupportedHardware(variant, id: id)
        guard let directory = modelDirectory(variant) else {
            throw ASRModelAdapterError.modelDirectoryUnavailable
        }
        let makeManager = makeManager
        return StreamingTranscriber(makeManager: { makeManager(variant, directory) })
    }

    func removeModelData(for id: String) async throws {
        guard let variant = variant(for: id) else { throw ASRModelAdapterError.unknownModel(id) }
        try await delete(variant)
    }

    /// What a complete download looks like on disk. The compiled models and the
    /// vocabulary are separated because they are validated differently: one is
    /// loaded, the other is parsed. Nemotron's optional fused `decoder_joint` and
    /// its `metadata.json` are left out on purpose — the pinned manager loads
    /// both only when present, so requiring them would call a usable download
    /// incomplete.
    private static func requiredArtifacts(
        for variant: ASRModelCatalog.StreamingVariant
    ) -> (models: Set<String>, vocabulary: String) {
        switch variant {
        case .parakeetEou320:
            (
                [
                    ModelNames.ParakeetEOU.encoderFile,
                    ModelNames.ParakeetEOU.decoderFile,
                    ModelNames.ParakeetEOU.jointFile,
                ],
                ModelNames.ParakeetEOU.vocab
            )
        case .nemotron560:
            (
                [
                    ModelNames.NemotronStreaming.preprocessorFile,
                    // The library names the int8 encoder by its nested path;
                    // validation searches the download by file name.
                    URL(fileURLWithPath: ModelNames.NemotronStreaming.encoderInt8File)
                        .lastPathComponent,
                    ModelNames.NemotronStreaming.decoderFile,
                    ModelNames.NemotronStreaming.jointFile,
                ],
                ModelNames.NemotronStreaming.tokenizer
            )
        }
    }

    private static let makeLibraryManager: MakeManager = { variant, directory in
        switch variant {
        case .parakeetEou320:
            ParakeetEouStreamingManager(modelDirectory: directory, chunkSize: .ms320)
        case .nemotron560:
            NemotronStreamingManager(modelDirectory: directory, chunkSize: .ms560)
        }
    }

    private func meetsHardwareRequirement(_ variant: ASRModelCatalog.StreamingVariant) -> Bool {
        variant.hardware.isMet(byAppleSilicon: hostIsAppleSilicon)
    }

    private func requireSupportedHardware(
        _ variant: ASRModelCatalog.StreamingVariant,
        id: String
    ) throws {
        guard !meetsHardwareRequirement(variant),
              let missing = variant.hardware.missingHardware else { return }
        throw ASRModelAdapterError.unsupportedHardware(modelID: id, missing: missing)
    }

    private func variant(for id: String) -> ASRModelCatalog.StreamingVariant? {
        guard let entry = ASRModelCatalog.entry(for: id),
              case let .streaming(variant) = entry.engine else { return nil }
        return variant
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
            if containsUsableCompiledModel(at: url, validate: validate) {
                return true
            }
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
               dictionary.keys.allSatisfy({ Int($0) != nil }) {
                return true
            }
            if let array = json as? [String], !array.isEmpty {
                return true
            }
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

    static func containsUsableModelPackage(at package: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: package.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let manifest = jsonDictionary(
                  at: package.appendingPathComponent("Manifest.json")
              ),
              let rootModelIdentifier = manifest["rootModelIdentifier"] as? String,
              !rootModelIdentifier.isEmpty,
              let itemInfoEntries = manifest["itemInfoEntries"] as? [String: Any],
              !itemInfoEntries.isEmpty,
              itemInfoEntries[rootModelIdentifier] != nil else {
            return false
        }

        let packageRoot = package.standardizedFileURL.resolvingSymlinksInPath()
        let dataRoot = package.appendingPathComponent("Data")
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard dataRoot == packageRoot.appendingPathComponent("Data").standardizedFileURL else {
            return false
        }

        return itemInfoEntries.values.allSatisfy { value in
            guard let entry = value as? [String: Any],
                  let path = entry["path"] as? String,
                  !path.isEmpty,
                  !path.hasPrefix("/") else {
                return false
            }
            let item = dataRoot.appendingPathComponent(path)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard item.path.hasPrefix(dataRoot.path + "/") else { return false }
            return containsOnlyNonemptyData(at: item)
        }
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

    private static func containsOnlyNonemptyData(at url: URL) -> Bool {
        guard let values = try? url.resourceValues(
            forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        ) else { return false }
        if values.isRegularFile == true {
            return (values.fileSize ?? 0) > 0
        }
        guard values.isDirectory == true,
              let enumerator = FileManager.default.enumerator(
                  at: url,
                  includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
              ) else { return false }

        var containsData = false
        for case let item as URL in enumerator {
            guard let itemValues = try? item.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            ) else { return false }
            guard itemValues.isRegularFile == true else { continue }
            guard (itemValues.fileSize ?? 0) > 0 else { return false }
            containsData = true
        }
        return containsData
    }

    static func canLoadCompiledModel(at url: URL) -> Bool {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        return autoreleasepool {
            (try? MLModel(contentsOf: url, configuration: configuration)) != nil
        }
    }
}

private enum ASRModelAdapterError: LocalizedError {
    case unknownModel(String)
    case modelDirectoryUnavailable
    case deletionUnavailable
    case unsupportedHardware(modelID: String, missing: String)

    var errorDescription: String? {
        switch self {
        case let .unknownModel(id): "Unknown ASR model: \(id)"
        case .modelDirectoryUnavailable: "Couldn't locate the ASR model directory."
        case .deletionUnavailable: "ASR model deletion is unavailable."
        case let .unsupportedHardware(modelID, missing):
            "\(ASRModelCatalog.entry(for: modelID)?.name ?? modelID) needs a Mac with \(missing)."
        }
    }
}
