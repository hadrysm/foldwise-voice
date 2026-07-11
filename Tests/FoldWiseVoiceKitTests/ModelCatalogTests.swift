import XCTest
@testable import FoldWiseVoiceKit

final class ModelCatalogTests: XCTestCase {
    func testCatalogListsTheCuratedRecommendations() {
        XCTAssertEqual(
            ModelCatalog.entries.map(\.id),
            [
                "gemma3:1b", "llama3.2:1b", "llama3.2:3b", "qwen2.5:3b", "gemma2:2b",
                "phi4-mini:3.8b", "gemma3:4b", "qwen2.5:7b", "llama3.1:8b", "mistral:7b",
            ]
        )
    }

    func testExactMatchKeepsItsSizeTierGuidance() {
        let entry = ModelCatalog.entry(for: "llama3.2:3b")

        XCTAssertEqual(entry?.name, "llama3.2:3b")
    }

    func testUnrecognizedVariantUsesFamilyGuidance() {
        let entry = ModelCatalog.entry(for: "mistral:instruct")

        XCTAssertEqual(entry?.name, "mistral:7b")
    }
}
