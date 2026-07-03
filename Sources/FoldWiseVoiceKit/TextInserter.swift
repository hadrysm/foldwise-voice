// Insert text into the focused app: clipboard + synthetic Cmd+V.
// The synthetic keystroke needs the Accessibility permission; without it we
// fall back to clipboard-only.

import AppKit
import ApplicationServices
import Foundation

enum TextInserter {
    /// Pending clipboard restore; canceled when a newer insert supersedes it.
    @MainActor private static var restoreWork: DispatchWorkItem?

    static func accessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Copy `text` and paste it into the focused app. Returns true if a
    /// synthetic Cmd+V was posted, false for the clipboard-only fallback.
    @MainActor
    static func insert(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }

        restoreWork?.cancel()
        restoreWork = nil

        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard accessibilityTrusted() else {
            NSLog("Accessibility not granted — transcript left on the clipboard")
            return false
        }

        usleep(50000) // let the clipboard settle before pasting

        let source = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 9
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: down)
            else { continue }
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
        }

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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }
        return true
    }
}
