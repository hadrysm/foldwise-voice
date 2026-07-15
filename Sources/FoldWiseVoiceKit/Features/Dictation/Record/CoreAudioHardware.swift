import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import os

final class CoreAudioHardware: AudioHardware {
    private let queue = DispatchQueue(label: "com.foldwise.audio-hardware")
    private let listenerLock = NSRecursiveLock()
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    func snapshot() throws -> AudioHardwareSnapshot {
        let devices = try deviceRecords().map(\.device)
        return AudioHardwareSnapshot(devices: devices, defaultUID: defaultInputUID())
    }

    func observeChanges(_ observer: @escaping (AudioHardwareChange) -> Void) throws {
        try listenerLock.withLock {
            stopObserving()
            try addListener(
                object: AudioObjectID(kAudioObjectSystemObject),
                selector: kAudioHardwarePropertyDevices,
                change: .topologyChanged,
                observer: observer
            )
            do {
                try addListener(
                    object: AudioObjectID(kAudioObjectSystemObject),
                    selector: kAudioHardwarePropertyDefaultInputDevice,
                    change: .topologyChanged,
                    observer: observer
                )
                try addListener(
                    object: AudioObjectID(kAudioObjectSystemObject),
                    selector: kAudioHardwarePropertyServiceRestarted,
                    change: .serviceRestarted,
                    observer: observer
                )
            } catch {
                stopObserving()
                throw error
            }
        }
    }

    func stopObserving() {
        listenerLock.withLock {
            for (object, storedAddress, block) in listeners {
                var address = storedAddress
                AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
            }
            listeners.removeAll()
        }
    }

    func startCapture(
        deviceUID: String,
        onFailure: @escaping (AudioCaptureError) -> Void
    ) throws -> any AudioCaptureSession {
        let devices = try deviceRecords()
        guard let record = devices.first(where: { $0.device.uid == deviceUID }) else {
            throw AudioCaptureError.unreadableDevice
        }
        return try AVAudioCaptureSession(
            deviceID: record.id,
            device: record.device,
            configurationFailure: { [weak self] in
                guard let self, let snapshot = try? snapshot() else {
                    return .configurationChanged
                }
                return snapshot.configurationFailure(activeDevice: record.device)
            },
            onFailure: onFailure
        )
    }

    private func addListener(
        object: AudioObjectID,
        selector: AudioObjectPropertySelector,
        change: AudioHardwareChange,
        observer: @escaping (AudioHardwareChange) -> Void
    ) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { _, _ in observer(change) }
        guard AudioObjectAddPropertyListenerBlock(object, &address, queue, block) == noErr else {
            throw AudioCaptureError.hardwareRestartFailed
        }
        listeners.append((object, address, block))
    }

    private func deviceRecords() throws -> [(id: AudioDeviceID, device: AudioInputDevice)] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr else { throw AudioCaptureError.unreadableDevice }
        var ids = [AudioDeviceID](
            repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { throw AudioCaptureError.unreadableDevice }
        return ids.compactMap { id -> (id: AudioDeviceID, device: AudioInputDevice)? in
            guard hasInputStreams(id) else { return nil }
            guard let uid = stringProperty(id, selector: kAudioDevicePropertyDeviceUID),
                  let name = stringProperty(id, selector: kAudioObjectPropertyName) else {
                Log.audio.error(
                    "Skipping input device \(id, privacy: .public): unreadable identity"
                )
                return nil
            }
            return (id, AudioInputDevice(uid: uid, name: name))
        }
    }

    private func hasInputStreams(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private func stringProperty(
        _ id: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value?.takeRetainedValue() as String?
    }

    private func defaultInputUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id
        ) == noErr, id != kAudioObjectUnknown else { return nil }
        return stringProperty(id, selector: kAudioDevicePropertyDeviceUID)
    }
}

private final class AVAudioCaptureSession: AudioCaptureSession {
    static let sampleRate = 16000.0

    private let engine = AVAudioEngine()
    private let recovery = AudioCaptureRecoveryCoordinator()
    private let lock = NSLock()
    private var converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let configurationFailure: () -> AudioCaptureError
    private let onFailure: (AudioCaptureError) -> Void
    private var buffered: [Float] = []
    private var latestLevel: Float = 0
    private var running = true
    private var tapInstalled = false
    private var configurationObserver: NSObjectProtocol?

    var level: Float {
        lock.withLock { latestLevel }
    }

    init(
        deviceID: AudioDeviceID,
        device: AudioInputDevice,
        configurationFailure: @escaping () -> AudioCaptureError,
        onFailure: @escaping (AudioCaptureError) -> Void
    ) throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw AudioCaptureError.permissionDenied
        }
        let input = engine.inputNode
        guard let audioUnit = input.audioUnit else {
            throw AudioCaptureError.bindFailed(device: device.name)
        }
        var mutableID = deviceID
        guard AudioUnitSetProperty(
            audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
            &mutableID, UInt32(MemoryLayout<AudioDeviceID>.size)
        ) == noErr else { throw AudioCaptureError.bindFailed(device: device.name) }

        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioCaptureError.invalidFormat(device: device.name)
        }
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate,
            channels: 1, interleaved: false
        ) else { throw AudioCaptureError.invalidFormat(device: device.name) }
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioCaptureError.converterFailed(device: device.name)
        }
        self.converter = converter
        self.outputFormat = outputFormat
        self.configurationFailure = configurationFailure
        self.onFailure = onFailure
        installTap(inputFormat: inputFormat)
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in self?.configurationChanged() }
        do {
            try recovery.start {
                engine.prepare()
                try engine.start()
            }
        } catch {
            recovery.stop { shutDownEngine() }
            throw AudioCaptureError.engineStartFailed(message: error.localizedDescription)
        }
    }

    func stop() -> [Float] {
        let samples: [Float] = lock.withLock {
            guard running else { return [] }
            running = false
            let samples = buffered
            buffered.removeAll()
            latestLevel = 0
            return samples
        }
        recovery.stop { shutDownEngine() }
        return samples
    }

    func close() {
        let shouldShutDown = lock.withLock {
            guard running else { return false }
            running = false
            buffered.removeAll()
            latestLevel = 0
            return true
        }
        if shouldShutDown { recovery.stop { shutDownEngine() } }
    }

    private func shutDownEngine() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        removeTap()
        engine.stop()
    }

    private func configurationChanged() {
        // AVAudioEngine delivers this notification on an internal queue and
        // warns against synchronous teardown there. Recovery owns its own
        // serial queue so stop/close cannot race tap and engine rebuilding.
        recovery.configurationChanged(
            recover: { [weak self] in try self?.rebuildAndRestartEngine() },
            onFailure: { [weak self] in
                guard let self else { return }
                onFailure(configurationFailure())
            }
        )
    }

    private func rebuildAndRestartEngine() throws {
        engine.stop()
        removeTap()
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioCaptureError.configurationChanged
        }
        lock.withLock { self.converter = converter }
        installTap(inputFormat: inputFormat)
        engine.prepare()
        try engine.start()
    }

    private func installTap(inputFormat: AVAudioFormat) {
        engine.inputNode.installTap(
            onBus: 0, bufferSize: 1024, format: inputFormat
        ) { [weak self] buffer, _ in
            self?.consume(buffer)
        }
        tapInstalled = true
    }

    private func removeTap() {
        guard tapInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    private func consume(_ buffer: AVAudioPCMBuffer) {
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            Log.audio.error("Could not allocate the converted audio buffer")
            return
        }
        var served = false
        var error: NSError?
        let activeConverter = lock.withLock { self.converter }
        activeConverter.convert(to: out, error: &error) { _, status in
            if served {
                status.pointee = .noDataNow
                return nil
            }
            served = true
            status.pointee = .haveData
            return buffer
        }
        if let error {
            Log.audio.error(
                "Audio conversion dropped a buffer: \(error.localizedDescription, privacy: .public)"
            )
            return
        }
        guard out.frameLength > 0, let channel = out.floatChannelData?[0] else { return }
        let frames = Int(out.frameLength)
        var sumOfSquares: Float = 0
        for index in 0 ..< frames {
            sumOfSquares += channel[index] * channel[index]
        }
        let rms = sqrt(sumOfSquares / Float(frames))
        lock.withLock {
            guard running else { return }
            buffered.append(contentsOf: UnsafeBufferPointer(start: channel, count: frames))
            latestLevel = rms
        }
    }
}

private extension NSLocking {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
