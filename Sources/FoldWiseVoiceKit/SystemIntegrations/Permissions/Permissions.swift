// Launch-time permission checks. Dictation needs Microphone (to record),
// Accessibility (to post the ⌘V that pastes the transcript), and Input
// Monitoring or Accessibility (for the global-hotkey event tap); missing any
// of them fails silently mid-dictation — empty transcripts, text stranded on
// the clipboard, or a hotkey that only works while the app is frontmost — so
// all are surfaced up front with native dialogs.

import AppKit
import ApplicationServices
import AVFoundation

@MainActor
enum Permissions {
    /// Check Microphone, then Accessibility, then Input Monitoring, chaining
    /// off the microphone callback so its dialog never stacks with the rest.
    static func requestAtLaunch() {
        requestMicrophone {
            requestAccessibility()
            requestInputMonitoring()
        }
    }

    // MARK: - Microphone

    private static func requestMicrophone(then next: @escaping @MainActor () -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            next()
        case .notDetermined:
            // Native system prompt (text comes from NSMicrophoneUsageDescription).
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                Task { @MainActor in next() }
            }
        case .denied, .restricted:
            // The system only asks once; after a denial, recording yields
            // silence with no error, so guide the user to System Settings.
            explainAndOfferSettings(
                title: "Microphone access is turned off",
                message: "FoldWise Voice can't hear you until Microphone access "
                    + "is enabled in System Settings → Privacy & Security → "
                    + "Microphone.",
                pane: "Privacy_Microphone"
            )
            next()
        @unknown default:
            next()
        }
    }

    // MARK: - Accessibility

    /// The AX system prompt only appears while the app has never been added to
    /// the Accessibility list; once it's listed (unchecked), further calls are
    /// silent. Track whether we've prompted so later launches fall back to an
    /// alert that links to System Settings.
    private static let axPromptedKey = "AXPermissionPrompted"

    private static func requestAccessibility() {
        guard !AXIsProcessTrusted() else { return }
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: axPromptedKey) {
            defaults.set(true, forKey: axPromptedKey)
            // Asking with the system prompt also registers the app (with its
            // current code signature) in System Settings → Accessibility, so
            // the grant survives ad-hoc rebuilds better than a hand-added
            // entry.
            let options =
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                    as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        } else {
            explainAndOfferSettings(
                title: "Accessibility access is turned off",
                message: "Without Accessibility, FoldWise Voice can't paste "
                    + "transcripts into other apps — dictations land on the "
                    + "clipboard instead. Enable it in System Settings → "
                    + "Privacy & Security → Accessibility.\n\n"
                    + "If FoldWise Voice already shows as enabled there, the "
                    + "grant belongs to a previous version of the app: remove "
                    + "it from the list with the − button, then add it back.",
                pane: "Privacy_Accessibility"
            )
        }
    }

    // MARK: - Input Monitoring

    /// The global-hotkey event tap is gated by Input Monitoring (Accessibility
    /// also satisfies it). Ask explicitly so the app gets listed in System
    /// Settings → Privacy & Security → Input Monitoring under its current code
    /// signature — otherwise the tap silently fails and the hotkey only works
    /// while the app is frontmost. The system shows this prompt at most once;
    /// after that the call is a silent no-op — including when a grant from a
    /// previous build's signature is still listed (updates re-sign the binary,
    /// which voids the old grant even though the toggle stays on). So on later
    /// launches explain the fix instead. HotkeyListener keeps retrying the
    /// tap, so a grant takes effect without a relaunch.
    private static let imPromptedKey = "IMPermissionPrompted"

    private static func requestInputMonitoring() {
        guard !AXIsProcessTrusted(), !CGPreflightListenEventAccess() else { return }
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: imPromptedKey) {
            defaults.set(true, forKey: imPromptedKey)
            _ = CGRequestListenEventAccess()
        } else {
            explainAndOfferSettings(
                title: "The dictation hotkey only works while the app is focused",
                message: "FoldWise Voice needs Input Monitoring to see the "
                    + "hotkey while you're in other apps. Enable it in System "
                    + "Settings → Privacy & Security → Input Monitoring.\n\n"
                    + "If FoldWise Voice already shows as enabled there, the "
                    + "grant belongs to a previous version of the app: remove "
                    + "it from the list with the − button, then add it back.",
                pane: "Privacy_ListenEvent"
            )
        }
    }

    // MARK: - shared alert

    private static func explainAndOfferSettings(
        title: String, message: String, pane: String
    ) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(
               string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
           ) {
            NSWorkspace.shared.open(url)
        }
    }
}
