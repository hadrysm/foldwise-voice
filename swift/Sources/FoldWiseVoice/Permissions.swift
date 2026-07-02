// Launch-time permission checks. Dictation needs Microphone (to record) and
// Accessibility (to post the ⌘V that pastes the transcript); missing either
// fails silently mid-dictation — empty transcripts or text stranded on the
// clipboard — so both are surfaced up front with native dialogs.

import AVFoundation
import AppKit
import ApplicationServices

@MainActor
enum Permissions {
    /// Check Microphone then Accessibility, chaining so the two dialogs
    /// never stack on top of each other.
    static func requestAtLaunch() {
        requestMicrophone { requestAccessibility() }
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
                pane: "Privacy_Microphone")
            next()
        @unknown default:
            next()
        }
    }

    // MARK: - Accessibility

    // The AX system prompt only appears while the app has never been added to
    // the Accessibility list; once it's listed (unchecked), further calls are
    // silent. Track whether we've prompted so later launches fall back to an
    // alert that links to System Settings.
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
                    + "Privacy & Security → Accessibility.",
                pane: "Privacy_Accessibility")
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
                string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
        {
            NSWorkspace.shared.open(url)
        }
    }
}
