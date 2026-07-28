// Boundary fakes for the streaming ASR seam (ADR-0009). The FluidAudio
// streaming managers are the only thing faked: everything above them —
// snapshot mapping, attempt lifecycle, timing — runs for real.

import Foundation
@testable import FoldWiseVoiceKit

/// A streaming manager whose reports a test emits by hand, so snapshot order and
/// attempt lifecycle are asserted without loading real speech models.
final class FakeStreamingASRManager: StreamingASRManaging, @unchecked Sendable {
    enum Event: Equatable {
        case load
        case observe
        case append([Float])
        case finish
        case reset
    }

    var loadError: Error?
    var appendError: Error?
    var finishResult: Result<String, Error> = .success("")
    /// Awaited inside `load()`, so a test can hold an engine mid-load.
    var onLoad: (() async -> Void)?
    /// Awaited inside `finish()`, so a test can observe the finalization window.
    var onFinish: (() async -> Void)?
    private let lock = NSLock()
    private var collected: [Event] = []
    private var tentative: (@Sendable (String) -> Void)?
    private var committed: (@Sendable (String) -> Void)?

    var events: [Event] {
        lock.withLock { collected }
    }

    var appended: [[Float]] {
        events.compactMap { event in
            guard case let .append(samples) = event else { return nil }
            return samples
        }
    }

    var loadCount: Int {
        events.filter { $0 == .load }.count
    }

    var resetCount: Int {
        events.filter { $0 == .reset }.count
    }

    func load() async throws {
        record(.load)
        await onLoad?()
        if let loadError {
            throw loadError
        }
    }

    func observe(
        tentative: @escaping @Sendable (String) -> Void,
        committed: @escaping @Sendable (String) -> Void
    ) async {
        lock.withLock {
            collected.append(.observe)
            self.tentative = tentative
            self.committed = committed
        }
    }

    func append(_ samples: [Float]) async throws {
        record(.append(samples))
        if let appendError {
            throw appendError
        }
    }

    func finish() async throws -> String {
        record(.finish)
        await onFinish?()
        return try finishResult.get()
    }

    func reset() async {
        record(.reset)
    }

    /// Reports everything decoded so far, as the managers' partial callback does.
    func reportTentative(_ text: String) {
        lock.withLock { tentative }?(text)
    }

    /// Reports an utterance boundary, as EOU 320's callback does.
    func reportCommitted(_ text: String) {
        lock.withLock { committed }?(text)
    }

    private func record(_ event: Event) {
        lock.withLock { collected.append(event) }
    }
}

/// A monotonic clock a test advances by hand, so timing assertions never depend
/// on how fast the suite runs.
final class TestMonotonicClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Duration = .zero

    func advance(by amount: Duration) {
        lock.withLock { current += amount }
    }

    func now() -> Duration {
        lock.withLock { current }
    }
}

/// Collects the snapshots a stream delivers, in order.
final class SnapshotCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [TranscriptSnapshot] = []

    var snapshots: [TranscriptSnapshot] {
        lock.withLock { collected }
    }

    func append(_ snapshot: TranscriptSnapshot) {
        lock.withLock { collected.append(snapshot) }
    }
}
