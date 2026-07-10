// Wires the stages: record → Parakeet ASR → (optional Ollama polish) →
// paste. start/stop are called from the hotkey listener and must be fast;
// transcription jobs run in chained Tasks so they process in order without
// ever blocking the UI.

import AppKit
import Foundation
import os

/// The record stage's seam (ADR-0002). `AudioRecorder` is the production
/// conformer; tests inject a fake with canned samples.
protocol AudioRecording: AnyObject {
    func start()
    func stop() -> [Float]
    func close()
}

/// The transcribe stage's seam (ADR-0002). Mirrors `Transcriber`'s full
/// surface because the asynchronous loading-model dance is part of the
/// behavior under test.
protocol Transcribing: AnyObject {
    var ready: Bool { get }
    var onLoading: ((Bool) -> Void)? { get set }
    /// Fired with a 0…1 fraction while a model's weights download on first use,
    /// for a Badge/pane percentage (issue #93). An engine that can't report a
    /// fraction (FluidAudio/Parakeet) leaves this unset and degrades to the
    /// boolean `onLoading` spinner.
    var onDownloadProgress: ((Double) -> Void)? { get set }
    func warmup()
    /// Load (and, on first use, download) the model, throwing on failure.
    /// The awaitable, error-reporting sibling of fire-and-forget `warmup()`,
    /// used by the Speech pane's Download action to fetch weights up front.
    func prepare() async throws
    func transcribe(_ samples: [Float]) async throws -> String
}

enum PipelineState: Equatable {
    case listening(mode: String)
    /// A model's weights are downloading on first use; `fraction` is 0…1.
    case downloadingModel(fraction: Double)
    case loadingModel
    case transcribing
    case polishing(model: String)
    case inserted
    case clipboard
    case idle
    case error(String)

    /// True while a model (down)load is on screen — downloading or loading — so
    /// the boolean load-done signal resolves back to transcribing/idle from
    /// whichever preparing state the Badge is currently showing.
    var isPreparing: Bool {
        switch self {
        case .downloadingModel, .loadingModel: true
        default: false
        }
    }
}

final class Pipeline {
    let config: Config
    let ducker = AudioDucker()

    private let recorder: AudioRecording
    private let transcriber: Transcribing
    private let polish: (String, Mode) async -> String
    private let insert: (String) async -> Bool
    /// Best-effort history sink (PRD #78): handed the assembled entry after
    /// insertion. A closure seam mirroring `polish`/`insert` (ADR-0002).
    private let record: (HistoryEntry) -> Void
    /// Frontmost-app name at insert time. Injectable so tests stay AppKit-free.
    private let frontmostApp: () async -> String?

    /// Recursive because state observers and injected effects may synchronously
    /// call back into the Pipeline. State delivery stays inside the lock so a
    /// callback accepted before shutdown cannot arrive after terminal idle.
    private let stateLock = NSRecursiveLock()

    /// May fire from any thread — UIs must hop to the main thread themselves.
    var onState: ((PipelineState) -> Void)?

    /// Owned here rather than read back through the record seam, so the
    /// start/stop guards are self-contained and fakes needn't track it.
    private var recording = false
    private var lastJob: Task<Void, Never>?
    private var jobActive = false
    private var lastEmitted: PipelineState = .idle
    private var isShutDown = false

    init(
        config: Config,
        recorder: AudioRecording = AudioRecorder(),
        transcriber: Transcribing = Transcriber(),
        polish: @escaping (String, Mode) async -> String = Pipeline.ollamaPolish,
        insert: @escaping (String) async -> Bool = Pipeline.pasteboardInsert,
        record: @escaping (HistoryEntry) -> Void = Pipeline.recordToHistory,
        frontmostApp: @escaping () async -> String? = Pipeline.frontmostAppName
    ) {
        self.config = config
        self.recorder = recorder
        self.transcriber = transcriber
        self.polish = polish
        self.insert = insert
        self.record = record
        self.frontmostApp = frontmostApp
        self.transcriber.onLoading = { [weak self] loading in
            guard let self else { return }
            withStateLock {
                if loading {
                    guard !self.recording else { return }
                    self.emit(.loadingModel)
                } else if self.lastEmitted.isPreparing {
                    // Back to whatever the (down)load interrupted: a queued dictation
                    // continues transcribing; a launch warmup returns to idle.
                    self.emit(self.jobActive ? .transcribing : .idle)
                }
            }
        }
        self.transcriber.onDownloadProgress = { [weak self] fraction in
            guard let self else { return }
            withStateLock {
                // Suppressed while recording, like the loading spinner: the
                // percentage would fight the live listening pill.
                guard !self.recording else { return }
                self.emit(.downloadingModel(fraction: fraction))
            }
        }
    }

    // MARK: - production stage defaults

    static func ollamaPolish(_ text: String, mode: Mode) async -> String {
        guard let model = mode.llmModel else { return text }
        return await OllamaClient.polish(
            text, model: model, systemPrompt: mode.systemPrompt, vocab: mode.vocab,
            expands: mode.expands
        )
    }

    static func pasteboardInsert(_ text: String) async -> Bool {
        await MainActor.run { TextInserter.insert(text) }
    }

    static func recordToHistory(_ entry: HistoryEntry) {
        JSONLHistoryStore(url: JSONLHistoryStore.defaultURL).append(entry)
    }

    static func frontmostAppName() async -> String? {
        await MainActor.run { NSWorkspace.shared.frontmostApplication?.localizedName }
    }

    /// Delivers `state` unless shutdown is complete, then reports whether the
    /// Pipeline remained active after the observer returned.
    @discardableResult
    private func emit(_ state: PipelineState) -> Bool {
        withStateLock {
            guard !isShutDown else { return false }
            deliver(state)
            return !isShutDown
        }
    }

    private func deliver(_ state: PipelineState) {
        lastEmitted = state
        onState?(state)
    }

    private func withStateLock<T>(_ operation: () throws -> T) rethrows -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return try operation()
    }

    // MARK: - called from the hotkey listener (must be fast)

    func startRecording() {
        withStateLock {
            guard !isShutDown, !recording else { return }
            recording = true
            if config.pauseAudio { ducker.duck() }
            recorder.start()
            emit(.listening(mode: config.activeMode))
        }
    }

    func stopRecording() {
        withStateLock {
            guard !isShutDown, recording else { return }
            recording = false
            let samples = recorder.stop()
            ducker.restore()
            guard emit(.transcribing) else { return }
            let mode = config.mode
            // Frozen at stop time alongside `mode`: whether this session is saved is
            // decided when the user stops speaking, not read later off the job task.
            let saveHistory = config.saveHistory
            let previous = lastJob
            lastJob = Task {
                await withTaskCancellationHandler {
                    await previous?.value
                    guard !Task.isCancelled else { return }
                    await self.process(samples, mode: mode, saveHistory: saveHistory)
                } onCancel: {
                    previous?.cancel()
                }
            }
        }
    }

    func toggleRecording() {
        withStateLock {
            guard !isShutDown else { return }
            if recording {
                stopRecording()
            } else {
                startRecording()
            }
        }
    }

    /// Test hook: awaits the most recently queued session job. Each job
    /// awaits its predecessor, so this drains the whole chain.
    func awaitPendingJob() async {
        let pendingJob = withStateLock { lastJob }
        await pendingJob?.value
    }

    func shutdown() {
        withStateLock {
            guard !isShutDown else { return }
            isShutDown = true
            recording = false
            lastJob?.cancel()
            ducker.restore()
            recorder.close()
            deliver(.idle)
        }
    }

    // MARK: - worker

    private func process(_ samples: [Float], mode: Mode, saveHistory: Bool) async {
        let started = withStateLock {
            guard !isShutDown else { return false }
            jobActive = true
            return true
        }
        guard started else { return }
        defer { withStateLock { jobActive = false } }
        guard samples.count >= 1600 else { // < 0.1 s — no real audio captured
            emit(.idle)
            return
        }
        // Near-silence makes ASR hallucinate — skip it.
        guard samples.contains(where: { abs($0) >= 0.005 }) else {
            emit(.idle)
            return
        }

        var text: String
        do {
            if !transcriber.ready {
                guard emit(.loadingModel) else { return }
            }
            text = try await transcriber.transcribe(samples)
            guard !Task.isCancelled else { return }
        } catch is CancellationError {
            guard !Task.isCancelled else { return }
            emit(.idle)
            return
        } catch {
            Log.pipeline.error(
                "Transcription failed: \(String(describing: error), privacy: .public)"
            )
            emit(.error("\(error)"))
            return
        }
        guard !text.isEmpty else {
            emit(.idle)
            return
        }
        Log.pipeline.info("raw: \(text, privacy: .private)")
        let rawText = text

        // The keep-or-fall-back decision lives in `Polish.run`, shared with
        // Re-run Polish (ADR-0004): the candidate is already sanitized, so the
        // check judges the transform, not stripped scaffolding, and a fallback
        // keeps `text` at the raw transcript — extending the "model unreachable"
        // fallback to "model answered the wrong question." No new Badge state. The
        // emit here matches `Polish.run`'s gate via `Mode.willPolish`.
        if mode.willPolish(text), let model = mode.llmModel {
            guard emit(.polishing(model: model)) else { return }
        }
        guard !Task.isCancelled else { return }
        let polished = await Polish.run(rawText: text, mode: mode, polish: polish)
        guard !Task.isCancelled else { return }
        text = polished.text
        let isPolished = polished.isPolished
        if let verdict = polished.verdict {
            if verdict.fellBack { logOffTaskFallback(verdict, mode: mode) }
            Log.pipeline.info("llm: \(text, privacy: .private)")
        }

        // Frontmost app is the paste target, captured just before insertion.
        let sourceApp = await frontmostApp()
        guard !Task.isCancelled else { return }
        let pasted = await insert(text)
        // The insert effect cannot be rolled back once started, but shutdown is
        // terminal: do not publish completion or history after it returns.
        guard !Task.isCancelled else { return }
        guard emit(pasted ? .inserted : .clipboard) else { return }

        // Recorded after insertion so a history write can never delay the
        // paste (PRD #78); `record` is best-effort and never breaks a session.
        // Gated on the master switch: with saving off the Pipeline assembles
        // and hands off no entry, so nothing is written to disk.
        guard saveHistory else { return }
        let entry = HistoryEntry(
            id: UUID(),
            createdAt: Date(),
            text: text,
            rawText: rawText,
            isPolished: isPolished,
            modeName: mode.name,
            wordCount: text.split(whereSeparator: { $0.isWhitespace }).count,
            sourceApp: sourceApp,
            durationMs: Int(Double(samples.count) / AudioRecorder.sampleRate * 1000),
            flagged: false,
            flagReason: nil
        )
        withStateLock {
            guard !isShutDown else { return }
            record(entry)
        }
    }

    /// One public-level line per off-task fallback, for tuning thresholds from
    /// field behavior: the signal that fired plus the numeric overlap and
    /// length ratio, never the discarded output or the transcript (those stay
    /// on the `.private` "llm:"/"raw:" lines).
    private func logOffTaskFallback(_ verdict: OllamaClient.OffTaskVerdict, mode: Mode) {
        let overlap = String(format: "%.2f", verdict.overlap)
        let ratio = String(format: "%.2f", verdict.lengthRatio)
        Log.pipeline.error("""
        Polish off-task (\(verdict.signal, privacy: .public)) in mode \
        \(mode.name, privacy: .public) [expands=\(String(mode.expands), privacy: .public)] — \
        overlap \(overlap, privacy: .public), length ratio \(ratio, privacy: .public); \
        pasting raw transcript
        """)
    }
}
