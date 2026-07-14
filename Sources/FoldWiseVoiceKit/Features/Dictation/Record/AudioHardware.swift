import Foundation

struct AudioInputDevice: Identifiable, Hashable {
    let uid: String
    let name: String

    var id: String {
        uid
    }
}

struct AudioHardwareSnapshot: Equatable {
    let devices: [AudioInputDevice]
    let defaultUID: String?

    var systemDefault: AudioInputDevice? {
        devices.first { $0.uid == defaultUID }
    }

    func device(uid: String?) -> AudioInputDevice? {
        guard let uid else { return nil }
        return devices.first { $0.uid == uid }
    }
}

enum AudioInputStatus: Equatable {
    case ready
    case fallback(preferred: String, effective: String)
    case restored(device: String)
    case deferred(current: String, next: String)
    case unavailable(message: String)
}

struct AudioInputState: Equatable {
    let devices: [AudioInputDevice]
    let systemDefault: AudioInputDevice?
    let preferredUID: String?
    let preferredName: String?
    let effectiveDevice: AudioInputDevice?
    let pendingDevice: AudioInputDevice?
    let status: AudioInputStatus
}

protocol AudioInputStateProviding: AnyObject {
    var inputState: AudioInputState { get }
    var onInputStateChange: ((AudioInputState) -> Void)? { get set }
}

enum AudioCaptureError: Error, Equatable, LocalizedError {
    case permissionDenied
    case noDefaultInput
    case unreadableDevice
    case invalidFormat(device: String)
    case bindFailed(device: String)
    case converterFailed(device: String)
    case engineStartFailed(message: String)
    case configurationChanged
    case hardwareRestartFailed
    case activeDeviceDisconnected(device: String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Microphone permission is required."
        case .noDefaultInput:
            "No input device is available."
        case .unreadableDevice:
            "FoldWise could not read the available input devices."
        case let .invalidFormat(device):
            "\(device) has an unsupported audio format."
        case let .bindFailed(device):
            "FoldWise could not connect to \(device)."
        case let .converterFailed(device):
            "FoldWise could not prepare audio conversion for \(device)."
        case let .engineStartFailed(message):
            "Audio capture could not start: \(message)"
        case .configurationChanged:
            "The active input route changed during dictation."
        case .hardwareRestartFailed:
            "FoldWise could not resume input-device monitoring."
        case let .activeDeviceDisconnected(device):
            "\(device) disconnected during dictation."
        }
    }
}

protocol AudioCaptureSession: AnyObject {
    var level: Float { get }
    func stop() -> [Float]
    func close()
}

enum AudioHardwareChange {
    case topologyChanged
    case serviceRestarted
}

protocol AudioHardware: AnyObject {
    func snapshot() throws -> AudioHardwareSnapshot
    func observeChanges(_ observer: @escaping (AudioHardwareChange) -> Void) throws
    func stopObserving()
    func startCapture(
        deviceUID: String,
        onFailure: @escaping (AudioCaptureError) -> Void
    ) throws -> any AudioCaptureSession
}
