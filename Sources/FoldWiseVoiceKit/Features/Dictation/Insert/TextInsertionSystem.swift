import AppKit
import ApplicationServices
import Foundation

enum TextInsertionSystem {
    static func scheduleRestore(
        after delay: TimeInterval,
        action: @escaping () -> Void
    ) -> () -> Void {
        let work = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        return { work.cancel() }
    }

    /// Synthesize Cmd+V into the focused app (needs Accessibility).
    static func postPaste() async {
        try? await Task.sleep(for: .milliseconds(50)) // let the clipboard settle before pasting

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

extension TextInserter {
    static func accessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    @MainActor
    static func insert(_ text: String) async -> Bool {
        await insert(
            text,
            pasteboard: .general,
            trusted: accessibilityTrusted,
            postPaste: TextInsertionSystem.postPaste,
            restoreDelay: 0.4,
            scheduleRestore: TextInsertionSystem.scheduleRestore
        )
    }
}
