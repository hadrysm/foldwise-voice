// The pinned FluidAudio streaming managers behind `StreamingASRManaging`
// (ADR-0009). Thin by design: these forward audio and callbacks and nothing
// else — snapshot mapping, timing, attempt lifecycle, and recovery all live in
// `TranscriptStream` and `StreamingTranscriber`, which are covered by tests.
// They are deliberate structural twins, as `Transcriber` and `WhisperTranscriber`
// already are: a shared generic shell would hide which library call each model
// actually makes for the sake of a dozen forwarding lines.
//
// EOU 320 detects utterance boundaries, so it reports both revisable text and a
// committed prefix. Nemotron 560 reports revisable text only; its committed
// prefix therefore stays empty until the attempt finalizes.

import FluidAudio
import Foundation

final class ParakeetEouStreamingManager: StreamingASRManaging {
    private let manager: StreamingEouAsrManager
    private let modelDirectory: URL

    init(modelDirectory: URL, chunkSize: StreamingChunkSize = .ms320) {
        manager = StreamingEouAsrManager(chunkSize: chunkSize)
        self.modelDirectory = modelDirectory
    }

    func load() async throws {
        try await manager.loadModels(from: modelDirectory)
    }

    func observe(
        tentative: @escaping @Sendable (String) -> Void,
        committed: @escaping @Sendable (String) -> Void
    ) async {
        await manager.setPartialCallback(tentative)
        await manager.setEouCallback(committed)
    }

    func append(_ samples: [Float]) async throws {
        _ = try await manager.process(audioBuffer: StreamingAudioChunk.buffer(for: samples))
    }

    func finish() async throws -> String {
        try await manager.finish().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func reset() async {
        await manager.reset()
    }
}

final class NemotronStreamingManager: StreamingASRManaging {
    private let manager: StreamingNemotronAsrManager
    private let modelDirectory: URL

    init(modelDirectory: URL, chunkSize: NemotronChunkSize = .ms560) {
        manager = StreamingNemotronAsrManager(requestedChunkSize: chunkSize)
        self.modelDirectory = modelDirectory
    }

    func load() async throws {
        try await manager.loadModels(from: modelDirectory)
    }

    func observe(
        tentative: @escaping @Sendable (String) -> Void,
        committed _: @escaping @Sendable (String) -> Void
    ) async {
        await manager.setPartialCallback(tentative)
    }

    func append(_ samples: [Float]) async throws {
        _ = try await manager.process(audioBuffer: StreamingAudioChunk.buffer(for: samples))
    }

    func finish() async throws -> String {
        try await manager.finish().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func reset() async {
        await manager.reset()
    }
}
