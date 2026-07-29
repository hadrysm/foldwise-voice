import XCTest
@testable import FoldWiseVoiceKit

/// What a Dictation session hands back versus what its consumer saw, so the
/// stop boundary reads as one assertion.
private struct StopBoundary: Equatable {
    let retained: [Float]
    let delivered: [[Float]]
}

final class AudioRecorderIncrementalDeliveryTests: XCTestCase {
    private let builtIn = AudioInputDevice(uid: "built-in", name: "MacBook Microphone")
    private let usb = AudioInputDevice(uid: "usb-1", name: "Studio Mic")

    func testSubscribedConsumerReceivesChunksInCaptureOrder() throws {
        let hardware = FakeAudioHardware(devices: [builtIn], defaultUID: builtIn.uid)
        let recorder = AudioRecorder(preferredInputUID: nil, hardware: hardware)
        var received: [[Float]] = []
        recorder.deliverSamples(to: { received.append($0) })

        try recorder.start()
        let session = try XCTUnwrap(hardware.lastSession)
        session.publish([0.3, 0.4])
        session.publish([0.5])
        session.drainDelivery()

        XCTAssertEqual(received, [[0.1, 0.2], [0.3, 0.4], [0.5]])
    }

    func testDeliveredChunksConcatenateToTheStoppedBuffer() throws {
        let hardware = FakeAudioHardware(devices: [builtIn], defaultUID: builtIn.uid)
        let recorder = AudioRecorder(preferredInputUID: nil, hardware: hardware)
        var received: [[Float]] = []
        recorder.deliverSamples(to: { received.append($0) })

        try recorder.start()
        let session = try XCTUnwrap(hardware.lastSession)
        session.publish([0.3, 0.4])
        session.drainDelivery()

        XCTAssertEqual(recorder.stop(), received.flatMap { $0 })
    }

    func testCaptureWithoutAConsumerStaysBatchOnly() throws {
        let hardware = FakeAudioHardware(devices: [builtIn], defaultUID: builtIn.uid)
        let recorder = AudioRecorder(preferredInputUID: nil, hardware: hardware)

        try recorder.start()

        XCTAssertEqual(hardware.lastSession?.hasConsumer, false)
    }

    /// A session captures the subscription when it begins, so a running
    /// batch-only session is never retrofitted mid-capture.
    func testSubscribingAfterStartLeavesTheRunningSessionBatchOnly() throws {
        let hardware = FakeAudioHardware(devices: [builtIn], defaultUID: builtIn.uid)
        let recorder = AudioRecorder(preferredInputUID: nil, hardware: hardware)
        try recorder.start()
        var received: [[Float]] = []

        recorder.deliverSamples(to: { received.append($0) })
        let session = try XCTUnwrap(hardware.lastSession)
        session.publish([0.3])
        session.drainDelivery()

        XCTAssertEqual(received, [])
    }

    func testTheNextSessionDeliversToAConsumerSubscribedBeforeIt() throws {
        let hardware = FakeAudioHardware(devices: [builtIn], defaultUID: builtIn.uid)
        let recorder = AudioRecorder(preferredInputUID: nil, hardware: hardware)
        var received: [[Float]] = []
        recorder.deliverSamples(to: { received.append($0) })
        try recorder.start()
        _ = recorder.stop()

        try recorder.start()
        let session = try XCTUnwrap(hardware.lastSession)
        session.publish([0.7])
        session.drainDelivery()

        XCTAssertEqual(received, [[0.1, 0.2], [0.7]])
    }

    func testDetachingTheConsumerStopsDeliveryMidSession() throws {
        let hardware = FakeAudioHardware(devices: [builtIn], defaultUID: builtIn.uid)
        let recorder = AudioRecorder(preferredInputUID: nil, hardware: hardware)
        var received: [[Float]] = []
        recorder.deliverSamples(to: { received.append($0) })
        try recorder.start()
        let session = try XCTUnwrap(hardware.lastSession)
        session.drainDelivery()

        recorder.deliverSamples(to: nil)
        session.publish([0.3])
        session.drainDelivery()

        XCTAssertEqual(received, [[0.1, 0.2]])
    }

    /// The recorder holds its routing lock across `stop()`, so a chunk accepted
    /// there must reach the batch buffer without running consumer code.
    func testChunksAcceptedWhileStoppingAreRetainedButNotDelivered() throws {
        let hardware = FakeAudioHardware(devices: [builtIn], defaultUID: builtIn.uid)
        let recorder = AudioRecorder(preferredInputUID: nil, hardware: hardware)
        var received: [[Float]] = []
        recorder.deliverSamples(to: { received.append($0) })
        hardware.onSessionStop = { hardware.lastSession?.publish([0.9]) }
        try recorder.start()
        let session = try XCTUnwrap(hardware.lastSession)
        session.drainDelivery()

        let samples = recorder.stop()
        session.drainDelivery()

        XCTAssertEqual(
            StopBoundary(retained: samples, delivered: received),
            StopBoundary(retained: [0.1, 0.2, 0.9], delivered: [[0.1, 0.2]])
        )
    }

    func testAChunkTheSessionAlreadyDequeuedIsRefusedAfterStop() throws {
        let hardware = FakeAudioHardware(devices: [builtIn], defaultUID: builtIn.uid)
        let recorder = AudioRecorder(preferredInputUID: nil, hardware: hardware)
        var received: [[Float]] = []
        recorder.deliverSamples(to: { received.append($0) })
        try recorder.start()
        let session = try XCTUnwrap(hardware.lastSession)
        _ = recorder.stop()

        session.deliverAfterStop([0.9])

        XCTAssertEqual(received, [])
    }

    func testConsumerCanStopTheRecorderFromInsideADelivery() throws {
        let hardware = FakeAudioHardware(devices: [builtIn], defaultUID: builtIn.uid)
        let recorder = AudioRecorder(preferredInputUID: nil, hardware: hardware)
        var stopped: [Float]?
        recorder.deliverSamples(to: { _ in stopped = recorder.stop() })
        try recorder.start()

        try XCTUnwrap(hardware.lastSession).drainDelivery()

        XCTAssertEqual(stopped, FakeAudioHardware.cannedCapture)
    }

    /// A route change during capture only defers the next route, so the session
    /// and its incremental delivery both survive it.
    func testConsumerKeepsReceivingAfterADeferredRouteChange() throws {
        let hardware = FakeAudioHardware(devices: [builtIn, usb], defaultUID: builtIn.uid)
        let recorder = AudioRecorder(preferredInputUID: nil, hardware: hardware)
        var received: [[Float]] = []
        recorder.deliverSamples(to: { received.append($0) })
        try recorder.start()

        recorder.setPreferredInputUID(usb.uid)
        let session = try XCTUnwrap(hardware.lastSession)
        session.publish([0.3])
        session.drainDelivery()

        XCTAssertEqual(received, [[0.1, 0.2], [0.3]])
    }

    func testBatchOnlyRecorderIgnoresIncrementalDelivery() {
        let recorder = FakeRecorder(samples: [0.1, 0.2])
        var received: [[Float]] = []

        recorder.deliverSamples(to: { received.append($0) })

        XCTAssertEqual(recorder.stop(), [0.1, 0.2])
        XCTAssertTrue(received.isEmpty)
    }
}
