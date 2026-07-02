// Insert text into the focused app: clipboard + synthetic Cmd+V.
// The synthetic keystroke needs the Accessibility permission; without it we
// fall back to clipboard-only.

import AppKit
import ApplicationServices
import Foundation

enum TextInserter {
    static func accessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Copy `text` and paste it into the focused app. Returns true if a
    /// synthetic Cmd+V was posted, false for the clipboard-only fallback.
    static func insert(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }

        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard accessibilityTrusted() else {
            NSLog("Accessibility not granted — transcript left on the clipboard")
            return false
        }

        usleep(50_000)  // let the clipboard settle before pasting

        let source = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 9
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: down)
            else { continue }
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
        }

        if let previous {
            // Give the focused app time to read the clipboard before restoring.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
        return true
    }
}
