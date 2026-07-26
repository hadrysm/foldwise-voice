import AppKit

enum ApplicationRunLoop {
    /// AppKit switches to modal-panel mode while it awaits a deferred
    /// termination reply, so lifecycle work must be eligible in both modes.
    static func handler<Event>(
        _ action: @escaping @MainActor (Event) -> Void
    ) -> (Event) -> Void {
        { event in
            perform {
                action(event)
            }
        }
    }

    private static func perform(_ action: @escaping @MainActor () -> Void) {
        RunLoop.main.perform(inModes: [.default, .modalPanel]) {
            MainActor.assumeIsolated {
                action()
            }
        }
    }
}
