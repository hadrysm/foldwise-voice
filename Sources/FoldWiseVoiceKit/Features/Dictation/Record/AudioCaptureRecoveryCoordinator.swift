import Foundation

final class AudioCaptureRecoveryCoordinator {
    private let queue = DispatchQueue(label: "com.foldwise.audio-capture")
    private let lock = NSLock()
    private var active = true
    private var recoveryScheduled = false
    private var failureReported = false
    private var shutdownPerformed = false

    func start(_ action: () throws -> Void) throws {
        try queue.sync {
            do {
                try action()
            } catch {
                lock.withLock { active = false }
                throw error
            }
        }
    }

    func configurationChanged(
        recover: @escaping () throws -> Void,
        onFailure: @escaping () -> Void
    ) {
        let shouldRecover = lock.withLock {
            guard active, !recoveryScheduled, !failureReported else { return false }
            recoveryScheduled = true
            return true
        }
        guard shouldRecover else { return }

        queue.async { [weak self] in
            guard let self else { return }
            let remainsActive = lock.withLock { self.active }
            guard remainsActive else {
                lock.withLock { self.recoveryScheduled = false }
                return
            }
            do {
                try recover()
                lock.withLock { self.recoveryScheduled = false }
            } catch {
                let shouldReport = lock.withLock {
                    self.recoveryScheduled = false
                    guard self.active, !self.failureReported else { return false }
                    self.failureReported = true
                    return true
                }
                guard shouldReport else { return }
                DispatchQueue.global(qos: .userInitiated).async(execute: onFailure)
            }
        }
    }

    func stop(_ action: () -> Void) {
        let shouldStop = lock.withLock {
            active = false
            guard !shutdownPerformed else { return false }
            shutdownPerformed = true
            return true
        }
        guard shouldStop else { return }
        queue.sync(execute: action)
    }
}

private extension NSLocking {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
