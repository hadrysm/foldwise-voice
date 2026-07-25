import Darwin
import Foundation

final class UpdateRuntimeAcceptanceSignalMonitor {
    enum MonitorError: Error {
        case couldNotWatchDirectory
    }

    private let signalURL: URL
    private let onSignal: @Sendable () -> Void
    private let queue = DispatchQueue(
        label: "com.foldwise.voice.update-runtime-acceptance-signals"
    )
    private var source: DispatchSourceFileSystemObject?
    private var directoryDescriptor: Int32 = -1

    init(
        directory: URL,
        signalName: String,
        onSignal: @escaping @Sendable () -> Void
    ) {
        signalURL = directory.appendingPathComponent(signalName)
        self.onSignal = onSignal
    }

    func start() throws {
        directoryDescriptor = open(signalURL.deletingLastPathComponent().path, O_EVTONLY)
        guard directoryDescriptor >= 0 else {
            throw MonitorError.couldNotWatchDirectory
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryDescriptor,
            eventMask: .write,
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.consumeSignal()
        }
        source.setCancelHandler { [descriptor = directoryDescriptor] in
            close(descriptor)
        }
        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        directoryDescriptor = -1
    }

    private func consumeSignal() {
        guard FileManager.default.fileExists(atPath: signalURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: signalURL)
        } catch {
            Log.app.error(
                "Acceptance signal cleanup failed: \(error.localizedDescription)"
            )
        }
        onSignal()
    }
}
