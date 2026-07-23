import Foundation

final class DictationCommandQueue {
    private let queue: DispatchQueue
    private let startAction: () -> Void
    private let stopAction: () -> Void
    private let toggleAction: () -> Void

    init(
        queue: DispatchQueue = DispatchQueue(label: "com.foldwise.dictation-commands"),
        start: @escaping () -> Void,
        stop: @escaping () -> Void,
        toggle: @escaping () -> Void
    ) {
        self.queue = queue
        startAction = start
        stopAction = stop
        toggleAction = toggle
    }

    func start() {
        queue.async(execute: startAction)
    }

    func stop() {
        queue.async(execute: stopAction)
    }

    func toggle() {
        queue.async(execute: toggleAction)
    }
}
