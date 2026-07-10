import Foundation

protocol OllamaTransporting: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
    func lines(for request: URLRequest) async throws -> (URLResponse, AsyncThrowingStream<String, Error>)
}

/// Thin URLSession adapter for the Ollama HTTP boundary. Response decisions
/// belong to `OllamaClient`; this type only converts URLSession's byte stream
/// into the line stream consumed by model downloads.
struct URLSessionOllamaTransport: OllamaTransporting {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }

    func lines(for request: URLRequest) async throws -> (URLResponse, AsyncThrowingStream<String, Error>) {
        let (bytes, response) = try await session.bytes(for: request)
        let lines = AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in bytes.lines {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
        return (response, lines)
    }
}

/// Production composition stays beside the URLSession effect so callers can
/// retain the client's original static surface while tests initialize the
/// included decision core with a deterministic transport.
extension OllamaClient {
    static func polish(
        _ text: String,
        model: String,
        systemPrompt: String?,
        vocab: [String],
        expands: Bool
    ) async -> String {
        await OllamaClient().polish(
            text,
            model: model,
            systemPrompt: systemPrompt,
            vocab: vocab,
            expands: expands
        )
    }

    static func listModels() async -> [InstalledModel] {
        await OllamaClient().listModels()
    }

    static func pull(
        model: String,
        onProgress: @escaping @Sendable (String, Double?) -> Void
    ) async -> String? {
        await OllamaClient().pull(model: model, onProgress: onProgress)
    }

    static func delete(model: String) async -> String? {
        await OllamaClient().delete(model: model)
    }
}
