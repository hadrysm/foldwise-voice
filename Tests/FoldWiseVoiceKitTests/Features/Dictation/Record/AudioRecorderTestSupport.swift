// Shared boundary fakes for driving `AudioRecorder` (ADR-0002): a scriptable
// Core Audio stand-in plus a capture session that publishes sample chunks on
// demand. Delivery is drained explicitly rather than synchronously from
// `publish`, mirroring the production hop onto a serial delivery queue.

import Foundation
@testable import FoldWiseVoiceKit

final class FakeAudioHardware: AudioHardware {
    /// What every fake session has captured by the time it starts, so batch
    /// callers see a non-empty buffer without publishing anything themselves.
    static let cannedCapture: [Float] = [0.1, 0.2]

    var startError: Error?
    var failureDuringStart: AudioCaptureError?
    var snapshotError: AudioCaptureError?
    var observeError: AudioCaptureError?
    var onStartCapture: (() -> Void)?
    var onSessionStop: (() -> Void)?
    private(set) var startedUIDs: [String] = []
    private(set) var stopObservingCount = 0
    private(set) var observeCount = 0
    private(set) var lastSession: FakeAudioCaptureSession?
    private var currentSnapshot: AudioHardwareSnapshot
    private var observer: ((AudioHardwareChange) -> Void)?

    init(devices: [AudioInputDevice], defaultUID: String?) {
        currentSnapshot = AudioHardwareSnapshot(devices: devices, defaultUID: defaultUID)
    }

    func snapshot() throws -> AudioHardwareSnapshot {
        if let snapshotError {
            throw snapshotError
        }
        return currentSnapshot
    }

    func observeChanges(_ observer: @escaping (AudioHardwareChange) -> Void) throws {
        observeCount += 1
        if let observeError {
            throw observeError
        }
        self.observer = observer
    }

    func stopObserving() {
        stopObservingCount += 1
    }

    func startCapture(
        deviceUID: String,
        onSamples: (([Float]) -> Void)?,
        onFailure: @escaping (AudioCaptureError) -> Void
    ) throws -> any AudioCaptureSession {
        if let startError {
            throw startError
        }
        onStartCapture?()
        startedUIDs.append(deviceUID)
        let session = FakeAudioCaptureSession(
            onSamples: onSamples, onFailure: onFailure, onStop: onSessionStop
        )
        session.publish(Self.cannedCapture)
        lastSession = session
        if let failureDuringStart {
            onFailure(failureDuringStart)
        }
        return session
    }

    func publish(devices: [AudioInputDevice], defaultUID: String?) {
        setSnapshot(devices: devices, defaultUID: defaultUID)
        observer?(.topologyChanged)
    }

    func setSnapshot(devices: [AudioInputDevice], defaultUID: String?) {
        currentSnapshot = AudioHardwareSnapshot(devices: devices, defaultUID: defaultUID)
    }

    func restartService() {
        let callback = observer
        observer = nil
        callback?(.serviceRestarted)
    }
}

final class FakeAudioCaptureSession: AudioCaptureSession {
    var level: Float = 0
    let hasConsumer: Bool
    private(set) var closeCount = 0
    private let onSamples: (([Float]) -> Void)?
    private let onFailure: (AudioCaptureError) -> Void
    private let onStop: (() -> Void)?
    private var captured: [Float] = []
    private var undelivered: [[Float]] = []
    private var isLive = true

    init(
        onSamples: (([Float]) -> Void)?,
        onFailure: @escaping (AudioCaptureError) -> Void,
        onStop: (() -> Void)?
    ) {
        self.onSamples = onSamples
        self.onFailure = onFailure
        self.onStop = onStop
        hasConsumer = onSamples != nil
    }

    /// Captures one chunk the way the audio render thread would: retained
    /// immediately, queued for a later delivery.
    func publish(_ chunk: [Float]) {
        captured.append(contentsOf: chunk)
        undelivered.append(chunk)
    }

    /// Runs the queued deliveries, so a test decides exactly when the consumer
    /// sees a chunk relative to stop, close, and route changes.
    func drainDelivery() {
        let chunks = undelivered
        undelivered.removeAll()
        guard isLive, let onSamples else { return }
        for chunk in chunks {
            onSamples(chunk)
        }
    }

    /// Simulates a delivery this session's queue had already dequeued when the
    /// recorder ended the session, so the recorder is the only thing left that
    /// can refuse it.
    func deliverAfterStop(_ chunk: [Float]) {
        onSamples?(chunk)
    }

    func stop() -> [Float] {
        onStop?()
        guard isLive else { return [] }
        isLive = false
        return captured
    }

    func close() {
        closeCount += 1
        isLive = false
    }

    func fail(_ error: AudioCaptureError) {
        onFailure(error)
    }
}
