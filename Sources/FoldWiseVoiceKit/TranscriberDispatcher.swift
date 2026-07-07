// Fronts the concrete ASR engines behind the single `Transcribing` seam
// (ADR-0005): the composition root builds one dispatcher where it used to build
// the Parakeet `Transcriber`, and the `Pipeline` drives it without ever
// learning there is more than one engine. The active engine is resolved from
// `Config.asrModel` through `ASRModelCatalog`; an unknown or fossil id falls
// back to Parakeet. When the user changes the selection the dispatcher rebuilds
// the active engine (ADR-0003 propagation) with **drop-before-load**: the old
// engine (and its model) is released before the new one is built, so a switch
// never holds two multi-GB models resident at once.

import Foundation

final class TranscriberDispatcher: Transcribing {
    private let config: Config
    private let makeEngine: (ASRModelCatalog.Engine) -> Transcribing

    /// Guards the swappable engine reference: `transcribe`/`ready` read it off
    /// the main thread while a selection change swaps it on the main actor. It
    /// is briefly `nil` inside `rebuild` while the old engine is dropped before
    /// the new one is built, but that gap is held under the lock so no accessor
    /// ever observes it.
    private let lock = NSLock()
    private var engine: Transcribing?
    private var storedOnLoading: ((Bool) -> Void)?
    private var storedOnDownloadProgress: ((Double) -> Void)?

    @MainActor
    init(
        config: Config,
        makeEngine: @escaping (ASRModelCatalog.Engine) -> Transcribing
            = TranscriberDispatcher.buildEngine
    ) {
        self.config = config
        self.makeEngine = makeEngine
        engine = makeEngine(ASRModelCatalog.engine(forSelected: config.asrModel))
        config.onChange { [weak self] changes in
            guard let self, changes.contains(.asrModel) else { return }
            rebuild()
        }
    }

    /// Production factory: map a catalog engine to its concrete conformer. The
    /// default `makeEngine`; tests inject fakes instead.
    static func buildEngine(_ engine: ASRModelCatalog.Engine) -> Transcribing {
        switch engine {
        case .parakeet: Transcriber()
        case let .whisper(variant): WhisperTranscriber(variant: variant)
        }
    }

    var ready: Bool {
        lock.lock()
        defer { lock.unlock() }
        return engine?.ready ?? false
    }

    var onLoading: ((Bool) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedOnLoading
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storedOnLoading = newValue
            engine?.onLoading = newValue
        }
    }

    var onDownloadProgress: ((Double) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedOnDownloadProgress
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storedOnDownloadProgress = newValue
            engine?.onDownloadProgress = newValue
        }
    }

    func warmup() {
        lock.lock()
        let current = engine
        lock.unlock()
        current?.warmup()
    }

    func prepare() async throws {
        lock.lock()
        let current = engine
        lock.unlock()
        try await current?.prepare()
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        lock.lock()
        let current = engine
        lock.unlock()
        // Unreachable in practice: `rebuild` swaps the engine under a single lock
        // hold, and `init` sets it before any caller runs — so a locked read
        // never sees nil. Fail loudly rather than silently drop a dictation.
        guard let current else { throw DispatchError.noEngine }
        return try await current.transcribe(samples)
    }

    /// Swap in the engine the current selection resolves to. Drop-before-load
    /// (ADR-0005): releasing the previous engine *before* `makeEngine` runs
    /// frees its model first, so two engines are never resident at once. The
    /// whole swap is held under the lock, so `nil` is never observed outside.
    private func rebuild() {
        let engineType = ASRModelCatalog.engine(forSelected: config.asrModel)
        lock.lock()
        defer { lock.unlock() }
        let loadingSink = storedOnLoading
        let progressSink = storedOnDownloadProgress
        engine = nil // release the old engine (and its loaded model) first
        let next = makeEngine(engineType)
        next.onLoading = loadingSink
        next.onDownloadProgress = progressSink
        engine = next
    }

    enum DispatchError: Error { case noEngine }
}
