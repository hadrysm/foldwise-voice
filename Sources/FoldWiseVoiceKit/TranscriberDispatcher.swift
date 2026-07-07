// Fronts the concrete ASR engines behind the single `Transcribing` seam
// (ADR-0005): the composition root builds one dispatcher where it used to build
// the Parakeet `Transcriber`, and the `Pipeline` drives it without ever
// learning there is more than one engine. The active engine is resolved from
// `Config.asrModel` through `ASRModelCatalog`; an unknown or fossil id falls
// back to Parakeet. When the user changes the selection the dispatcher rebuilds
// the active engine (ADR-0003 propagation). Slice 1 ships Parakeet only —
// drop-before-load ordering and the Whisper engine arrive in later slices.

import Foundation

final class TranscriberDispatcher: Transcribing {
    private let config: Config
    private let makeEngine: (ASRModelCatalog.Engine) -> Transcribing

    /// Guards the swappable engine reference: `transcribe`/`ready` read it off
    /// the main thread while a selection change swaps it on the main actor.
    private let lock = NSLock()
    private var engine: Transcribing
    private var storedOnLoading: ((Bool) -> Void)?

    @MainActor
    init(
        config: Config,
        makeEngine: @escaping (ASRModelCatalog.Engine) -> Transcribing = { _ in Transcriber() }
    ) {
        self.config = config
        self.makeEngine = makeEngine
        engine = makeEngine(ASRModelCatalog.engine(forSelected: config.asrModel))
        config.onChange { [weak self] changes in
            guard let self, changes.contains(.asrModel) else { return }
            rebuild()
        }
    }

    var ready: Bool {
        lock.lock()
        defer { lock.unlock() }
        return engine.ready
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
            engine.onLoading = newValue
        }
    }

    func warmup() {
        lock.lock()
        let current = engine
        lock.unlock()
        current.warmup()
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        lock.lock()
        let current = engine
        lock.unlock()
        return try await current.transcribe(samples)
    }

    /// Swap in the engine the current selection resolves to, carrying the
    /// dispatcher's `onLoading` sink over so HUD feedback keeps flowing.
    private func rebuild() {
        let next = makeEngine(ASRModelCatalog.engine(forSelected: config.asrModel))
        lock.lock()
        next.onLoading = storedOnLoading
        engine = next
        lock.unlock()
    }
}
