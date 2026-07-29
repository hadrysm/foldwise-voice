import XCTest
@testable import FoldWiseVoiceKit

final class ASRModelAdapterTests: XCTestCase {
    private var directory: URL?

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ASRModelAdapterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: try XCTUnwrap(directory),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let directory {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func testWhisperReportsCompleteCoreMLDataAsAvailable() throws {
        let directory = try XCTUnwrap(directory)
        let tokenizerDirectory = directory.appendingPathComponent("tokenizer")
        for component in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            try writeCompiledModel(named: component, to: directory)
        }
        try writeTokenizerData(to: tokenizerDirectory)
        let adapter = WhisperASRModelAdapter(
            modelDirectory: { _ in directory },
            tokenizerDirectory: { _, _ in tokenizerDirectory },
            compiledModelIsUsable: FakeCoreMLValidation.compiledModelIsUsable,
            packageIsUsable: FakeCoreMLValidation.modelPackageIsUsable,
            download: { _, _ in }
        )

        XCTAssertTrue(adapter.isModelDataAvailable(for: "whisper-small"))
    }

    func testWhisperReportsEmptyModelDirectoriesAsUnavailable() throws {
        let directory = try XCTUnwrap(directory)
        for component in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent("\(component).mlmodelc"),
                withIntermediateDirectories: true
            )
        }
        let adapter = WhisperASRModelAdapter(
            modelDirectory: { _ in directory },
            compiledModelIsUsable: FakeCoreMLValidation.compiledModelIsUsable,
            packageIsUsable: FakeCoreMLValidation.modelPackageIsUsable,
            download: { _, _ in }
        )

        XCTAssertFalse(adapter.isModelDataAvailable(for: "whisper-small"))
    }

    func testWhisperReportsNonEmptyCorruptModelDataAsUnavailable() throws {
        let directory = try XCTUnwrap(directory)
        for component in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            try writeCompiledModel(named: component, to: directory)
        }
        let adapter = WhisperASRModelAdapter(
            modelDirectory: { _ in directory },
            download: { _, _ in }
        )

        XCTAssertFalse(adapter.isModelDataAvailable(for: "whisper-small"))
    }

    func testWhisperReportsPackagedCoreMLDataAsAvailable() throws {
        let directory = try XCTUnwrap(directory)
        let tokenizerDirectory = directory.appendingPathComponent("tokenizer")
        for component in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            try writePackagedModel(named: component, to: directory)
        }
        try writeTokenizerData(to: tokenizerDirectory)
        let adapter = WhisperASRModelAdapter(
            modelDirectory: { _ in directory },
            tokenizerDirectory: { _, _ in tokenizerDirectory },
            compiledModelIsUsable: FakeCoreMLValidation.compiledModelIsUsable,
            packageIsUsable: FakeCoreMLValidation.modelPackageIsUsable,
            download: { _, _ in }
        )

        XCTAssertTrue(adapter.isModelDataAvailable(for: "whisper-large-v3"))
    }

    func testWhisperStructurallyValidatesPackagedCoreMLDataWithoutCompilingIt() throws {
        let adapter = try makeWhisperAdapterWithRealisticPackages()

        XCTAssertTrue(adapter.isModelDataAvailable(for: "whisper-large-v3"))
    }

    func testWhisperRejectsMalformedModelPackageManifest() throws {
        let adapter = try makeWhisperAdapterWithRealisticPackages()
        let directory = try XCTUnwrap(directory)
        try Data("{".utf8).write(
            to: directory.appendingPathComponent("AudioEncoder.mlpackage/Manifest.json")
        )

        XCTAssertFalse(adapter.isModelDataAvailable(for: "whisper-large-v3"))
    }

    func testWhisperRejectsEmptyReferencedModelPackageData() throws {
        let adapter = try makeWhisperAdapterWithRealisticPackages()
        let directory = try XCTUnwrap(directory)
        try Data().write(
            to: directory.appendingPathComponent(
                "AudioEncoder.mlpackage/Data/com.apple.CoreML/weights/weight.bin"
            )
        )

        XCTAssertFalse(adapter.isModelDataAvailable(for: "whisper-large-v3"))
    }

    func testWhisperRejectsMissingRootModelPackageEntry() throws {
        let adapter = try makeWhisperAdapterWithRealisticPackages()
        let directory = try XCTUnwrap(directory)
        let package = directory.appendingPathComponent("AudioEncoder.mlpackage")
        try writePackageManifest(to: package, rootModelIdentifier: "missing")

        XCTAssertFalse(adapter.isModelDataAvailable(for: "whisper-large-v3"))
    }

    func testWhisperRejectsModelPackagePathOutsideDataDirectory() throws {
        let adapter = try makeWhisperAdapterWithRealisticPackages()
        let directory = try XCTUnwrap(directory)
        let package = directory.appendingPathComponent("AudioEncoder.mlpackage")
        try Data("outside".utf8).write(to: directory.appendingPathComponent("outside.mlmodel"))
        try writePackageManifest(to: package, modelPath: "../../outside.mlmodel")

        XCTAssertFalse(adapter.isModelDataAvailable(for: "whisper-large-v3"))
    }

    func testWhisperRequiresUsableTokenizerData() throws {
        let directory = try XCTUnwrap(directory)
        let tokenizerDirectory = directory.appendingPathComponent("tokenizer")
        for component in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            try writeCompiledModel(named: component, to: directory)
        }
        try writeTokenizerData(to: tokenizerDirectory)
        let adapter = WhisperASRModelAdapter(
            modelDirectory: { _ in directory },
            tokenizerDirectory: { _, _ in tokenizerDirectory },
            compiledModelIsUsable: FakeCoreMLValidation.compiledModelIsUsable,
            packageIsUsable: FakeCoreMLValidation.modelPackageIsUsable,
            download: { _, _ in }
        )

        let complete = adapter.isModelDataAvailable(for: "whisper-small")
        try Data(
            #"{"version":"1.0","model":{"type":"BPE","vocab":{"token":0},"merges":[" token"]}}"#.utf8
        ).write(
            to: tokenizerDirectory.appendingPathComponent("tokenizer.json")
        )
        let emptyMergeToken = adapter.isModelDataAvailable(for: "whisper-small")
        try Data(#"{"version":"1.0"}"#.utf8).write(
            to: tokenizerDirectory.appendingPathComponent("tokenizer.json")
        )

        XCTAssertEqual(
            [complete, emptyMergeToken, adapter.isModelDataAvailable(for: "whisper-small")],
            [true, false, false]
        )
    }

    func testLiveAdaptersExposeExpectedModelIDs() {
        let parakeet = ParakeetASRModelAdapter()
        let whisper = WhisperASRModelAdapter()

        XCTAssertEqual(
            [parakeet.modelIDs, whisper.modelIDs],
            [
                ["parakeet-v2", "parakeet-v3"],
                ["whisper-large-v3-turbo", "whisper-small", "whisper-large-v3"],
            ]
        )
    }

    func testLiveAdaptersConstructEnginesWithoutPreparingThem() throws {
        let parakeet = try ParakeetASRModelAdapter().makeEngine(for: "parakeet-v2")
        let whisper = try WhisperASRModelAdapter().makeEngine(for: "whisper-small")

        XCTAssertTrue(parakeet is Transcriber)
        XCTAssertTrue(whisper is WhisperTranscriber)
    }

    func testAdaptersRejectEngineConstructionForUnknownModelIDs() {
        XCTAssertEqual(
            [
                constructionFails {
                    try ParakeetASRModelAdapter().makeEngine(for: "whisper-small")
                },
                constructionFails {
                    try WhisperASRModelAdapter().makeEngine(for: "parakeet-v3")
                },
            ],
            [true, true]
        )
    }

    func testAdaptersWithoutDeletionBoundaryFailExplicitly() async {
        let parakeet = ParakeetASRModelAdapter(
            availability: { _ in true },
            download: { _, _ in }
        )
        let whisper = WhisperASRModelAdapter(
            modelDirectory: { _ in nil },
            download: { _, _ in }
        )

        let errors = [
            await unknownModelError { try await parakeet.removeModelData(for: "parakeet-v2") },
            await unknownModelError { try await whisper.removeModelData(for: "whisper-small") },
        ]

        XCTAssertEqual(errors, [
            "ASR model deletion is unavailable.",
            "ASR model deletion is unavailable.",
        ])
    }

    private func constructionFails(_ construct: () throws -> Transcribing) -> Bool {
        do {
            _ = try construct()
            return false
        } catch {
            return true
        }
    }

    func testParakeetLibraryDownloadUsesStorageOnlyRepositoryPrimitive() async throws {
        let directory = try XCTUnwrap(directory)
        let probe = RepositoryDownloadProbe()

        try await ParakeetASRModelAdapter.downloadFromLibrary(
            .v3
        ) {
            probe.recordProgress($0)
        }
        modelDirectory: { _ in
            directory.appendingPathComponent("parakeet-v3")
        }
        downloadRepository: { repo, parent, variant, progress in
            probe.record(repo: repo.folderName, directory: parent, variant: variant)
            progress(0.4)
        }

        XCTAssertEqual(
            probe.state,
            RepositoryDownloadState(
                repository: "parakeet-tdt-0.6b-v3",
                directory: directory.appendingPathComponent("parakeet-v3")
                    .deletingLastPathComponent(),
                variant: "int8",
                progress: [0.4]
            )
        )
    }

    func testParakeetV2LibraryDownloadUsesItsRepositoryWithoutAPrecisionVariant() async throws {
        let directory = try XCTUnwrap(directory)
        let probe = RepositoryDownloadProbe()
        let modelDirectory: ParakeetASRModelAdapter.ModelDirectory = { _ in
            directory.appendingPathComponent("parakeet-v2")
        }
        let download: ParakeetASRModelAdapter.RepositoryDownload = { repo, parent, variant, progress in
            probe.record(repo: repo.folderName, directory: parent, variant: variant)
            progress(0.25)
        }

        try await ParakeetASRModelAdapter.downloadFromLibrary(
            .v2,
            { probe.recordProgress($0) },
            modelDirectory: modelDirectory,
            downloadRepository: download
        )

        XCTAssertEqual(
            probe.state,
            RepositoryDownloadState(
                repository: "parakeet-tdt-0.6b-v2",
                directory: directory.appendingPathComponent("parakeet-v2")
                    .deletingLastPathComponent(),
                variant: nil,
                progress: [0.25]
            )
        )
    }

    func testParakeetLibraryDownloadFailsWhenTheModelDirectoryCannotResolve() async {
        let modelDirectory: ParakeetASRModelAdapter.ModelDirectory = { _ in nil }
        let download: ParakeetASRModelAdapter.RepositoryDownload = { _, _, _, _ in }
        let error = await unknownModelError {
            try await ParakeetASRModelAdapter.downloadFromLibrary(
                .v3,
                { _ in },
                modelDirectory: modelDirectory,
                downloadRepository: download
            )
        }

        XCTAssertEqual(error, "Couldn't locate the ASR model directory.")
    }

    func testWhisperLibraryDownloadStoresWeightsAndTokenizerWithoutEngineLoading() async throws {
        let directory = try XCTUnwrap(directory)
        let probe = WhisperStorageDownloadProbe()

        try await WhisperASRModelAdapter.downloadFromLibrary(
            "openai_whisper-small"
        ) {
            probe.recordProgress($0)
        } downloadWeights: { variant, progress in
            probe.recordWeights(variant)
            progress(0.5)
            return directory
        } downloadTokenizer: { repository, destination, progress in
            probe.recordTokenizer(repository: repository, destination: destination)
            progress(1)
        }

        XCTAssertEqual(
            probe.state,
            WhisperStorageDownloadState(
                weightsVariant: "openai_whisper-small",
                tokenizerRepository: "openai/whisper-small",
                tokenizerDestination: directory,
                progress: [0.475, 1]
            )
        )
    }

    func testWhisperDownloadMapsCatalogIDAndForwardsProgress() async throws {
        let probe = DownloadProbe<String>()
        let progressProbe = DownloadProbe<Double>()
        let adapter = WhisperASRModelAdapter(
            modelDirectory: { _ in nil },
            download: { variant, progress in
                probe.record(variant)
                progress(0.75)
            }
        )
        try await adapter.downloadModelData(for: "whisper-small") { fraction in
            progressProbe.record(fraction)
        }

        XCTAssertEqual(
            DownloadMapping(mappedValues: probe.values, progress: progressProbe.values),
            DownloadMapping(mappedValues: ["openai_whisper-small"], progress: [0.75])
        )
    }

    func testWhisperDeletionMapsCatalogIDToLibraryVariant() async throws {
        let probe = DownloadProbe<String>()
        let adapter = WhisperASRModelAdapter(
            modelDirectory: { _ in nil },
            download: { _, _ in },
            delete: { probe.record($0) }
        )

        try await adapter.removeModelData(for: "whisper-small")

        XCTAssertEqual(probe.values, ["openai_whisper-small"])
    }

    func testWhisperRejectsUnknownAndWrongFamilyIDs() async {
        let adapter = WhisperASRModelAdapter(
            modelDirectory: { _ in nil },
            download: { _, _ in }
        )

        let error = await unknownModelError {
            try await adapter.downloadModelData(for: "unknown") { _ in }
        }
        let deletionError = await unknownModelError {
            try await adapter.removeModelData(for: "unknown")
        }
        XCTAssertEqual(
            RejectionState(
                unknownIsAvailable: adapter.isModelDataAvailable(for: "unknown"),
                wrongFamilyIsAvailable: adapter.isModelDataAvailable(for: "parakeet-v3"),
                error: error,
                deletionError: deletionError
            ),
            RejectionState(
                unknownIsAvailable: false,
                wrongFamilyIsAvailable: false,
                error: "Unknown ASR model: unknown",
                deletionError: "Unknown ASR model: unknown"
            )
        )
    }

    func testParakeetAdapterMapsCatalogIDToLibraryVariant() async throws {
        let probe = DownloadProbe<ASRModelCatalog.ParakeetVariant>()
        let adapter = ParakeetASRModelAdapter(
            availability: { $0 == .v2 },
            download: { variant, _ in probe.record(variant) }
        )

        try await adapter.downloadModelData(for: "parakeet-v2") { _ in }

        XCTAssertEqual(
            ParakeetMappingState(
                mappedValues: probe.values,
                isAvailable: adapter.isModelDataAvailable(for: "parakeet-v2")
            ),
            ParakeetMappingState(mappedValues: [.v2], isAvailable: true)
        )
    }

    func testParakeetDeletionMapsCatalogIDToLibraryVariant() async throws {
        let probe = DownloadProbe<ASRModelCatalog.ParakeetVariant>()
        let adapter = ParakeetASRModelAdapter(
            availability: { _ in true },
            download: { _, _ in },
            delete: { probe.record($0) }
        )

        try await adapter.removeModelData(for: "parakeet-v2")

        XCTAssertEqual(probe.values, [.v2])
    }

    func testParakeetRequiresEveryLibraryModelArtifact() throws {
        let directory = try XCTUnwrap(directory)
        let requiredArtifacts = [
            "Preprocessor.mlmodelc",
            "Encoder.mlmodelc",
            "Decoder.mlmodelc",
            "JointDecision.mlmodelc",
            "parakeet_vocab.json",
        ]
        for artifact in requiredArtifacts {
            if artifact.hasSuffix(".mlmodelc") {
                try writeCompiledModel(
                    named: String(artifact.dropLast(".mlmodelc".count)),
                    to: directory
                )
            } else {
                try Data(#"{"0":"token"}"#.utf8).write(
                    to: directory.appendingPathComponent(artifact)
                )
            }
        }
        let adapter = ParakeetASRModelAdapter(
            modelDirectory: { $0 == .v2 ? directory : nil },
            modelsExist: { _, _ in true },
            compiledModelIsUsable: FakeCoreMLValidation.compiledModelIsUsable,
            download: { _, _ in }
        )

        let complete = adapter.isModelDataAvailable(for: "parakeet-v2")
        try FileManager.default.removeItem(
            at: directory.appendingPathComponent("JointDecision.mlmodelc")
        )
        XCTAssertEqual(
            [
                complete,
                adapter.isModelDataAvailable(for: "parakeet-v2"),
                adapter.isModelDataAvailable(for: "parakeet-v3"),
            ],
            [true, false, false]
        )
    }

    func testParakeetDoesNotUseArtifactsFromAnotherModelDirectory() throws {
        let directory = try XCTUnwrap(directory)
        let target = directory.appendingPathComponent("target")
        let sibling = directory.appendingPathComponent("sibling")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        for artifact in [
            "Preprocessor.mlmodelc",
            "Encoder.mlmodelc",
            "Decoder.mlmodelc",
            "JointDecision.mlmodelc",
            "parakeet_vocab.json",
        ] {
            if artifact.hasSuffix(".mlmodelc") {
                try writeCompiledModel(
                    named: String(artifact.dropLast(".mlmodelc".count)),
                    to: sibling
                )
            } else {
                try Data(#"{"0":"token"}"#.utf8).write(
                    to: sibling.appendingPathComponent(artifact)
                )
            }
        }
        let adapter = ParakeetASRModelAdapter(
            modelDirectory: { $0 == .v2 ? target : nil },
            modelsExist: { _, _ in true },
            compiledModelIsUsable: FakeCoreMLValidation.compiledModelIsUsable,
            download: { _, _ in }
        )

        XCTAssertFalse(adapter.isModelDataAvailable(for: "parakeet-v2"))
    }

    func testParakeetReportsNonEmptyCorruptModelDataAsUnavailable() throws {
        let directory = try XCTUnwrap(directory)
        for component in ["Preprocessor", "Encoder", "Decoder", "JointDecision"] {
            try writeCompiledModel(named: component, to: directory)
        }
        try Data(#"{"0":"token"}"#.utf8).write(
            to: directory.appendingPathComponent("parakeet_vocab.json")
        )
        let adapter = ParakeetASRModelAdapter(
            modelDirectory: { $0 == .v2 ? directory : nil },
            modelsExist: { _, _ in true },
            download: { _, _ in }
        )

        XCTAssertFalse(adapter.isModelDataAvailable(for: "parakeet-v2"))
    }

    func testParakeetV3AcceptsArrayVocabularyAndRejectsInvalidVocabulary() throws {
        let directory = try XCTUnwrap(directory)
        for component in ["Preprocessor", "Encoder", "Decoder", "JointDecisionv3"] {
            try writeCompiledModel(named: component, to: directory)
        }
        let vocabulary = directory.appendingPathComponent("parakeet_vocab.json")
        try Data(#"{"bad":"token"}"#.utf8).write(to: vocabulary)
        let adapter = ParakeetASRModelAdapter(
            modelDirectory: { $0 == .v3 ? directory : nil },
            modelsExist: { _, _ in true },
            compiledModelIsUsable: FakeCoreMLValidation.compiledModelIsUsable,
            download: { _, _ in }
        )

        let invalidVocabulary = adapter.isModelDataAvailable(for: "parakeet-v3")
        try Data(#"["token"]"#.utf8).write(to: vocabulary)

        XCTAssertEqual(
            [invalidVocabulary, adapter.isModelDataAvailable(for: "parakeet-v3")],
            [false, true]
        )
    }

    func testParakeetRejectsUnknownAndWrongFamilyIDs() async {
        let adapter = ParakeetASRModelAdapter(
            availability: { _ in true },
            download: { _, _ in }
        )

        let error = await unknownModelError {
            try await adapter.downloadModelData(for: "whisper-small") { _ in }
        }
        let deletionError = await unknownModelError {
            try await adapter.removeModelData(for: "whisper-small")
        }
        XCTAssertEqual(
            RejectionState(
                unknownIsAvailable: adapter.isModelDataAvailable(for: "unknown"),
                wrongFamilyIsAvailable: adapter.isModelDataAvailable(for: "whisper-small"),
                error: error,
                deletionError: deletionError
            ),
            RejectionState(
                unknownIsAvailable: false,
                wrongFamilyIsAvailable: false,
                error: "Unknown ASR model: whisper-small",
                deletionError: "Unknown ASR model: whisper-small"
            )
        )
    }

    // MARK: - Streaming ASR models (ADR-0009)

    func testStreamingReportsCompleteEouDataAsAvailable() throws {
        let directory = try XCTUnwrap(directory)
        try writeEouModelData(to: directory)
        let adapter = makeStreamingAdapter(directory: directory)

        XCTAssertTrue(adapter.isModelDataAvailable(for: "parakeet-eou-320"))
    }

    func testStreamingRequiresEveryEouArtifact() throws {
        let directory = try XCTUnwrap(directory)
        try writeEouModelData(to: directory)
        let adapter = makeStreamingAdapter(directory: directory)

        let complete = adapter.isModelDataAvailable(for: "parakeet-eou-320")
        try FileManager.default.removeItem(
            at: directory.appendingPathComponent("joint_decision.mlmodelc")
        )

        XCTAssertEqual(
            [complete, adapter.isModelDataAvailable(for: "parakeet-eou-320")],
            [true, false]
        )
    }

    func testStreamingRejectsEouDataWithoutAUsableVocabulary() throws {
        let directory = try XCTUnwrap(directory)
        try writeEouModelData(to: directory)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("vocab.json"))
        let adapter = makeStreamingAdapter(directory: directory)

        XCTAssertFalse(adapter.isModelDataAvailable(for: "parakeet-eou-320"))
    }

    func testStreamingReportsUnresolvableModelDirectoryAsUnavailable() {
        let adapter = StreamingASRModelAdapter(modelDirectory: { _ in nil }, download: { _, _ in })

        XCTAssertFalse(adapter.isModelDataAvailable(for: "parakeet-eou-320"))
    }

    /// The pinned downloader re-appends `parakeet-eou-streaming/320ms`, so the
    /// destination it is handed is the shared models root; passing the variant's
    /// parent — as the TDT checkpoints do — would nest the tier twice.
    func testStreamingLibraryDownloadTargetsTheEouRepositoryAtTheSharedRoot() async throws {
        let probe = RepositoryDownloadProbe()
        let download: StreamingASRModelAdapter.RepositoryDownload = { repo, root, variant, progress in
            probe.record(repo: repo.folderName, directory: root, variant: variant)
            progress(0.6)
        }

        try await StreamingASRModelAdapter.downloadFromLibrary(
            .parakeetEou320,
            { probe.recordProgress($0) },
            downloadRepository: download
        )

        XCTAssertEqual(
            probe.state,
            RepositoryDownloadState(
                repository: "parakeet-eou-streaming/320ms",
                directory: ASRModelStore.streamingDownloadRoot(),
                variant: nil,
                progress: [0.6]
            )
        )
    }

    func testStreamingDeletionMapsCatalogIDToLibraryVariant() async throws {
        let probe = DownloadProbe<ASRModelCatalog.StreamingVariant>()
        let adapter = StreamingASRModelAdapter(
            modelDirectory: { _ in nil },
            availability: { _ in true },
            download: { _, _ in },
            delete: { probe.record($0) }
        )

        try await adapter.removeModelData(for: "parakeet-eou-320")

        XCTAssertEqual(probe.values, [.parakeetEou320])
    }

    func testStreamingRejectsUnknownAndWrongFamilyIDs() async {
        let adapter = StreamingASRModelAdapter(
            modelDirectory: { _ in nil },
            availability: { _ in true },
            download: { _, _ in }
        )

        let error = await unknownModelError {
            try await adapter.downloadModelData(for: "parakeet-v3") { _ in }
        }
        let deletionError = await unknownModelError {
            try await adapter.removeModelData(for: "parakeet-v3")
        }
        XCTAssertEqual(
            RejectionState(
                unknownIsAvailable: adapter.isModelDataAvailable(for: "unknown"),
                wrongFamilyIsAvailable: adapter.isModelDataAvailable(for: "parakeet-v3"),
                error: error,
                deletionError: deletionError
            ),
            RejectionState(
                unknownIsAvailable: false,
                wrongFamilyIsAvailable: false,
                error: "Unknown ASR model: parakeet-v3",
                deletionError: "Unknown ASR model: parakeet-v3"
            )
        )
    }

    /// The capability Dictation acts on is the engine's type, so EOU's engine has
    /// to answer `StreamCapableTranscribing` — the catalog flag alone is copy.
    func testStreamingEngineIsStreamCapable() throws {
        let adapter = StreamingASRModelAdapter(
            modelDirectory: { _ in URL(fileURLWithPath: "/tmp/eou") },
            availability: { _ in true },
            download: { _, _ in }
        )

        XCTAssertTrue(
            try adapter.makeEngine(for: "parakeet-eou-320") is any StreamCapableTranscribing
        )
    }

    func testStreamingEngineLoadsItsVariantFromTheModelDirectory() async throws {
        let directory = try XCTUnwrap(directory)
        let probe = DownloadProbe<StreamingManagerRequest>()
        let manager = FakeStreamingASRManager()
        let adapter = StreamingASRModelAdapter(
            modelDirectory: { _ in directory },
            availability: { _ in true },
            download: { _, _ in },
            makeManager: { variant, directory in
                probe.record(StreamingManagerRequest(variant: variant, directory: directory))
                return manager
            }
        )

        try await adapter.makeEngine(for: "parakeet-eou-320").prepare()

        XCTAssertEqual(
            probe.values,
            [StreamingManagerRequest(variant: .parakeetEou320, directory: directory)]
        )
    }

    func testStreamingEngineFailsWhenTheModelDirectoryCannotResolve() {
        let adapter = StreamingASRModelAdapter(
            modelDirectory: { _ in nil },
            availability: { _ in true },
            download: { _, _ in }
        )

        XCTAssertThrowsError(try adapter.makeEngine(for: "parakeet-eou-320")) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Couldn't locate the ASR model directory."
            )
        }
    }

    // MARK: - Nemotron 560, the Apple-silicon Streaming ASR model

    func testStreamingReportsCompleteNemotronDataAsAvailable() throws {
        let directory = try XCTUnwrap(directory)
        try writeNemotronModelData(to: directory)
        let adapter = makeStreamingAdapter(directory: directory)

        XCTAssertTrue(adapter.isModelDataAvailable(for: "nemotron-560"))
    }

    /// Nemotron's int8 encoder is the one artifact the library keeps in a nested
    /// folder, so a validator that only looked beside the other models would call
    /// an incomplete download usable.
    func testStreamingRequiresNemotronsNestedInt8Encoder() throws {
        let directory = try XCTUnwrap(directory)
        try writeNemotronModelData(to: directory)
        let adapter = makeStreamingAdapter(directory: directory)

        let complete = adapter.isModelDataAvailable(for: "nemotron-560")
        try FileManager.default.removeItem(at: directory.appendingPathComponent("encoder"))

        XCTAssertEqual(
            [complete, adapter.isModelDataAvailable(for: "nemotron-560")],
            [true, false]
        )
    }

    func testStreamingRejectsNemotronDataWithoutAUsableTokenizer() throws {
        let directory = try XCTUnwrap(directory)
        try writeNemotronModelData(to: directory)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("tokenizer.json"))
        let adapter = makeStreamingAdapter(directory: directory)

        XCTAssertFalse(adapter.isModelDataAvailable(for: "nemotron-560"))
    }

    func testNemotronIsUnavailableOnAnIntelMac() throws {
        let directory = try XCTUnwrap(directory)
        try writeNemotronModelData(to: directory)

        XCTAssertFalse(
            makeStreamingAdapter(directory: directory, hostIsAppleSilicon: false)
                .isModelDataAvailable(for: "nemotron-560")
        )
    }

    /// The requirement follows the engine, not the family: EOU runs anywhere.
    func testEouStaysAvailableOnAnIntelMac() throws {
        let directory = try XCTUnwrap(directory)
        try writeEouModelData(to: directory)

        XCTAssertTrue(
            makeStreamingAdapter(directory: directory, hostIsAppleSilicon: false)
                .isModelDataAvailable(for: "parakeet-eou-320")
        )
    }

    func testNemotronDownloadIsRefusedOnAnIntelMac() async {
        let probe = DownloadProbe<ASRModelCatalog.StreamingVariant>()
        let adapter = StreamingASRModelAdapter(
            modelDirectory: { _ in nil },
            availability: { _ in true },
            download: { variant, _ in probe.record(variant) },
            hostIsAppleSilicon: false
        )

        let error = await unknownModelError {
            try await adapter.downloadModelData(for: "nemotron-560") { _ in }
        }

        XCTAssertEqual(
            DownloadRefusal(error: error, attempted: probe.values),
            DownloadRefusal(error: "Nemotron 560 needs a Mac with Apple silicon.", attempted: [])
        )
    }

    func testNemotronEngineIsRefusedOnAnIntelMac() {
        let adapter = StreamingASRModelAdapter(
            modelDirectory: { _ in URL(fileURLWithPath: "/tmp/nemotron") },
            availability: { _ in true },
            download: { _, _ in },
            hostIsAppleSilicon: false
        )

        XCTAssertThrowsError(try adapter.makeEngine(for: "nemotron-560")) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Nemotron 560 needs a Mac with Apple silicon."
            )
        }
    }

    func testStreamingLibraryDownloadTargetsTheNemotronRepositoryAtTheSharedRoot() async throws {
        let probe = RepositoryDownloadProbe()
        let download: StreamingASRModelAdapter.RepositoryDownload = { repo, root, variant, progress in
            probe.record(repo: repo.folderName, directory: root, variant: variant)
            progress(0.4)
        }

        try await StreamingASRModelAdapter.downloadFromLibrary(
            .nemotron560,
            { probe.recordProgress($0) },
            downloadRepository: download
        )

        XCTAssertEqual(
            probe.state,
            RepositoryDownloadState(
                repository: "nemotron-streaming/560ms",
                directory: ASRModelStore.streamingDownloadRoot(),
                variant: nil,
                progress: [0.4]
            )
        )
    }

    func testStreamingEngineLoadsNemotronFromItsModelDirectory() async throws {
        let directory = try XCTUnwrap(directory)
        let probe = DownloadProbe<StreamingManagerRequest>()
        let manager = FakeStreamingASRManager()
        let adapter = StreamingASRModelAdapter(
            modelDirectory: { _ in directory },
            availability: { _ in true },
            download: { _, _ in },
            makeManager: { variant, directory in
                probe.record(StreamingManagerRequest(variant: variant, directory: directory))
                return manager
            }
        )

        try await adapter.makeEngine(for: "nemotron-560").prepare()

        XCTAssertEqual(
            probe.values,
            [StreamingManagerRequest(variant: .nemotron560, directory: directory)]
        )
    }

    func testNemotronDeletionMapsCatalogIDToLibraryVariant() async throws {
        let probe = DownloadProbe<ASRModelCatalog.StreamingVariant>()
        let adapter = StreamingASRModelAdapter(
            modelDirectory: { _ in nil },
            availability: { _ in true },
            download: { _, _ in },
            delete: { probe.record($0) }
        )

        try await adapter.removeModelData(for: "nemotron-560")

        XCTAssertEqual(probe.values, [.nemotron560])
    }

    private func makeStreamingAdapter(
        directory: URL,
        hostIsAppleSilicon: Bool = true
    ) -> StreamingASRModelAdapter {
        StreamingASRModelAdapter(
            modelDirectory: { _ in directory },
            compiledModelIsUsable: FakeCoreMLValidation.compiledModelIsUsable,
            download: { _, _ in },
            hostIsAppleSilicon: hostIsAppleSilicon
        )
    }

    private func writeEouModelData(to directory: URL) throws {
        for component in ["streaming_encoder", "decoder", "joint_decision"] {
            try writeCompiledModel(named: component, to: directory)
        }
        try Data(#"{"0":"token"}"#.utf8).write(
            to: directory.appendingPathComponent("vocab.json")
        )
    }

    /// A complete Nemotron download as the pinned manager loads it: the encoder
    /// nested under `encoder/`, and neither the fused `decoder_joint` nor
    /// `metadata.json`, both of which the manager reads only when present.
    private func writeNemotronModelData(to directory: URL) throws {
        for component in ["preprocessor", "decoder", "joint"] {
            try writeCompiledModel(named: component, to: directory)
        }
        let encoder = directory.appendingPathComponent("encoder")
        try FileManager.default.createDirectory(at: encoder, withIntermediateDirectories: true)
        try writeCompiledModel(named: "encoder_int8", to: encoder)
        try Data(#"{"0":"token"}"#.utf8).write(
            to: directory.appendingPathComponent("tokenizer.json")
        )
    }

    private func unknownModelError(
        operation: () async throws -> Void
    ) async -> String? {
        do {
            try await operation()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func writeCompiledModel(named name: String, to directory: URL) throws {
        let bundle = directory.appendingPathComponent("\(name).mlmodelc")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try Data("program".utf8).write(to: bundle.appendingPathComponent("model.mil"))
        try Data("compiled".utf8).write(to: bundle.appendingPathComponent("coremldata.bin"))
        try Data(#"{"model":"compiled"}"#.utf8).write(
            to: bundle.appendingPathComponent("metadata.json")
        )
    }

    private func makeWhisperAdapterWithRealisticPackages() throws -> WhisperASRModelAdapter {
        let directory = try XCTUnwrap(directory)
        let tokenizerDirectory = directory.appendingPathComponent("tokenizer")
        for component in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            try writeRealisticPackagedModel(named: component, to: directory)
        }
        try writeTokenizerData(to: tokenizerDirectory)
        return WhisperASRModelAdapter(
            modelDirectory: { _ in directory },
            tokenizerDirectory: { _, _ in tokenizerDirectory },
            download: { _, _ in }
        )
    }

    private func writePackagedModel(named name: String, to directory: URL) throws {
        let package = directory.appendingPathComponent("\(name).mlpackage")
        let model = package.appendingPathComponent("Data/com.apple.CoreML/model.mlmodel")
        try FileManager.default.createDirectory(
            at: model.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("model".utf8).write(to: model)
        try Data(#"{"rootModelIdentifier":"model"}"#.utf8).write(
            to: package.appendingPathComponent("Manifest.json")
        )
    }

    private func writeRealisticPackagedModel(named name: String, to directory: URL) throws {
        let package = directory.appendingPathComponent("\(name).mlpackage")
        let model = package.appendingPathComponent("Data/com.apple.CoreML/model.mlmodel")
        let weights = package.appendingPathComponent("Data/com.apple.CoreML/weights/weight.bin")
        try FileManager.default.createDirectory(
            at: model.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: weights.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("model specification".utf8).write(to: model)
        try Data("weights".utf8).write(to: weights)
        try writePackageManifest(to: package)
    }

    private func writePackageManifest(
        to package: URL,
        rootModelIdentifier: String = "model",
        modelPath: String = "com.apple.CoreML/model.mlmodel"
    ) throws {
        let manifest: [String: Any] = [
            "fileFormatVersion": "1.0.0",
            "itemInfoEntries": [
                "model": [
                    "author": "com.apple.CoreML",
                    "description": "CoreML Model Specification",
                    "name": "model.mlmodel",
                    "path": modelPath,
                ],
                "weights": [
                    "author": "com.apple.CoreML",
                    "description": "CoreML Model Weights",
                    "name": "weights",
                    "path": "com.apple.CoreML/weights",
                ],
            ],
            "rootModelIdentifier": rootModelIdentifier,
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: package.appendingPathComponent("Manifest.json")
        )
    }

    private func writeTokenizerData(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"model_type":"whisper"}"#.utf8).write(
            to: directory.appendingPathComponent("config.json")
        )
        try Data(#"{"tokenizer_class":"WhisperTokenizer"}"#.utf8).write(
            to: directory.appendingPathComponent("tokenizer_config.json")
        )
        try Data(
            #"{"version":"1.0","model":{"type":"BPE","vocab":{"token":0},"merges":[["t","o"]]}}"#.utf8
        ).write(
            to: directory.appendingPathComponent("tokenizer.json")
        )
    }
}

private struct RepositoryDownloadState: Equatable {
    let repository: String?
    let directory: URL?
    let variant: String?
    let progress: [Double]
}

private final class RepositoryDownloadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var repository: String?
    private var directory: URL?
    private var variant: String?
    private var progress: [Double] = []

    var state: RepositoryDownloadState {
        lock.withLock {
            RepositoryDownloadState(
                repository: repository,
                directory: directory,
                variant: variant,
                progress: progress
            )
        }
    }

    func record(repo: String, directory: URL, variant: String?) {
        lock.withLock {
            repository = repo
            self.directory = directory
            self.variant = variant
        }
    }

    func recordProgress(_ fraction: Double) {
        lock.withLock { progress.append(fraction) }
    }
}

private struct WhisperStorageDownloadState: Equatable {
    let weightsVariant: String?
    let tokenizerRepository: String?
    let tokenizerDestination: URL?
    let progress: [Double]
}

private final class WhisperStorageDownloadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var weightsVariant: String?
    private var tokenizerRepository: String?
    private var tokenizerDestination: URL?
    private var progress: [Double] = []

    var state: WhisperStorageDownloadState {
        lock.withLock {
            WhisperStorageDownloadState(
                weightsVariant: weightsVariant,
                tokenizerRepository: tokenizerRepository,
                tokenizerDestination: tokenizerDestination,
                progress: progress
            )
        }
    }

    func recordWeights(_ variant: String) {
        lock.withLock { weightsVariant = variant }
    }

    func recordTokenizer(repository: String, destination: URL) {
        lock.withLock {
            tokenizerRepository = repository
            tokenizerDestination = destination
        }
    }

    func recordProgress(_ fraction: Double) {
        lock.withLock { progress.append(fraction) }
    }
}

private enum FakeCoreMLValidation {
    static let compiledModelIsUsable: @Sendable (URL) -> Bool = { url in
        (try? Data(contentsOf: url.appendingPathComponent("model.mil")))
            == Data("program".utf8)
            && (try? Data(contentsOf: url.appendingPathComponent("coremldata.bin")))
            == Data("compiled".utf8)
            && (try? Data(contentsOf: url.appendingPathComponent("metadata.json")))
            == Data(#"{"model":"compiled"}"#.utf8)
    }

    static let modelPackageIsUsable: @Sendable (URL) -> Bool = { url in
        (try? Data(contentsOf: url.appendingPathComponent(
            "Data/com.apple.CoreML/model.mlmodel"
        ))) == Data("model".utf8)
            && (try? Data(contentsOf: url.appendingPathComponent("Manifest.json")))
            == Data(#"{"rootModelIdentifier":"model"}"#.utf8)
    }
}

private struct DownloadMapping<Value: Equatable>: Equatable {
    let mappedValues: [Value]
    let progress: [Double]
}

private struct DownloadRefusal: Equatable {
    let error: String?
    let attempted: [ASRModelCatalog.StreamingVariant]
}

private struct StreamingManagerRequest: Equatable {
    let variant: ASRModelCatalog.StreamingVariant
    let directory: URL
}

private struct ParakeetMappingState: Equatable {
    let mappedValues: [ASRModelCatalog.ParakeetVariant]
    let isAvailable: Bool
}

private struct RejectionState: Equatable {
    let unknownIsAvailable: Bool
    let wrongFamilyIsAvailable: Bool
    let error: String?
    let deletionError: String?
}

private final class DownloadProbe<Value>: @unchecked Sendable {
    var values: [Value] {
        lock.withLock { _values }
    }

    private let lock = NSLock()
    private var _values: [Value] = []

    func record(_ value: Value) {
        lock.withLock { _values.append(value) }
    }
}
