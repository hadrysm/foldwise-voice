import Foundation
import XCTest
@testable import FoldWiseVoiceKit

final class OllamaClientHTTPBehaviorTests: XCTestCase {
    private let transcript = "we should meet at noon"

    func testPolishReturnsValidOutput() async {
        let transport = FakeOllamaTransport(
            data: Data(#"{"choices":[{"message":{"content":"We should meet at noon."}}]}"#.utf8),
            status: 200
        )

        let result = await OllamaClient(transport: transport).polish(
            "we should meet at noon",
            model: "qwen2.5:3b",
            systemPrompt: nil,
            vocab: [],
            expands: false
        )

        XCTAssertEqual(result, "We should meet at noon.")
    }

    func testPolishReturnsRawTranscriptWhenTransportFails() async {
        let transport = FakeOllamaTransport(status: 200, dataError: .unreachable)

        let result = await polish(using: transport)

        XCTAssertEqual(result, transcript)
    }

    func testPolishReturnsRawTranscriptForUnsuccessfulStatus() async {
        let transport = FakeOllamaTransport(data: Data(#"{"error":"missing model"}"#.utf8), status: 404)

        let result = await polish(using: transport)

        XCTAssertEqual(result, transcript)
    }

    func testPolishReturnsRawTranscriptForInvalidJSON() async {
        let transport = FakeOllamaTransport(data: Data("not json".utf8), status: 200)

        let result = await polish(using: transport)

        XCTAssertEqual(result, transcript)
    }

    func testPolishReturnsRawTranscriptForMalformedResponse() async {
        let transport = FakeOllamaTransport(data: Data(#"{"choices":[]}"#.utf8), status: 200)

        let result = await polish(using: transport)

        XCTAssertEqual(result, transcript)
    }

    func testPolishReturnsRawTranscriptForEmptyOutput() async {
        let transport = FakeOllamaTransport(
            data: Data(#"{"choices":[{"message":{"content":"   "}}]}"#.utf8),
            status: 200
        )

        let result = await polish(using: transport)

        XCTAssertEqual(result, transcript)
    }

    func testListModelsReturnsSortedValidModels() async {
        let transport = FakeOllamaTransport(
            data: Data(
                #"{"models":[{"name":"zeta:latest","size":2048},{"name":"alpha:latest","size":1024},{"size":5}]}"#.utf8
            ),
            status: 200
        )

        let models = await client(using: transport).listModels()

        XCTAssertEqual(models.map(\.id), ["alpha:latest", "zeta:latest"])
    }

    func testListModelsReturnsEmptyWhenTransportFails() async {
        let transport = FakeOllamaTransport(status: 200, dataError: .unreachable)

        let models = await client(using: transport).listModels()

        XCTAssertTrue(models.isEmpty)
    }

    func testListModelsReturnsEmptyForUnsuccessfulStatus() async {
        let transport = FakeOllamaTransport(status: 500)

        let models = await client(using: transport).listModels()

        XCTAssertTrue(models.isEmpty)
    }

    func testListModelsReturnsEmptyForMalformedPayload() async {
        let transport = FakeOllamaTransport(data: Data(#"{"items":[]}"#.utf8), status: 200)

        let models = await client(using: transport).listModels()

        XCTAssertTrue(models.isEmpty)
    }

    func testListModelsNormalizesDoubleAndMissingSizes() async {
        let transport = FakeOllamaTransport(
            data: Data(
                #"{"models":[{"name":"double","size":12.0},{"name":"missing"}]}"#.utf8
            ),
            status: 200
        )

        let models = await client(using: transport).listModels()

        XCTAssertEqual(models.map(\.sizeBytes), [12, 0])
    }

    func testPullReportsProgressFromStream() async {
        let transport = FakeOllamaTransport(
            status: 200,
            lines: [#"{"status":"downloading","completed":25,"total":100}"#]
        )
        let updates = ProgressBox()

        let error = await client(using: transport).pull(
            model: "qwen2.5:3b",
            onProgress: { updates.append(status: $0, fraction: $1) }
        )

        XCTAssertEqual(
            PullObservation(error: error, updates: updates.values),
            PullObservation(
                error: nil,
                updates: [ProgressUpdate(status: "downloading", fraction: 0.25)]
            )
        )
    }

    func testPullReportsIndeterminateProgressWithoutTotal() async {
        let transport = FakeOllamaTransport(
            status: 200,
            lines: [#"{"status":"verifying"}"#]
        )
        let updates = ProgressBox()

        let error = await client(using: transport).pull(
            model: "qwen2.5:3b",
            onProgress: { updates.append(status: $0, fraction: $1) }
        )

        XCTAssertEqual(
            PullObservation(error: error, updates: updates.values),
            PullObservation(
                error: nil,
                updates: [ProgressUpdate(status: "verifying", fraction: nil)]
            )
        )
    }

    func testPullReturnsServerErrorFromStream() async {
        let transport = FakeOllamaTransport(
            status: 200,
            lines: [#"{"error":"model manifest not found"}"#]
        )

        let error = await client(using: transport).pull(
            model: "missing",
            onProgress: { _, _ in }
        )

        XCTAssertEqual(error, "model manifest not found")
    }

    func testPullIgnoresMalformedProgressLines() async {
        let transport = FakeOllamaTransport(status: 200, lines: ["not json"])

        let error = await client(using: transport).pull(
            model: "qwen2.5:3b",
            onProgress: { _, _ in }
        )

        XCTAssertNil(error)
    }

    func testPullReturnsErrorForUnsuccessfulStatus() async {
        let transport = FakeOllamaTransport(status: 503)

        let error = await client(using: transport).pull(
            model: "qwen2.5:3b",
            onProgress: { _, _ in }
        )

        XCTAssertEqual(error, "Ollama refused the download — is it running?")
    }

    func testPullReturnsTransportFailure() async {
        let transport = FakeOllamaTransport(status: 200, lineStartError: .unreachable)

        let error = await client(using: transport).pull(
            model: "qwen2.5:3b",
            onProgress: { _, _ in }
        )

        XCTAssertEqual(error, "Ollama is unreachable")
    }

    func testPullReturnsStreamingFailure() async {
        let transport = FakeOllamaTransport(status: 200, streamError: .interrupted)

        let error = await client(using: transport).pull(
            model: "qwen2.5:3b",
            onProgress: { _, _ in }
        )

        XCTAssertEqual(error, "Ollama stream was interrupted")
    }

    func testDeleteReturnsNoErrorForSuccessfulResponse() async {
        let transport = FakeOllamaTransport(status: 200)

        let error = await client(using: transport).delete(model: "qwen2.5:3b")

        XCTAssertNil(error)
    }

    func testDeleteReturnsErrorForUnsuccessfulResponse() async {
        let transport = FakeOllamaTransport(status: 500)

        let error = await client(using: transport).delete(model: "qwen2.5:3b")

        XCTAssertEqual(error, "Ollama returned an unexpected status (HTTP 500).")
    }

    func testDeleteReturnsTransportFailure() async {
        let transport = FakeOllamaTransport(status: 200, dataError: .unreachable)

        let error = await client(using: transport).delete(model: "qwen2.5:3b")

        XCTAssertEqual(error, "Ollama is unreachable")
    }

    private func polish(using transport: FakeOllamaTransport) async -> String {
        await client(using: transport).polish(
            transcript,
            model: "qwen2.5:3b",
            systemPrompt: nil,
            vocab: [],
            expands: false
        )
    }

    private func client(using transport: FakeOllamaTransport) -> OllamaClient {
        OllamaClient(transport: transport)
    }
}

private struct ProgressUpdate: Equatable {
    let status: String
    let fraction: Double?
}

private struct PullObservation: Equatable {
    let error: String?
    let updates: [ProgressUpdate]
}

private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ProgressUpdate] = []

    var values: [ProgressUpdate] {
        lock.withLock { storage }
    }

    func append(status: String, fraction: Double?) {
        lock.withLock {
            storage.append(ProgressUpdate(status: status, fraction: fraction))
        }
    }
}

private enum TestFailure: LocalizedError {
    case interrupted
    case unreachable

    var errorDescription: String? {
        switch self {
        case .interrupted:
            "Ollama stream was interrupted"
        case .unreachable:
            "Ollama is unreachable"
        }
    }
}

private struct FakeOllamaTransport: OllamaTransporting {
    let data: Data
    let response: URLResponse
    let streamedLines: [String]
    let dataError: TestFailure?
    let lineStartError: TestFailure?
    let streamError: TestFailure?

    init(
        data: Data = Data(),
        status: Int,
        lines: [String] = [],
        dataError: TestFailure? = nil,
        lineStartError: TestFailure? = nil,
        streamError: TestFailure? = nil
    ) {
        self.data = data
        streamedLines = lines
        self.dataError = dataError
        self.lineStartError = lineStartError
        self.streamError = streamError
        guard let response = HTTPURLResponse(
            url: URL(string: "http://localhost")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        ) else {
            preconditionFailure("The canned HTTP response must be constructible")
        }
        self.response = response
    }

    func data(for _: URLRequest) async throws -> (Data, URLResponse) {
        if let dataError {
            throw dataError
        }
        return (data, response)
    }

    func lines(for _: URLRequest) async throws -> (URLResponse, AsyncThrowingStream<String, Error>) {
        if let lineStartError {
            throw lineStartError
        }
        let lines = streamedLines
        let streamError = streamError
        return (
            response,
            AsyncThrowingStream { continuation in
                for line in lines {
                    continuation.yield(line)
                }
                if let streamError {
                    continuation.finish(throwing: streamError)
                } else {
                    continuation.finish()
                }
            }
        )
    }
}
