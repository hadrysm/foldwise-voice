import XCTest
@testable import FoldWiseVoiceKit

final class AudioRecorderDevicePolicyTests: XCTestCase {
    private let builtIn = AudioInputDevice(uid: "built-in", name: "MacBook Microphone")
    private let usb = AudioInputDevice(uid: "usb-1", name: "Studio Mic")
    private let bluetooth = AudioInputDevice(uid: "bt-1", name: "Headset")

    func testCaptureErrorsHaveSpecificRecoveryMessages() {
        let cases: [(AudioCaptureError, String)] = [
            (.permissionDenied, "Microphone permission is required."),
            (.noDefaultInput, "No input device is available."),
            (.unreadableDevice, "FoldWise could not read the available input devices."),
            (.invalidFormat(device: "Studio Mic"), "Studio Mic has an unsupported audio format."),
            (.bindFailed(device: "Studio Mic"), "FoldWise could not connect to Studio Mic."),
            (
                .converterFailed(device: "Studio Mic"),
                "FoldWise could not prepare audio conversion for Studio Mic."
            ),
            (
                .engineStartFailed(message: "busy"),
                "Audio capture could not start: busy"
            ),
            (
                .configurationChanged,
                "The active input route changed during dictation."
            ),
            (
                .hardwareRestartFailed,
                "FoldWise could not resume input-device monitoring."
            ),
            (
                .activeDeviceDisconnected(device: "Studio Mic"),
                "Studio Mic disconnected during dictation."
            ),
        ]

        for (error, message) in cases {
            XCTAssertEqual(error.localizedDescription, message)
        }
    }

    func testSystemDefaultFollowsInitialAndLiveDefaultChanges() {
        let hardware = FakeAudioHardware(devices: [builtIn, usb], defaultUID: builtIn.uid)
        let recorder = AudioRecorder(preferredInputUID: nil, hardware: hardware)

        XCTAssertEqual(recorder.inputState.effectiveDevice, builtIn)

        hardware.publish(devices: [builtIn, usb], defaultUID: usb.uid)

        XCTAssertEqual(recorder.inputState.effectiveDevice, usb)
    }

    func testExplicitSelectionIgnoresUnrelatedDefaultChanges() {
        let hardware = FakeAudioHardware(devices: [builtIn, usb], defaultUID: builtIn.uid)
        let recorder = AudioRecorder(preferredInputUID: usb.uid, hardware: hardware)

        hardware.publish(devices: [builtIn, usb], defaultUID: usb.uid)

        XCTAssertEqual(recorder.inputState.effectiveDevice, usb)
    }

    func testPreferredDisconnectFallsBackAndReconnectRestores() {
        let hardware = FakeAudioHardware(devices: [builtIn, usb], defaultUID: builtIn.uid)
        let recorder = AudioRecorder(preferredInputUID: usb.uid, hardware: hardware)

        hardware.publish(devices: [builtIn], defaultUID: builtIn.uid)

        XCTAssertEqual(
            recorder.inputState,
            AudioInputState(
                devices: [builtIn], systemDefault: builtIn, preferredUID: usb.uid,
                preferredName: usb.name, effectiveDevice: builtIn, pendingDevice: nil,
                status: .fallback(preferred: usb.name, effective: builtIn.name)
            )
        )

        hardware.publish(devices: [builtIn, usb], defaultUID: builtIn.uid)

        XCTAssertEqual(recorder.inputState.effectiveDevice, usb)
        XCTAssertEqual(recorder.inputState.status, .restored(device: usb.name))
    }

    func testFallbackTracksANewSystemDefault() {
        let hardware = FakeAudioHardware(devices: [builtIn, usb], defaultUID: builtIn.uid)
        let recorder = AudioRecorder(preferredInputUID: usb.uid, hardware: hardware)
        hardware.publish(devices: [builtIn], defaultUID: builtIn.uid)

        hardware.publish(devices: [builtIn, bluetooth], defaultUID: bluetooth.uid)

        XCTAssertEqual(recorder.inputState.effectiveDevice, bluetooth)
        XCTAssertEqual(
            recorder.inputState.status,
            .fallback(preferred: usb.name, effective: bluetooth.name)
        )
    }

    func testHealthyRouteChangeDefersUntilStop() throws {
        let hardware = FakeAudioHardware(devices: [builtIn, usb], defaultUID: builtIn.uid)
        let recorder = AudioRecorder(preferredInputUID: nil, hardware: hardware)
        try recorder.start()

        recorder.setPreferredInputUID(usb.uid)

        XCTAssertEqual(recorder.inputState.effectiveDevice, builtIn)
        XCTAssertEqual(recorder.inputState.pendingDevice, usb)
        XCTAssertEqual(
            recorder.inputState.status,
            .deferred(current: builtIn.name, next: usb.name)
        )

        _ = recorder.stop()

        XCTAssertEqual(recorder.inputState.effectiveDevice, usb)
        XCTAssertNil(recorder.inputState.pendingDevice)
        XCTAssertEqual(hardware.startedUIDs, [builtIn.uid])
    }

    func testRouteChangeDuringStopAppliesAfterSamplesFreeze() throws {
        let hardware = FakeAudioHardware(devices: [builtIn, usb], defaultUID: builtIn.uid)
        let recorder = AudioRecorder(preferredInputUID: nil, hardware: hardware)
        var stateBeforeSamplesFreeze: AudioInputState?
        hardware.onSessionStop = {
            recorder.setPreferredInputUID(self.usb.uid)
            stateBeforeSamplesFreeze = recorder.inputState
        }
        try recorder.start()

        _ = recorder.stop()

        XCTAssertEqual(stateBeforeSamplesFreeze?.effectiveDevice, builtIn)
        XCTAssertEqual(stateBeforeSamplesFreeze?.pendingDevice, usb)
        XCTAssertEqual(recorder.inputState.effectiveDevice, usb)
        XCTAssertNil(recorder.inputState.pendingDevice)
    }

    func testActiveRouteLossFailsSessionAndPreparesFallback() throws {
        let hardware = FakeAudioHardware(devices: [builtIn, usb], defaultUID: builtIn.uid)
        let recorder = AudioRecorder(preferredInputUID: usb.uid, hardware: hardware)
        var failures: [AudioCaptureError] = []
        recorder.onFailure = { failures.append($0) }
        try recorder.start()

        hardware.publish(devices: [builtIn], defaultUID: builtIn.uid)

        XCTAssertEqual(failures, [.activeDeviceDisconnected(device: usb.name)])
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(recorder.stop(), [])
        XCTAssertEqual(recorder.inputState.effectiveDevice, builtIn)
    }

    func testDuplicateDisplayNamesRemainDistinctByUID() {
        let other = AudioInputDevice(uid: "usb-2", name: usb.name)
        let hardware = FakeAudioHardware(devices: [usb, other], defaultUID: usb.uid)
        let recorder = AudioRecorder(preferredInputUID: other.uid, hardware: hardware)

        XCTAssertEqual(recorder.inputState.effectiveDevice?.uid, other.uid)
    }

    func testCaptureStartupFailurePreservesPreferenceForRetry() {
        let hardware = FakeAudioHardware(devices: [builtIn, usb], defaultUID: builtIn.uid)
        hardware.startError = AudioCaptureError.bindFailed(device: usb.name)
        let recorder = AudioRecorder(preferredInputUID: usb.uid, hardware: hardware)

        XCTAssertThrowsError(try recorder.start()) { error in
            XCTAssertEqual(error as? AudioCaptureError, .bindFailed(device: self.usb.name))
        }

        XCTAssertEqual(recorder.inputState.preferredUID, usb.uid)
        XCTAssertFalse(recorder.isRecording)
    }

    func testTypedStartupFailuresPreservePreferenceAndAllowRetry() throws {
        let failures: [AudioCaptureError] = [
            .permissionDenied,
            .invalidFormat(device: usb.name),
            .bindFailed(device: usb.name),
            .converterFailed(device: usb.name),
            .engineStartFailed(message: "device busy"),
        ]

        for failure in failures {
            let hardware = FakeAudioHardware(devices: [builtIn, usb], defaultUID: builtIn.uid)
            hardware.startError = failure
            let recorder = AudioRecorder(preferredInputUID: usb.uid, hardware: hardware)

            XCTAssertThrowsError(try recorder.start()) { error in
                XCTAssertEqual(error as? AudioCaptureError, failure)
            }
            XCTAssertEqual(recorder.inputState.preferredUID, usb.uid)
            XCTAssertFalse(recorder.isRecording)

            hardware.startError = nil
            try recorder.start()
            XCTAssertTrue(recorder.isRecording)
            _ = recorder.stop()
        }
    }

    func testFailureDeliveredDuringStartupPreventsListeningSession() {
        let hardware = FakeAudioHardware(devices: [builtIn], defaultUID: builtIn.uid)
        hardware.failureDuringStart = .engineStartFailed(message: "lost during startup")
        let recorder = AudioRecorder(preferredInputUID: nil, hardware: hardware)
        var runtimeFailures: [AudioCaptureError] = []
        recorder.onFailure = { runtimeFailures.append($0) }

        XCTAssertThrowsError(try recorder.start()) { error in
            XCTAssertEqual(
                error as? AudioCaptureError,
                .engineStartFailed(message: "lost during startup")
            )
        }

        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(hardware.lastSession?.closeCount, 1)
        XCTAssertTrue(runtimeFailures.isEmpty)
    }

    func testCaptureLifecyclePublishesLevelAndStopsOnce() throws {
        let hardware = FakeAudioHardware(devices: [builtIn], defaultUID: builtIn.uid)
        let recorder = AudioRecorder(preferredInputUID: nil, hardware: hardware)
        XCTAssertEqual(recorder.level, 0)

        try recorder.start()
        hardware.lastSession?.level = 0.75
        try recorder.start()

        XCTAssertEqual(recorder.level, 0.75)
        XCTAssertEqual(hardware.startedUIDs, [builtIn.uid])
        XCTAssertEqual(recorder.stop(), [0.1, 0.2])
        XCTAssertEqual(recorder.level, 0)
        XCTAssertFalse(recorder.isRecording)
    }

    func testClosingActiveCaptureDiscardsItAndStopsObservation() throws {
        let hardware = FakeAudioHardware(devices: [builtIn], defaultUID: builtIn.uid)
        let recorder = AudioRecorder(preferredInputUID: nil, hardware: hardware)
        try recorder.start()

        recorder.close()

        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(hardware.lastSession?.closeCount, 1)
        XCTAssertEqual(hardware.stopObservingCount, 1)
    }

    func testQueuedHardwareChangeAfterCloseDoesNotRestartObservation() {
        let hardware = FakeAudioHardware(devices: [builtIn], defaultUID: builtIn.uid)
        let recorder = AudioRecorder(preferredInputUID: nil, hardware: hardware)
        recorder.close()

        hardware.restartService()

        XCTAssertEqual(hardware.observeCount, 1)
    }

    func testSelectingSystemDefaultClearsRememberedPreferredName() {
        let hardware = FakeAudioHardware(devices: [builtIn, usb], defaultUID: builtIn.uid)
        let recorder = AudioRecorder(preferredInputUID: usb.uid, hardware: hardware)

        recorder.setPreferredInputUID(nil)

        XCTAssertNil(recorder.inputState.preferredName)
        XCTAssertEqual(recorder.inputState.effectiveDevice, builtIn)
    }

    func testFreshSnapshotFailureAtStartIsTypedAndRetryable() {
        let hardware = FakeAudioHardware(devices: [builtIn], defaultUID: builtIn.uid)
        let recorder = AudioRecorder(preferredInputUID: nil, hardware: hardware)
        hardware.snapshotError = .unreadableDevice

        XCTAssertThrowsError(try recorder.start()) { error in
            XCTAssertEqual(error as? AudioCaptureError, .unreadableDevice)
        }

        XCTAssertFalse(recorder.isRecording)
    }

    func testUnknownStartupFailureMapsToEngineStartFailure() {
        struct UnexpectedFailure: LocalizedError {
            var errorDescription: String? {
                "unexpected boundary failure"
            }
        }
        let hardware = FakeAudioHardware(devices: [builtIn], defaultUID: builtIn.uid)
        hardware.startError = UnexpectedFailure()
        let recorder = AudioRecorder(preferredInputUID: nil, hardware: hardware)

        XCTAssertThrowsError(try recorder.start()) { error in
            XCTAssertEqual(
                error as? AudioCaptureError,
                .engineStartFailed(message: "unexpected boundary failure")
            )
        }
    }

    func testMissingSystemDefaultFailsRecoverably() {
        let hardware = FakeAudioHardware(devices: [], defaultUID: nil)
        let recorder = AudioRecorder(preferredInputUID: nil, hardware: hardware)

        XCTAssertThrowsError(try recorder.start()) { error in
            XCTAssertEqual(error as? AudioCaptureError, .noDefaultInput)
        }

        XCTAssertEqual(
            recorder.inputState.status,
            .unavailable(message: AudioCaptureError.noDefaultInput.localizedDescription)
        )
    }

    func testFreshSnapshotWithoutDefaultFailsEvenWhenPublishedRouteIsStale() {
        let hardware = FakeAudioHardware(devices: [builtIn], defaultUID: builtIn.uid)
        let recorder = AudioRecorder(preferredInputUID: nil, hardware: hardware)
        XCTAssertEqual(recorder.inputState.effectiveDevice, builtIn)
        hardware.setSnapshot(devices: [builtIn], defaultUID: nil)

        XCTAssertThrowsError(try recorder.start()) { error in
            XCTAssertEqual(error as? AudioCaptureError, .noDefaultInput)
        }

        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(
            recorder.inputState.status,
            .unavailable(message: AudioCaptureError.noDefaultInput.localizedDescription)
        )
    }

    func testUnreadableSnapshotRecoversOnLaterHardwareNotification() {
        let hardware = FakeAudioHardware(devices: [builtIn], defaultUID: builtIn.uid)
        hardware.snapshotError = .unreadableDevice
        let recorder = AudioRecorder(preferredInputUID: nil, hardware: hardware)

        hardware.snapshotError = nil
        hardware.publish(devices: [builtIn], defaultUID: builtIn.uid)

        XCTAssertEqual(recorder.inputState.effectiveDevice, builtIn)
        XCTAssertEqual(recorder.inputState.status, .ready)
    }

    func testUnreadableLiveHardwareNotificationPublishesRecoverableState() {
        let hardware = FakeAudioHardware(devices: [builtIn], defaultUID: builtIn.uid)
        let recorder = AudioRecorder(preferredInputUID: nil, hardware: hardware)
        hardware.snapshotError = .unreadableDevice

        hardware.publish(devices: [builtIn], defaultUID: builtIn.uid)

        XCTAssertEqual(
            recorder.inputState.status,
            .unavailable(message: AudioCaptureError.unreadableDevice.localizedDescription)
        )
    }

    func testRuntimeCaptureFailureDiscardsSamplesAndPreservesIntent() throws {
        let hardware = FakeAudioHardware(devices: [builtIn, usb], defaultUID: builtIn.uid)
        let recorder = AudioRecorder(preferredInputUID: usb.uid, hardware: hardware)
        var failures: [AudioCaptureError] = []
        recorder.onFailure = { failures.append($0) }
        try recorder.start()

        hardware.lastSession?.fail(.configurationChanged)

        XCTAssertEqual(failures, [.configurationChanged])
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(recorder.stop(), [])
        XCTAssertEqual(recorder.inputState.preferredUID, usb.uid)
    }

    func testNoDefaultChangeDuringCaptureKeepsSessionButMarksNextRouteUnavailable() throws {
        let hardware = FakeAudioHardware(devices: [builtIn], defaultUID: builtIn.uid)
        let recorder = AudioRecorder(preferredInputUID: nil, hardware: hardware)
        try recorder.start()

        hardware.publish(devices: [builtIn], defaultUID: nil)

        XCTAssertTrue(recorder.isRecording)
        XCTAssertEqual(
            recorder.inputState.status,
            .unavailable(message: AudioCaptureError.noDefaultInput.localizedDescription)
        )
    }

    func testListenerInstallationFailureRetriesBeforeCapture() throws {
        let hardware = FakeAudioHardware(devices: [builtIn], defaultUID: builtIn.uid)
        hardware.observeError = .hardwareRestartFailed
        let recorder = AudioRecorder(preferredInputUID: nil, hardware: hardware)
        XCTAssertEqual(
            recorder.inputState.status,
            .unavailable(message: AudioCaptureError.hardwareRestartFailed.localizedDescription)
        )

        hardware.publish(devices: [builtIn], defaultUID: builtIn.uid)
        XCTAssertEqual(
            recorder.inputState.status,
            .unavailable(message: AudioCaptureError.hardwareRestartFailed.localizedDescription)
        )

        hardware.observeError = nil
        try recorder.start()

        XCTAssertEqual(recorder.inputState.status, .ready)
        XCTAssertEqual(hardware.observeCount, 2)
    }

    func testServiceRestartReinstallsListenersAndRefreshesRoute() {
        let hardware = FakeAudioHardware(devices: [builtIn, usb], defaultUID: builtIn.uid)
        let recorder = AudioRecorder(preferredInputUID: nil, hardware: hardware)
        hardware.setSnapshot(devices: [builtIn, usb], defaultUID: usb.uid)

        hardware.restartService()

        XCTAssertEqual(hardware.observeCount, 2)
        XCTAssertEqual(recorder.inputState.effectiveDevice, usb)
        XCTAssertEqual(recorder.inputState.status, .ready)
    }

    func testFailedServiceRestartIsRecoverableOnNextStart() throws {
        let hardware = FakeAudioHardware(devices: [builtIn], defaultUID: builtIn.uid)
        let recorder = AudioRecorder(preferredInputUID: nil, hardware: hardware)
        hardware.observeError = .hardwareRestartFailed

        hardware.restartService()

        XCTAssertEqual(
            recorder.inputState.status,
            .unavailable(message: AudioCaptureError.hardwareRestartFailed.localizedDescription)
        )
        hardware.observeError = nil
        try recorder.start()
        XCTAssertTrue(recorder.isRecording)
    }

    func testRestorationMessageExpiresAfterDwell() {
        let hardware = FakeAudioHardware(devices: [builtIn, usb], defaultUID: builtIn.uid)
        var resets: [() -> Void] = []
        let recorder = AudioRecorder(
            preferredInputUID: usb.uid,
            hardware: hardware,
            scheduleRestorationReset: { resets.append($0) }
        )
        hardware.publish(devices: [builtIn], defaultUID: builtIn.uid)
        hardware.publish(devices: [builtIn, usb], defaultUID: builtIn.uid)
        XCTAssertEqual(recorder.inputState.status, .restored(device: usb.name))

        resets[0]()

        XCTAssertEqual(recorder.inputState.status, .ready)
    }

    func testStaleRestorationResetDoesNotOverwriteNewerStatus() {
        let hardware = FakeAudioHardware(devices: [builtIn, usb], defaultUID: builtIn.uid)
        var resets: [() -> Void] = []
        let recorder = AudioRecorder(
            preferredInputUID: usb.uid,
            hardware: hardware,
            scheduleRestorationReset: { resets.append($0) }
        )
        hardware.publish(devices: [builtIn], defaultUID: builtIn.uid)
        hardware.publish(devices: [builtIn, usb], defaultUID: builtIn.uid)
        recorder.setPreferredInputUID(nil)

        resets[0]()

        XCTAssertEqual(recorder.inputState.status, .ready)
        XCTAssertNil(recorder.inputState.preferredUID)
    }

    @MainActor
    func testConfigReactorAppliesOnlyInputDeviceChanges() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("foldwise-input-reactor-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: path) }
        let config = Config.defaultConfig(path: path)
        let hardware = FakeAudioHardware(devices: [builtIn, usb], defaultUID: builtIn.uid)
        let recorder = AudioRecorder(config: config, hardware: hardware)
        var publications = 0
        recorder.onInputStateChange = { _ in publications += 1 }

        config.setActiveMode("Email")
        try config.saveAndNotify()
        config.inputDevice = usb.uid
        try config.saveAndNotify()

        XCTAssertEqual(recorder.inputState.effectiveDevice, usb)
        XCTAssertEqual(publications, 1)
    }
}

private final class FakeAudioHardware: AudioHardware {
    var startError: Error?
    var failureDuringStart: AudioCaptureError?
    var snapshotError: AudioCaptureError?
    var observeError: AudioCaptureError?
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
        if let snapshotError { throw snapshotError }
        return currentSnapshot
    }

    func observeChanges(_ observer: @escaping (AudioHardwareChange) -> Void) throws {
        observeCount += 1
        if let observeError { throw observeError }
        self.observer = observer
    }

    func stopObserving() {
        stopObservingCount += 1
    }

    func startCapture(
        deviceUID: String,
        onFailure: @escaping (AudioCaptureError) -> Void
    ) throws -> any AudioCaptureSession {
        if let startError { throw startError }
        startedUIDs.append(deviceUID)
        let session = FakeAudioCaptureSession(onFailure: onFailure, onStop: onSessionStop)
        lastSession = session
        if let failureDuringStart { onFailure(failureDuringStart) }
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

private final class FakeAudioCaptureSession: AudioCaptureSession {
    var level: Float = 0
    private(set) var closeCount = 0
    private let onFailure: (AudioCaptureError) -> Void
    private let onStop: (() -> Void)?

    init(onFailure: @escaping (AudioCaptureError) -> Void, onStop: (() -> Void)?) {
        self.onFailure = onFailure
        self.onStop = onStop
    }

    func stop() -> [Float] {
        onStop?()
        return [0.1, 0.2]
    }

    func close() {
        closeCount += 1
    }

    func fail(_ error: AudioCaptureError) {
        onFailure(error)
    }
}
