// Pins the native `/api/chat` request body. Native chat is required because its
// response separates model load, prompt evaluation, and generation timing.
// Mirrors OllamaDeleteOutcomeTests: drives the client's pure builder directly
// with no network.

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

    func testNativeOptionsSetTemperatureToZero() {
        let options = body()["options"] as? [String: Any]
        XCTAssertEqual(options?["temperature"] as? Int, 0)
    }

    func testNativeOptionsThreadTheGenerationLimit() {
        let options = body(maxTokens: 512)["options"] as? [String: Any]
        XCTAssertEqual(options?["num_predict"] as? Int, 512)
    }

    func testPolishKeepsTheModelResidentForTenMinutes() {
        XCTAssertEqual(body()["keep_alive"] as? String, "10m")
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
