import Foundation

final class AudioRecorder: AudioRecording, AudioInputStateProviding {
    static let sampleRate = 16000.0

    private let hardware: any AudioHardware
    private let scheduleRestorationReset: (@escaping () -> Void) -> Void
    private let lock = NSRecursiveLock()
    private var snapshot: AudioHardwareSnapshot
    private var preferredUID: String?
    private var rememberedPreferredName: String?
    private var effective: AudioInputDevice?
    private var pending: AudioInputDevice?
    private var status: AudioInputStatus
    private var statusGeneration = 0
    private var capture: (any AudioCaptureSession)?
    private var isStarting = false
    private var startingFailure: AudioCaptureError?
    private var observationInstalled = false

    private enum StartResolution {
        case alreadyActive
        case unavailable(AudioInputState)
        case target(AudioInputDevice)
    }

    var onFailure: ((AudioCaptureError) -> Void)?
    var onInputStateChange: ((AudioInputState) -> Void)?

    var level: Float {
        lock.withLock { capture?.level ?? 0 }
    }

    var isRecording: Bool {
        lock.withLock { capture != nil }
    }

    var inputState: AudioInputState {
        lock.withLock { makeState() }
    }

    @MainActor
    convenience init(config: Config, hardware: any AudioHardware) {
        self.init(preferredInputUID: config.inputDevice, hardware: hardware)
        config.onChange { [weak self, weak config] changes in
            guard changes.contains(.inputDevice), let config else { return }
            self?.setPreferredInputUID(config.inputDevice)
        }
    }

    convenience init(preferredInputUID: String?, hardware: any AudioHardware) {
        self.init(
            preferredInputUID: preferredInputUID,
            hardware: hardware,
            scheduleRestorationReset: { action in
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 4,
                    execute: DispatchWorkItem(block: action)
                )
            }
        )
    }

    init(
        preferredInputUID: String?,
        hardware: any AudioHardware,
        scheduleRestorationReset: @escaping (@escaping () -> Void) -> Void
    ) {
        self.hardware = hardware
        self.scheduleRestorationReset = scheduleRestorationReset
        preferredUID = preferredInputUID
        do {
            snapshot = try hardware.snapshot()
            rememberedPreferredName = snapshot.device(uid: preferredInputUID)?.name
            effective = Self.resolve(preferredUID: preferredInputUID, snapshot: snapshot)
            status = Self.routeStatus(
                preferredUID: preferredInputUID,
                preferredName: rememberedPreferredName,
                effective: effective,
                snapshot: snapshot
            )
        } catch {
            snapshot = AudioHardwareSnapshot(devices: [], defaultUID: nil)
            effective = nil
            status = .unavailable(message: AudioCaptureError.unreadableDevice.localizedDescription)
        }
        do {
            try installObservation()
        } catch {
            setStatus(.unavailable(
                message: AudioCaptureError.hardwareRestartFailed.localizedDescription
            ))
        }
    }

    deinit {
        hardware.stopObserving()
    }

    func setPreferredInputUID(_ uid: String?) {
        let update = lock.withLock {
            preferredUID = uid
            if let device = snapshot.device(uid: uid) {
                rememberedPreferredName = device.name
            } else if uid == nil {
                rememberedPreferredName = nil
            }
            let resetGeneration = reduceRoute(restored: false)
            return (makeState(), resetGeneration)
        }
        onInputStateChange?(update.0)
        scheduleReset(generation: update.1)
    }

    func start() throws {
        try ensureObservation()
        let freshSnapshot: AudioHardwareSnapshot
        do {
            freshSnapshot = try hardware.snapshot()
        } catch {
            throw AudioCaptureError.unreadableDevice
        }

        let resolution: StartResolution = lock.withLock {
            guard capture == nil, !isStarting else { return .alreadyActive }
            snapshot = freshSnapshot
            let target = Self.resolve(preferredUID: preferredUID, snapshot: snapshot)
            guard let target else {
                setStatus(.unavailable(
                    message: AudioCaptureError.noDefaultInput.localizedDescription
                ))
                return .unavailable(makeState())
            }
            isStarting = true
            startingFailure = nil
            return .target(target)
        }
        let target: AudioInputDevice
        switch resolution {
        case .alreadyActive:
            return
        case let .unavailable(state):
            onInputStateChange?(state)
            throw AudioCaptureError.noDefaultInput
        case let .target(device):
            target = device
        }

        let session: any AudioCaptureSession
        do {
            session = try hardware.startCapture(
                deviceUID: target.uid,
                onFailure: { [weak self] error in self?.captureFailed(error) }
            )
        } catch let error as AudioCaptureError {
            lock.withLock {
                isStarting = false
                startingFailure = nil
            }
            throw error
        } catch {
            lock.withLock {
                isStarting = false
                startingFailure = nil
            }
            throw AudioCaptureError.engineStartFailed(message: error.localizedDescription)
        }

        let outcome: (AudioInputState?, AudioCaptureError?) = lock.withLock {
            isStarting = false
            if let failure = startingFailure {
                startingFailure = nil
                return (nil, failure)
            }
            capture = session
            effective = target
            pending = nil
            setStatus(Self.routeStatus(
                preferredUID: preferredUID,
                preferredName: rememberedPreferredName,
                effective: effective,
                snapshot: snapshot
            ))
            return (makeState(), nil)
        }
        if let failure = outcome.1 {
            session.close()
            throw failure
        }
        if let state = outcome.0 { onInputStateChange?(state) }
    }

    func stop() -> [Float] {
        guard let session = lock.withLock({ () -> (any AudioCaptureSession)? in
            let session = capture
            capture = nil
            return session
        }) else { return [] }

        let samples = session.stop()
        let freshSnapshot = try? hardware.snapshot()
        let update = lock.withLock {
            if let freshSnapshot { snapshot = freshSnapshot }
            let resetGeneration = reduceRoute(restored: false)
            return (makeState(), resetGeneration)
        }
        onInputStateChange?(update.0)
        scheduleReset(generation: update.1)
        return samples
    }

    func close() {
        let update = lock.withLock { () -> ((any AudioCaptureSession)?, AudioInputState) in
            let session = capture
            capture = nil
            isStarting = false
            startingFailure = nil
            pending = nil
            observationInstalled = false
            statusGeneration += 1
            return (session, makeState())
        }
        update.0?.close()
        hardware.stopObserving()
        onInputStateChange?(update.1)
    }

    private func hardwareChanged(_ change: AudioHardwareChange) {
        switch change {
        case .topologyChanged:
            refreshHardware()
        case .serviceRestarted:
            restartObservation()
        }
    }

    private func refreshHardware() {
        let freshSnapshot: AudioHardwareSnapshot
        do {
            freshSnapshot = try hardware.snapshot()
        } catch {
            let state = lock.withLock {
                setStatus(.unavailable(
                    message: AudioCaptureError.unreadableDevice.localizedDescription
                ))
                return makeState()
            }
            onInputStateChange?(state)
            return
        }

        let update = lock.withLock { () -> (
            session: (any AudioCaptureSession)?, state: AudioInputState,
            failure: AudioCaptureError?, resetGeneration: Int?
        ) in
            let oldSnapshot = snapshot
            snapshot = freshSnapshot
            if let preferred = snapshot.device(uid: preferredUID) {
                rememberedPreferredName = preferred.name
            }
            if capture != nil, let effective, snapshot.device(uid: effective.uid) == nil {
                let failedSession = capture
                capture = nil
                pending = nil
                let failedName = effective.name
                self.effective = Self.resolve(preferredUID: preferredUID, snapshot: snapshot)
                setStatus(Self.routeStatus(
                    preferredUID: preferredUID,
                    preferredName: rememberedPreferredName,
                    effective: self.effective,
                    snapshot: snapshot
                ))
                return (
                    failedSession, makeState(),
                    .activeDeviceDisconnected(device: failedName), nil
                )
            }
            let restored = preferredUID != nil
                && oldSnapshot.device(uid: preferredUID) == nil
                && snapshot.device(uid: preferredUID) != nil
            let resetGeneration = reduceRoute(restored: restored)
            return (nil, makeState(), nil, resetGeneration)
        }
        update.session?.close()
        onInputStateChange?(update.state)
        scheduleReset(generation: update.resetGeneration)
        if let failure = update.failure { onFailure?(failure) }
    }

    private func captureFailed(_ error: AudioCaptureError) {
        let update = lock.withLock { () -> (
            session: (any AudioCaptureSession)?, state: AudioInputState?
        ) in
            if isStarting {
                startingFailure = error
                return (nil, nil)
            }
            guard let session = capture else { return (nil, nil) }
            capture = nil
            pending = nil
            if let fresh = try? hardware.snapshot() { snapshot = fresh }
            effective = Self.resolve(preferredUID: preferredUID, snapshot: snapshot)
            setStatus(.unavailable(message: error.localizedDescription))
            return (session, makeState())
        }
        guard let state = update.state else { return }
        update.session?.close()
        onInputStateChange?(state)
        onFailure?(error)
    }

    private func installObservation() throws {
        try hardware.observeChanges { [weak self] change in
            self?.hardwareChanged(change)
        }
        lock.withLock { observationInstalled = true }
    }

    private func ensureObservation() throws {
        guard !lock.withLock({ observationInstalled }) else { return }
        do {
            try installObservation()
        } catch {
            let state = lock.withLock {
                setStatus(.unavailable(
                    message: AudioCaptureError.hardwareRestartFailed.localizedDescription
                ))
                return makeState()
            }
            onInputStateChange?(state)
            throw AudioCaptureError.hardwareRestartFailed
        }
    }

    private func restartObservation() {
        lock.withLock { observationInstalled = false }
        hardware.stopObserving()
        do {
            try installObservation()
            refreshHardware()
        } catch {
            let state = lock.withLock {
                setStatus(.unavailable(
                    message: AudioCaptureError.hardwareRestartFailed.localizedDescription
                ))
                return makeState()
            }
            onInputStateChange?(state)
        }
    }

    @discardableResult
    private func reduceRoute(restored: Bool) -> Int? {
        let desired = Self.resolve(preferredUID: preferredUID, snapshot: snapshot)
        if capture != nil, desired != effective {
            pending = desired
            if let effective, let desired {
                setStatus(.deferred(current: effective.name, next: desired.name))
            } else {
                setStatus(.unavailable(
                    message: AudioCaptureError.noDefaultInput.localizedDescription
                ))
            }
            return nil
        }
        effective = desired
        pending = nil
        if restored, let preferred = snapshot.device(uid: preferredUID) {
            return setStatus(.restored(device: preferred.name))
        }
        setStatus(Self.routeStatus(
            preferredUID: preferredUID,
            preferredName: rememberedPreferredName,
            effective: effective,
            snapshot: snapshot
        ))
        return nil
    }

    @discardableResult
    private func setStatus(_ status: AudioInputStatus) -> Int? {
        self.status = status
        statusGeneration += 1
        if case .restored = status { return statusGeneration }
        return nil
    }

    private func scheduleReset(generation: Int?) {
        guard let generation else { return }
        scheduleRestorationReset { [weak self] in
            self?.expireRestoration(generation: generation)
        }
    }

    private func expireRestoration(generation: Int) {
        let state = lock.withLock { () -> AudioInputState? in
            guard statusGeneration == generation, case .restored = status else { return nil }
            setStatus(Self.routeStatus(
                preferredUID: preferredUID,
                preferredName: rememberedPreferredName,
                effective: effective,
                snapshot: snapshot
            ))
            return makeState()
        }
        if let state { onInputStateChange?(state) }
    }

    private func makeState() -> AudioInputState {
        AudioInputState(
            devices: snapshot.devices,
            systemDefault: snapshot.systemDefault,
            preferredUID: preferredUID,
            preferredName: rememberedPreferredName,
            effectiveDevice: effective,
            pendingDevice: pending,
            status: status
        )
    }

    private static func resolve(
        preferredUID: String?, snapshot: AudioHardwareSnapshot
    ) -> AudioInputDevice? {
        if let preferred = snapshot.device(uid: preferredUID) { return preferred }
        return snapshot.systemDefault
    }

    private static func routeStatus(
        preferredUID: String?, preferredName: String?, effective: AudioInputDevice?,
        snapshot: AudioHardwareSnapshot
    ) -> AudioInputStatus {
        guard let effective else {
            return .unavailable(message: AudioCaptureError.noDefaultInput.localizedDescription)
        }
        if let preferredUID, snapshot.device(uid: preferredUID) == nil {
            return .fallback(
                preferred: preferredName ?? "Previously selected device",
                effective: effective.name
            )
        }
        return .ready
    }
}

private extension NSRecursiveLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
