// Pins the pure delete-outcome mapping: given the HTTP status Ollama returns
// for DELETE /api/delete, the optional error a user would see. The 404 rule is
// the one non-obvious behavior — the model is already gone (e.g. removed via
// the CLI), which is exactly the goal state, so it maps to success, not an
// error. Mirrors OllamaSanitizeTests: drives the client's pure helper directly
// with no network.

import XCTest
@testable import FoldWiseVoiceKit

final class OllamaDeleteOutcomeTests: XCTestCase {
    func testSuccessStatusMapsToNoError() {
        XCTAssertNil(OllamaClient.deleteOutcome(status: 200))
    }

    func testAlreadyGoneStatusMapsToNoError() {
        XCTAssertNil(OllamaClient.deleteOutcome(status: 404))
    }

    func testServerErrorStatusMapsToError() {
        XCTAssertNotNil(OllamaClient.deleteOutcome(status: 500))
    }
}
