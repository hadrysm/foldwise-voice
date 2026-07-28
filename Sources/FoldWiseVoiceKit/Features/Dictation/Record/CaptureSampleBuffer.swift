import Foundation

/// A capture session's samples. Retains the authoritative 16 kHz mono buffer
/// that `stop()` hands back, and relays the very same frames to an optional
/// incremental consumer (ADR-0009).
///
/// The consumer never runs on the audio render thread and never runs while this
/// lock is held, because `AudioRecorder.stop()` acquires the routing lock first
/// and the capture lock second: delivery is a non-blocking queue hop. `finish()`
/// therefore does not wait for a delivery already in flight — waiting would
/// deadlock a consumer that stops the recorder — so the boundary it establishes
/// is that no further chunk is dequeued. `AudioRecorder` closes the remaining
/// sliver by refusing a chunk from a session it has already ended.
final class CaptureSampleBuffer {
    typealias Consumer = ([Float]) -> Void

    private let schedule: (@escaping () -> Void) -> Void
    private let lock = NSLock()
    private var retained: [Float] = []
    private var pending: [[Float]] = []
    private var consumer: Consumer?
    private var isDelivering = false
    private var isLive = true
    private var latestLevel: Float = 0

    init(
        schedule: @escaping (@escaping () -> Void) -> Void = CaptureSampleBuffer.serialDelivery()
    ) {
        self.schedule = schedule
    }

    var level: Float {
        lock.withLock { latestLevel }
    }

    /// Subscribes the incremental consumer, normally before capture starts.
    /// `nil` detaches it and leaves the retained buffer untouched.
    func deliver(to consumer: Consumer?) {
        lock.withLock { self.consumer = consumer }
    }

    /// Accepts one converted chunk from the audio render thread. Retaining is
    /// synchronous so the batch buffer stays exact; delivery is queued, so a slow
    /// or reentrant consumer can never stall capture.
    func append(_ chunk: [Float], level: Float) {
        let startsDelivery = lock.withLock { () -> Bool in
            guard isLive else { return false }
            retained.append(contentsOf: chunk)
            latestLevel = level
            guard consumer != nil else { return false }
            pending.append(chunk)
            guard !isDelivering else { return false }
            isDelivering = true
            return true
        }
        guard startsDelivery else { return }
        schedule { [weak self] in self?.drain() }
    }

    /// Ends the session and hands back the retained buffer. A Dictation session
    /// has exactly one authoritative batch buffer, so later calls return `nil`;
    /// chunks accepted but not yet delivered are represented in that buffer.
    @discardableResult
    func finish() -> [Float]? {
        lock.withLock { () -> [Float]? in
            guard isLive else { return nil }
            isLive = false
            let samples = retained
            retained.removeAll()
            pending.removeAll()
            latestLevel = 0
            return samples
        }
    }

    /// One serial queue per capture session keeps chunks ordered and keeps
    /// consumer code off the audio render thread.
    static func serialDelivery() -> (@escaping () -> Void) -> Void {
        let queue = DispatchQueue(label: "com.foldwise.audio-chunks", qos: .userInitiated)
        return { work in queue.async(execute: work) }
    }

    private func drain() {
        while let delivery = nextDelivery() {
            delivery.consumer(delivery.chunk)
        }
    }

    private func nextDelivery() -> (consumer: Consumer, chunk: [Float])? {
        lock.withLock { () -> (consumer: Consumer, chunk: [Float])? in
            guard isLive, let consumer, !pending.isEmpty else {
                isDelivering = false
                return nil
            }
            return (consumer, pending.removeFirst())
        }
    }
}

private extension NSLocking {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
