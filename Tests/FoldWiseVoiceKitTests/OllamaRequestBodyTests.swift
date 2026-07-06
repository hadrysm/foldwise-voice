// Pins the Polish request body: `temperature` and `max_tokens` must be sent as
// TOP-LEVEL fields for the OpenAI-compatible /v1/chat/completions endpoint,
// which silently ignores the nested `options` object (Ollama's native
// /api/chat convention). Before this, temperature: 0 lived inside `options` and
// never applied, so Polish ran at Ollama's default temperature — a driver of
// the off-task failures. Mirrors OllamaDeleteOutcomeTests: drives the client's
// pure builder directly with no network.

import XCTest
@testable import FoldWiseVoiceKit

final class OllamaRequestBodyTests: XCTestCase {
    private func body(maxTokens: Int = 256) -> [String: Any] {
        OllamaClient.chatRequestBody(
            model: "qwen2.5:3b",
            system: "Clean up this dictated text.",
            user: "we should meet at noon",
            maxTokens: maxTokens
        )
    }

    func testTemperatureIsTopLevelZero() {
        XCTAssertEqual(body()["temperature"] as? Int, 0)
    }

    func testMaxTokensIsTopLevelAndThreaded() {
        XCTAssertEqual(body(maxTokens: 512)["max_tokens"] as? Int, 512)
    }

    func testNoOptionsObjectIsSent() {
        XCTAssertNil(body()["options"])
    }

    func testMessagesCarrySystemThenUser() {
        let messages = body()["messages"] as? [[String: String]]
        XCTAssertEqual(messages?.first?["role"], "system")
        XCTAssertEqual(messages?.first?["content"], "Clean up this dictated text.")
        XCTAssertEqual(messages?.last?["role"], "user")
        XCTAssertEqual(messages?.last?["content"], "we should meet at noon")
    }

    /// The whole point of the pure builder: the payload must survive
    /// JSONSerialization exactly as the endpoint will receive it.
    func testBodySerializesToJSON() throws {
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body()))
    }
}
