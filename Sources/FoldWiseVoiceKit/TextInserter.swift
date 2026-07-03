// Insert text into the focused app: clipboard + synthetic Cmd+V.
// The synthetic keystroke needs the Accessibility permission; without it we
// fall back to clipboard-only.

import AppKit
import ApplicationServices
import Foundation
import os

enum TextInserter {
    /// Pending clipboard restore; canceled when a newer insert supersedes it.
    @MainActor private static var restoreWork: DispatchWorkItem?

    static func accessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Copy `text` and paste it into the focused app. Returns true if a
    /// synthetic Cmd+V was posted, false for the clipboard-only fallback.
    /// The pasteboard, permission check, and keystroke are parameters with
    /// production defaults so tests can drive the restore logic against a
    /// private named pasteboard.
    @MainActor
    static func insert(
        _ text: String,
        pasteboard: NSPasteboard = .general,
        trusted: () -> Bool = accessibilityTrusted,
        postPaste: () -> Void = postCmdV,
        restoreDelay: TimeInterval = 0.4
    ) -> Bool {
        guard !text.isEmpty else { return false }

        restoreWork?.cancel()
        restoreWork = nil

        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard trusted() else {
            Log.insert.warning("Accessibility not granted — transcript left on the clipboard")
            return false
        }

        postPaste()

        if let previous {
            // Give the focused app time to read the clipboard before
            // restoring — and only restore if nothing (a newer dictation, a
            // user copy) has written to the pasteboard since.
            let expectedChangeCount = pasteboard.changeCount
            let work = DispatchWorkItem {
                guard pasteboard.changeCount == expectedChangeCount else { return }
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
            restoreWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay, execute: work)
        }
        return true
    }

    /// Synthesize Cmd+V into the focused app (needs Accessibility).
    static func postCmdV() {
        usleep(50000) // let the clipboard settle before pasting

        let source = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 9
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: down)
            else { continue }
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
        }
    }
}
