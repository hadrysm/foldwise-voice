// The dispatching `Transcribing` (ADR-0005) driven through the seam the
// Pipeline uses: it delegates the transcribe-stage surface to the engine the
// current `asr_model` selection resolves to, and rebuilds that engine when the
// selection changes (ADR-0006 propagation). Engines are injected as
// `FakeTranscriber`s via the factory, so no real Parakeet/Whisper model loads.

import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class TranscriberDispatcherTests: XCTestCase {
    /// XCTest instantiates the case once per test method, so each test gets
    /// its own scratch directory.
    private let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("foldwise-tests-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    private func makeConfig() -> Config {
        Config.defaultConfig(path: dir.appendingPathComponent("modes.json"))
    }

    func testTranscribeDelegatesToTheEngine() async throws {
        let fake = FakeTranscriber()
        fake.result = .success("hello world")
        let dispatcher = TranscriberDispatcher(config: makeConfig()) { _ in fake }

        let text = try await dispatcher.transcribe([0.1, 0.2, 0.3])

        XCTAssertEqual(text, "hello world")
        XCTAssertEqual(fake.received, [[0.1, 0.2, 0.3]])
    }

    func testWarmupForwardsToTheEngine() {
        let fake = FakeTranscriber()
        let dispatcher = TranscriberDispatcher(config: makeConfig()) { _ in fake }

        dispatcher.warmup()

        XCTAssertEqual(fake.warmupCount, 1)
    }

    func testReadyReflectsTheEngine() {
        let fake = FakeTranscriber()
        fake.ready = false
        let dispatcher = TranscriberDispatcher(config: makeConfig()) { _ in fake }

        XCTAssertFalse(dispatcher.ready)
        fake.ready = true
        XCTAssertTrue(dispatcher.ready)
    }

    func testOnLoadingFromTheEngineReachesTheDispatchersSink() {
        let fake = FakeTranscriber()
        let dispatcher = TranscriberDispatcher(config: makeConfig()) { _ in fake }
        var loadings: [Bool] = []
        dispatcher.onLoading = { loadings.append($0) }

        fake.onLoading?(true)
        fake.onLoading?(false)

        XCTAssertEqual(loadings, [true, false])
    }

    func testOnDownloadProgressFromTheEngineReachesTheDispatchersSink() {
        let fake = FakeTranscriber()
        let dispatcher = TranscriberDispatcher(config: makeConfig()) { _ in fake }
        var fractions: [Double] = []
        dispatcher.onDownloadProgress = { fractions.append($0) }

        fake.onDownloadProgress?(0.25)
        fake.onDownloadProgress?(1.0)

        XCTAssertEqual(fractions, [0.25, 1.0])
    }

    func testDownloadProgressSinkIsRewiredOntoTheSwappedEngine() throws {
        let config = makeConfig()
        var built: [FakeTranscriber] = []
        let dispatcher = TranscriberDispatcher(config: config) { _ in
            let fake = FakeTranscriber()
            built.append(fake)
            return fake
        }
        var fractions: [Double] = []
        dispatcher.onDownloadProgress = { fractions.append($0) }

        config.setASRModel("whisper-large-v3-turbo")
        try config.saveAndNotify()
        built.last?.onDownloadProgress?(0.75)

        XCTAssertEqual(fractions, [0.75], "progress from the swapped-in engine still reaches the sink")
    }

    func testResolvesTheParakeetEngineForAnUnknownFossilID() {
        // A stored MLX fossil resolves to Parakeet without being rewritten.
        let config = Config.defaultConfig(path: dir.appendingPathComponent("modes.json"))
        config.setASRModel("mlx-community/whisper-large-v3-turbo")
        var engines: [ASRModelCatalog.Engine] = []
        _ = TranscriberDispatcher(config: config) { engine in
            engines.append(engine)
            return FakeTranscriber()
        }

        XCTAssertEqual(engines, [.parakeet(version: .v3)])
    }

    func testSelectionChangeRebuildsAndSwapsTheEngine() async throws {
        let config = makeConfig()
        var built: [FakeTranscriber] = []
        let dispatcher = TranscriberDispatcher(config: config) { _ in
            let fake = FakeTranscriber()
            fake.result = .success("from-engine-\(built.count)")
            built.append(fake)
            return fake
        }
        XCTAssertEqual(built.count, 1, "the initial engine is built at init")

        config.setASRModel("parakeet-different")
        try config.saveAndNotify()

        XCTAssertEqual(built.count, 2, "a selection change rebuilds the engine")
        let text = try await dispatcher.transcribe([0.1])
        XCTAssertEqual(text, "from-engine-1", "transcription now runs on the swapped-in engine")
    }

    func testReleasesTheOldEngineBeforeBuildingTheNext() throws {
        // Drop-before-load (ADR-0005): the previously-loaded engine must be
        // released before the next is constructed, so a switch never holds two
        // models resident. Each fake logs its build (via the factory) and its
        // deinit, so the interleaving pins the ordering with no real models.
        let config = makeConfig()
        let log = EngineLifecycleLog()
        var built = 0
        let dispatcher = TranscriberDispatcher(config: config) { _ in
            let index = built
            built += 1
            log.append("build-\(index)")
            return LifecycleFake(index: index, log: log)
        }

        config.setASRModel("whisper-large-v3-turbo")
        try config.saveAndNotify()

        XCTAssertEqual(log.events, ["build-0", "release-0", "build-1"])
        _ = dispatcher // keep alive so engine-1 isn't released before the assert
    }

    func testUnrelatedChangeDoesNotRebuildTheEngine() throws {
        let config = makeConfig()
        var buildCount = 0
        _ = TranscriberDispatcher(config: config) { _ in
            buildCount += 1
            return FakeTranscriber()
        }
        XCTAssertEqual(buildCount, 1)

        config.hotkey = "cmd_r"
        try config.saveAndNotify()

        XCTAssertEqual(buildCount, 1, "a non-ASR change leaves the engine untouched")
    }
}

/// Ordered log of engine build/release events, shared between the factory and
/// the fakes it produces, so a test can assert drop-before-load interleaving.
private final class EngineLifecycleLog {
    private(set) var events: [String] = []
    func append(_ event: String) {
        events.append(event)
    }
}

/// A `Transcribing` that records its own deallocation, so a test can prove the
/// dispatcher released it (freeing its would-be model) before building the next.
private final class LifecycleFake: Transcribing {
    var ready = true
    var onLoading: ((Bool) -> Void)?
    var onDownloadProgress: ((Double) -> Void)?
    private let index: Int
    private let log: EngineLifecycleLog

    init(index: Int, log: EngineLifecycleLog) {
        self.index = index
        self.log = log
    }

    deinit {
        log.append("release-\(index)")
    }

    func warmup() {}
    func prepare() async throws {}
    func transcribe(_: [Float]) async throws -> String {
        ""
    }
}
