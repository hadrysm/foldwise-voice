// Insert text into the focused app: clipboard + synthetic Cmd+V.
// The synthetic keystroke needs the Accessibility permission; without it we
// fall back to clipboard-only.

import AppKit
import Foundation
import os

enum TextInserter {
    /// Pending clipboard restore; canceled when a newer insert supersedes it.
    @MainActor private static var cancelRestore: (() -> Void)?

    typealias RestoreScheduler = (
        _ delay: TimeInterval,
        _ action: @escaping () -> Void
    ) -> () -> Void

    /// Copy `text` and paste it into the focused app. Returns true if a
    /// synthetic Cmd+V was posted, false for the clipboard-only fallback.
    @MainActor
    static func insert(
        _ text: String,
        pasteboard: NSPasteboard,
        trusted: () -> Bool,
        postPaste: () -> Void,
        restoreDelay: TimeInterval,
        scheduleRestore: RestoreScheduler
    ) -> Bool {
        guard !text.isEmpty else { return false }

        cancelRestore?()
        cancelRestore = nil

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
            cancelRestore = scheduleRestore(restoreDelay) {
                guard pasteboard.changeCount == expectedChangeCount else { return }
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
        return true
    }
}
