// Id → entry resolution for the ASR catalog, mirroring how `ModelCatalog`
// resolves Ollama model names. The catalog is our own stable id vocabulary
// (ADR-0006), so an old `mlx-community/...` fossil id resolves to no entry and
// falls back to the Parakeet engine.

import XCTest
@testable import FoldWiseVoiceKit

final class ASRModelCatalogTests: XCTestCase {
    func testResolvesKnownParakeetID() {
        let entry = ASRModelCatalog.entry(for: "parakeet-v3")
        XCTAssertEqual(entry?.id, "parakeet-v3")
        XCTAssertEqual(entry?.engine, .parakeet)
    }

    func testDefaultIDIsAKnownEntry() {
        XCTAssertNotNil(ASRModelCatalog.entry(for: ASRModelCatalog.defaultID))
    }

    func testUnknownFossilIDResolvesToNoEntry() {
        XCTAssertNil(ASRModelCatalog.entry(for: "mlx-community/whisper-large-v3-turbo"))
    }

    func testUnknownIDFallsBackToParakeetEngine() {
        XCTAssertEqual(
            ASRModelCatalog.engine(forSelected: "mlx-community/whisper-large-v3-turbo"),
            .parakeet
        )
    }

    func testKnownIDResolvesToItsEngine() {
        XCTAssertEqual(ASRModelCatalog.engine(forSelected: "parakeet-v3"), .parakeet)
    }

    func testResolvesWhisperTurboToItsEngineAndVariant() {
        let entry = ASRModelCatalog.entry(for: "whisper-large-v3-turbo")
        XCTAssertEqual(entry?.id, "whisper-large-v3-turbo")
        XCTAssertEqual(
            entry?.engine,
            .whisper(variant: "openai_whisper-large-v3-v20240930_turbo_632MB")
        )
    }

    func testWhisperEngineResolvesFromSelectedID() {
        XCTAssertEqual(
            ASRModelCatalog.engine(forSelected: "whisper-large-v3-turbo"),
            .whisper(variant: "openai_whisper-large-v3-v20240930_turbo_632MB")
        )
    }

    func testCatalogListsParakeetAndWhisperTurbo() {
        XCTAssertEqual(ASRModelCatalog.entries.map(\.id), ["parakeet-v3", "whisper-large-v3-turbo"])
    }

    // MARK: - download outcome (pure, mirrors OllamaDeleteOutcomeTests)

    private var whisper: ASRModelCatalog.Entry {
        // Force-unwrap: the entry is a compile-time-constant catalog member.
        // swiftlint:disable:next force_unwrapping
        ASRModelCatalog.entry(for: "whisper-large-v3-turbo")!
    }

    func testDownloadSuccessMapsToNoError() {
        XCTAssertNil(ASRModelCatalog.downloadError(for: whisper, failure: nil))
    }

    func testEmptyFailureMapsToNoError() {
        XCTAssertNil(ASRModelCatalog.downloadError(for: whisper, failure: ""))
    }

    func testFailureMapsToNamedError() {
        let message = ASRModelCatalog.downloadError(for: whisper, failure: "network down")
        XCTAssertEqual(message, "Couldn't download Whisper large-v3-turbo: network down")
    }
}
