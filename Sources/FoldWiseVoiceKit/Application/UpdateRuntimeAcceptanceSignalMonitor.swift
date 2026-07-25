import Foundation

final class UpdateRuntimeAcceptanceSignalMonitor {
    private let signalURL: URL
    private let onSignal: @Sendable () -> Void
    private let queue = DispatchQueue(
        label: "com.foldwise.voice.update-runtime-acceptance-signals"
    )
    private var timer: DispatchSourceTimer?

    init(
        directory: URL,
        signalName: String,
        onSignal: @escaping @Sendable () -> Void
    ) {
        signalURL = directory.appendingPathComponent(signalName)
        self.onSignal = onSignal
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now(),
            repeating: .milliseconds(50),
            leeway: .milliseconds(10)
        )
        timer.setEventHandler { [weak self] in
            self?.consumeSignal()
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func consumeSignal() {
        guard FileManager.default.fileExists(atPath: signalURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: signalURL)
        } catch {
            Log.app.error(
                "Acceptance signal cleanup failed: \(error.localizedDescription)"
            )
            return
        }
        onSignal()
    }
}
