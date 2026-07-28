// A modal session a lost `abortModal()` can't turn into a hung test process.
//
// The hosted tests drive AppKit for real: they show a window, schedule the
// events they want delivered with `DispatchQueue.main.async`, and end the
// session from inside that block. `NSApp.runModal(for:)` blocks until someone
// calls `abortModal()` — but the scheduled block only lands inside the session
// if nothing drains the main queue first, and any nested AppKit run loop
// (`orderFront`, layout, a sheet) will drain it. When that happens the abort
// fires with no session to end, `runModal` waits for an abort that will never
// come again, and the process never exits. Whatever it left on screen stays
// there: a `.statusBar`-level Badge panel joins every Space and has no
// titlebar, so the only way out is `kill`.
//
// So the deadline belongs to us, not to the callback: a watchdog scheduled in
// the run loop mode the modal session actually runs in ends the session and
// fails the test, instead of hanging the run.

import AppKit
import XCTest

extension XCTestCase {
    /// Runs `window` modally until something ends the session, or fails the test
    /// after `timeout` rather than blocking forever.
    @MainActor
    func runModalBounded(
        _ window: NSWindow,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let watchdog = Timer(timeInterval: timeout, repeats: false) { _ in
            XCTFail(
                "The modal session for \(window.title.isEmpty ? "an untitled window" : window.title) "
                    + "did not end within \(timeout)s — its abort was likely delivered "
                    + "before the session started.",
                file: file,
                line: line
            )
            NSApp.abortModal()
        }
        // `.modalPanel` is the mode a modal session spins in; a timer left in
        // `.default` would never fire while the session holds the run loop.
        RunLoop.current.add(watchdog, forMode: .modalPanel)
        defer { watchdog.invalidate() }
        NSApp.runModal(for: window)
    }
}
