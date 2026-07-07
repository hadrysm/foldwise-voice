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
}
