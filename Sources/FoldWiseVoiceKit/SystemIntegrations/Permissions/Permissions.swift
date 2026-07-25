import AppKit
import ApplicationServices
import AVFoundation

@MainActor
enum Permissions {
    static func snapshot() -> PermissionRecoverySnapshot {
        PermissionRecoverySnapshot(
            microphone: microphoneStatus,
            accessibilityGranted: AXIsProcessTrusted(),
            inputMonitoringGranted: CGPreflightListenEventAccess()
        )
    }

    static func request(_ permission: PermissionKind) {
        switch permission {
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        case .accessibility:
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
            ] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        case .inputMonitoring:
            CGRequestListenEventAccess()
        }
    }

    static func openSystemSettings(for permission: PermissionKind) {
        let pane = switch permission {
        case .microphone:
            "Privacy_Microphone"
        case .accessibility:
            "Privacy_Accessibility"
        case .inputMonitoring:
            "Privacy_ListenEvent"
        }
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        ) else {
            Log.app.error("Could not construct the permission settings URL")
            return
        }
        NSWorkspace.shared.open(url)
    }

    private static var microphoneStatus: MicrophonePermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            .notDetermined
        case .restricted:
            .restricted
        case .denied:
            .denied
        case .authorized:
            .authorized
        @unknown default:
            .restricted
        }
    }
}
