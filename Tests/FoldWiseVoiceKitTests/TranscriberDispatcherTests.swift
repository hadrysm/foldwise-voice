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

    func testResolvesTheParakeetEngineForAnUnknownFossilID() {
        // A stored MLX fossil resolves to Parakeet without being rewritten.
        let config = Config.defaultConfig(path: dir.appendingPathComponent("modes.json"))
        config.setASRModel("mlx-community/whisper-large-v3-turbo")
        var engines: [ASRModelCatalog.Engine] = []
        _ = TranscriberDispatcher(config: config) { engine in
            engines.append(engine)
            return FakeTranscriber()
        }

        XCTAssertEqual(engines, [.parakeet])
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
