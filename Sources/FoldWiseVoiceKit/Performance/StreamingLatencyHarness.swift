enum StreamingLatencyHarnessBuild {
    static var isEnabled: Bool {
        #if STREAMING_LATENCY_HARNESS
            true
        #else
            false
        #endif
    }
}

#if STREAMING_LATENCY_HARNESS
    // The doing half of the streaming latency gate (PRD #351). It drives the real
    // packaged Release Pipeline with a real resident Streaming ASR model, the real
    // Ollama Polish path, and the real Live transcript caption, replacing only the
    // microphone with a private WAV fixture played at capture pace and the
    // permission-bound paste with a stub plus its separately measured constant.
    //
    // Every judgment lives in `StreamingLatencyGate`; this file only measures and
    // records. The harness exists only in builds compiled with
    // `STREAMING_LATENCY_HARNESS`.

    import AppKit
    import AVFoundation
    import CryptoKit
    import Darwin
    import Foundation

    struct StreamingLatencyFixturePlan: Codable, Equatable {
        let length: StreamingLatencyFixtureLength
        let audioURL: URL
    }

    /// One process measures one Streaming ASR model, so its integrated peak
    /// footprint and maximum RSS belong to that model alone.
    struct StreamingLatencyPlan: Codable, Equatable {
        let schemaVersion: Int
        let asrModel: String
        let polishModel: String
        let sampleCount: Int
        /// The separately measured Accessibility paste constant, added to every
        /// post-release total so the gated number is the whole effect and not the
        /// stub. Never below the unconditional 50 ms clipboard settle.
        let insertConstantMilliseconds: Double
        let outputURL: URL
        let fixtures: [StreamingLatencyFixturePlan]

        static let minimumInsertConstantMilliseconds: Double = 50

        static func load(from url: URL) throws -> StreamingLatencyPlan {
            let plan = try JSONDecoder().decode(
                StreamingLatencyPlan.self,
                from: Data(contentsOf: url)
            )
            guard plan.schemaVersion == 1 else {
                throw StreamingLatencyHarnessError.unsupportedSchema(plan.schemaVersion)
            }
            guard let entry = ASRModelCatalog.entry(for: plan.asrModel), entry.streaming else {
                throw StreamingLatencyHarnessError.notAStreamingModel(plan.asrModel)
            }
            guard !plan.polishModel.isEmpty else {
                throw StreamingLatencyHarnessError.emptyModel
            }
            guard plan.sampleCount > 0 else {
                throw StreamingLatencyHarnessError.invalidSampleCount
            }
            guard plan.insertConstantMilliseconds >= minimumInsertConstantMilliseconds else {
                throw StreamingLatencyHarnessError.invalidInsertConstant(
                    plan.insertConstantMilliseconds
                )
            }
            guard plan.outputURL.isFileURL,
                  plan.fixtures.allSatisfy(\.audioURL.isFileURL)
            else {
                throw StreamingLatencyHarnessError.nonFileURL
            }
            guard plan.fixtures.map(\.length) == StreamingLatencyFixtureLength.allCases else {
                throw StreamingLatencyHarnessError.invalidFixtureMatrix
            }
            for fixture in plan.fixtures
                where !FileManager.default.fileExists(atPath: fixture.audioURL.path) {
                throw StreamingLatencyHarnessError.missingFixture(fixture.audioURL)
            }
            return plan
        }
    }

    /// One Dictation session, with both halves of the budget and the authority
    /// facts the gate refuses a run over. Raw text is reduced to digests here: the
    /// gate only needs to know whether the stages agreed.
    struct StreamingLatencySampleReport: Codable, Equatable {
        let index: Int
        let firstFeedbackMilliseconds: Double?
        let postReleaseMilliseconds: Double?
        /// The post-release total before the Accessibility paste constant, kept so
        /// the two components of the gated number stay visible.
        let stubbedPostReleaseMilliseconds: Double?
        let captionRendered: Bool
        let batchTranscriptionCalls: Int
        let insertions: Int
        let pipelineRawDigest: String
        let historyRawDigest: String
        let insertedDigest: String
        let polishGenerationMilliseconds: Double?
        let sessionTotalMilliseconds: Double?
    }

    struct StreamingLatencyClassReport: Codable, Equatable {
        let length: StreamingLatencyFixtureLength
        let shape: StreamingLatencyShape
        /// Whether this class is judged against a post-release limit. Recorded for
        /// the reader; the gate re-derives it so a report cannot exempt itself.
        let postReleaseLimitMilliseconds: Double?
        let discardedWarmUpRawTranscript: String
        let samples: [StreamingLatencySampleReport]
        let firstFeedback: StreamingLatencyStatistics?
        let postRelease: StreamingLatencyStatistics?
        /// Recorded evidence only: long-form Polish generation is never gated.
        let polishGeneration: StreamingLatencyStatistics?

        init(
            length: StreamingLatencyFixtureLength,
            shape: StreamingLatencyShape,
            discardedWarmUpRawTranscript: String,
            samples: [StreamingLatencySampleReport]
        ) {
            self.length = length
            self.shape = shape
            postReleaseLimitMilliseconds = StreamingLatencyClass(length: length, shape: shape)
                .postReleaseLimitMilliseconds
            self.discardedWarmUpRawTranscript = discardedWarmUpRawTranscript
            self.samples = samples
            firstFeedback = try? StreamingLatencyStatistics(
                samplesMilliseconds: samples.compactMap(\.firstFeedbackMilliseconds)
            )
            postRelease = try? StreamingLatencyStatistics(
                samplesMilliseconds: samples.compactMap(\.postReleaseMilliseconds)
            )
            polishGeneration = try? StreamingLatencyStatistics(
                samplesMilliseconds: samples.compactMap(\.polishGenerationMilliseconds)
            )
        }
    }

    struct StreamingLatencyResidencyReport: Codable, Equatable {
        let peakFootprintBytes: Int
        let maximumResidentBytes: Int
        let residentASREngineCount: Int
    }

    struct StreamingLatencyFixtureReport: Codable, Equatable {
        let length: StreamingLatencyFixtureLength
        let sha256: String
        let durationSeconds: Double
        let speechOnsetSeconds: Double
        let observedRawTranscripts: [String]
    }

    struct StreamingLatencyModelReport: Codable, Equatable {
        let schemaVersion: Int
        let recordedAt: Date
        let asrModel: String
        let effectiveASRModel: String
        let polishModel: String
        let recordedSamplesPerClass: Int
        let warmUpSamplesDiscardedPerClass: Int
        let insertion: String
        let insertConstantMilliseconds: Double
        let fixtures: [StreamingLatencyFixtureReport]
        let residency: StreamingLatencyResidencyReport
        let classes: [StreamingLatencyClassReport]

        func write(to url: URL) throws {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(self).write(to: url, options: .atomic)
        }
    }

    /// A private WAV fixture, plus the exact instant inside it where speech starts.
    /// The onset is a property of the audio rather than of a chunk boundary, so the
    /// first-feedback origin does not drift with the capture cadence.
    struct StreamingLatencyAudioFixture {
        let plan: StreamingLatencyFixturePlan
        let samples: [Float]
        let sha256: String

        /// The threshold Pipeline itself uses to decide audio is not near-silence.
        static let voiceThreshold: Float = 0.005

        var durationSeconds: Double {
            Double(samples.count) / AudioRecorder.sampleRate
        }

        var speechOnsetSeconds: Double {
            guard let index = samples.firstIndex(where: { abs($0) >= Self.voiceThreshold })
            else { return 0 }
            return Double(index) / AudioRecorder.sampleRate
        }

        static func load(_ plan: StreamingLatencyFixturePlan) throws -> StreamingLatencyAudioFixture {
            let file = try AVAudioFile(forReading: plan.audioURL)
            let format = file.processingFormat
            guard format.channelCount == 1,
                  abs(format.sampleRate - AudioRecorder.sampleRate) < 0.01
            else {
                throw StreamingLatencyHarnessError.invalidAudioFormat(
                    plan.audioURL,
                    sampleRate: format.sampleRate,
                    channels: format.channelCount
                )
            }
            guard file.length > 0, file.length <= AVAudioFramePosition(UInt32.max) else {
                throw StreamingLatencyHarnessError.invalidAudioLength(plan.audioURL)
            }
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(file.length)
            ) else {
                throw StreamingLatencyHarnessError.unreadableFixture(plan.audioURL)
            }
            try file.read(into: buffer)
            guard let channel = buffer.floatChannelData?.pointee else {
                throw StreamingLatencyHarnessError.unreadableFixture(plan.audioURL)
            }
            let samples = Array(
                UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            )
            guard samples.count >= 1600,
                  samples.contains(where: { abs($0) >= voiceThreshold })
            else {
                throw StreamingLatencyHarnessError.silentFixture(plan.audioURL)
            }
            let digest = SHA256.hash(data: try Data(contentsOf: plan.audioURL))
                .map { String(format: "%02x", $0) }
                .joined()
            return StreamingLatencyAudioFixture(plan: plan, samples: samples, sha256: digest)
        }
    }

    /// The kernel's own high-water marks. Read once at the end of a run rather
    /// than polled, so a sampling gap cannot understate the peak.
    enum StreamingLatencyProcessMemory {
        static func residency(residentASREngineCount: Int) -> StreamingLatencyResidencyReport {
            let info = vmInfo()
            return StreamingLatencyResidencyReport(
                peakFootprintBytes: Int(info?.ledger_phys_footprint_peak ?? 0),
                maximumResidentBytes: Int(info?.resident_size_peak ?? 0),
                residentASREngineCount: residentASREngineCount
            )
        }

        private static func vmInfo() -> task_vm_info_data_t? {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(
                MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
            )
            let outcome = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
                }
            }
            return outcome == KERN_SUCCESS ? info : nil
        }
    }

    @MainActor
    final class StreamingLatencyApplication {
        private let plan: StreamingLatencyPlan
        private var processActivity: NSObjectProtocol?

        init(plan: StreamingLatencyPlan) {
            self.plan = plan
        }

        func start() {
            processActivity = ProcessInfo.processInfo.beginActivity(
                options: [.latencyCritical, .idleSystemSleepDisabled],
                reason: "FoldWise streaming latency measurement"
            )
            Task {
                do {
                    let report = try await run()
                    try report.write(to: plan.outputURL)
                    finish()
                    NSApp.terminate(nil)
                } catch {
                    fail(error)
                }
            }
        }

        private func run() async throws -> StreamingLatencyModelReport {
            let fixtures = try plan.fixtures.map(StreamingLatencyAudioFixture.load)
            let config = try makeConfig()
            let lifecycle = ASRModelLifecycle(
                storedSelection: plan.asrModel,
                adapters: [
                    ParakeetASRModelAdapter(),
                    StreamingASRModelAdapter(),
                    WhisperASRModelAdapter(),
                ]
            )
            await lifecycle.start()
            let effective = try await effectiveSelection(of: lifecycle)

            let session = StreamingLatencySession(
                plan: plan,
                config: config,
                lifecycle: lifecycle
            )
            defer { session.shutdown() }
            var classReports: [StreamingLatencyClassReport] = []
            for shape in StreamingLatencyShape.allCases {
                try select(shape, in: config)
                for fixture in fixtures {
                    classReports.append(
                        try await session.measureClass(fixture: fixture, shape: shape)
                    )
                }
            }
            return StreamingLatencyModelReport(
                schemaVersion: 1,
                recordedAt: Date(),
                asrModel: plan.asrModel,
                effectiveASRModel: effective,
                polishModel: plan.polishModel,
                recordedSamplesPerClass: plan.sampleCount,
                warmUpSamplesDiscardedPerClass: 1,
                insertion: "stubbed plus the separately measured Accessibility constant",
                insertConstantMilliseconds: plan.insertConstantMilliseconds,
                fixtures: fixtures.map { fixture in
                    StreamingLatencyFixtureReport(
                        length: fixture.plan.length,
                        sha256: fixture.sha256,
                        durationSeconds: fixture.durationSeconds,
                        speechOnsetSeconds: fixture.speechOnsetSeconds,
                        observedRawTranscripts: session.observedRawTranscripts(
                            length: fixture.plan.length
                        )
                    )
                },
                residency: StreamingLatencyProcessMemory.residency(
                    residentASREngineCount: effective.isEmpty ? 0 : 1
                ),
                classes: classReports
            )
        }

        private func effectiveSelection(of lifecycle: ASRModelLifecycle) async throws -> String {
            let snapshot = await lifecycle.snapshot()
            guard !lifecycle.isDictationBlocked, let effective = snapshot.effectiveSelection else {
                throw StreamingLatencyHarnessError.asrUnavailable(plan.asrModel)
            }
            guard effective == plan.asrModel else {
                throw StreamingLatencyHarnessError.unexpectedEffectiveASRModel(
                    requested: plan.asrModel,
                    effective: effective
                )
            }
            return effective
        }

        private func makeConfig() throws -> Config {
            let configURL = plan.outputURL
                .deletingLastPathComponent()
                .appendingPathComponent("streaming-latency-config.json")
            var modes = Config.defaultConfig(path: configURL).orderedModes
            for index in modes.indices {
                modes[index].asrModel = plan.asrModel
                modes[index].llmModel = plan.polishModel
            }
            guard modes.contains(where: { $0.transformation == .inPlace }),
                  modes.contains(where: { $0.transformation == .expanding })
            else {
                throw StreamingLatencyHarnessError.missingShippedModes
            }
            return Config(
                preferences: Config.Preferences(
                    selection: .voiceToText,
                    hotkey: "alt_r",
                    toggleHotkey: nil,
                    pauseAudio: false,
                    inputDevice: nil,
                    asrModel: plan.asrModel,
                    appearance: .system,
                    saveHistory: true,
                    historyRetention: .forever,
                    sidebarCollapsed: false
                ),
                badgePosition: nil,
                orderedModes: modes,
                path: configURL
            )
        }

        private func select(_ shape: StreamingLatencyShape, in config: Config) throws {
            switch shape {
            case .voiceToText:
                try config.select(.voiceToText)
            case .inPlace, .expanding:
                let transformation: ModeTransformation = shape == .inPlace
                    ? .inPlace
                    : .expanding
                guard let id = config.orderedModes.first(where: {
                    $0.transformation == transformation
                })?.id else {
                    throw StreamingLatencyHarnessError.missingShippedModes
                }
                try config.select(.mode(id))
            }
        }

        private func finish() {
            guard let processActivity else { return }
            ProcessInfo.processInfo.endActivity(processActivity)
            self.processActivity = nil
        }

        private func fail(_ error: Error) {
            finish()
            let message = "Streaming latency run failed: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
            let failureURL = plan.outputURL
                .deletingPathExtension()
                .appendingPathExtension("failure.txt")
            do {
                try message.write(to: failureURL, atomically: true, encoding: .utf8)
            } catch {
                let writeFailure = "Could not write streaming latency failure artifact: "
                    + "\(error.localizedDescription)\n"
                FileHandle.standardError.write(Data(writeFailure.utf8))
            }
            NSApp.terminate(nil)
        }
    }

    /// What one Dictation session did, gathered off the Pipeline's own stage
    /// closures. Separate from the session object because `insert` and `record`
    /// arrive as initializer parameters and fire from the job task, not the main
    /// actor.
    private final class StreamingLatencyOutcome: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [HistoryEntry] = []
        private var insertedTexts: [String] = []
        private var insertedAt: Duration?
        private var batchTranscriptions = 0
        private var errorMessage: String?

        func recordInsert(_ text: String) {
            lock.withLock {
                insertedTexts.append(text)
                insertedAt = Pipeline.continuousNow()
            }
        }

        func record(_ entry: HistoryEntry) {
            lock.withLock { entries.append(entry) }
        }

        func recordBatchTranscription() {
            lock.withLock { batchTranscriptions += 1 }
        }

        func record(error message: String) {
            lock.withLock { errorMessage = message }
        }

        func reset() {
            lock.withLock {
                entries.removeAll(keepingCapacity: true)
                insertedTexts.removeAll(keepingCapacity: true)
                insertedAt = nil
                batchTranscriptions = 0
                errorMessage = nil
            }
        }

        var error: String? {
            lock.withLock { errorMessage }
        }

        var onlyEntry: HistoryEntry? {
            lock.withLock { entries.count == 1 ? entries[0] : nil }
        }

        var insertions: Int {
            lock.withLock { insertedTexts.count }
        }

        var insertedText: String {
            lock.withLock { insertedTexts.first ?? "" }
        }

        var insertCompletedAt: Duration? {
            lock.withLock { insertedAt }
        }

        var batchTranscriptionCalls: Int {
            lock.withLock { batchTranscriptions }
        }
    }

    /// Owns the composed production objects for one measured model: the real
    /// Pipeline, the real Badge and Live transcript caption, and the observers that
    /// turn one Dictation session into one recorded sample.
    @MainActor
    private final class StreamingLatencySession {
        private let plan: StreamingLatencyPlan
        private let recorder: StreamingLatencyRecorder
        private let outcome = StreamingLatencyOutcome()
        private let pipeline: Pipeline
        private let badge: BadgeController
        private let asrBadgePresentation = ASRBadgePresentation()
        private var lockedRawText = ""
        private var captionRenderedAt: Duration?
        private var rawTranscripts: [StreamingLatencyFixtureLength: Set<String>] = [:]

        init(plan: StreamingLatencyPlan, config: Config, lifecycle: ASRModelLifecycle) {
            self.plan = plan
            let recorder = StreamingLatencyRecorder()
            let outcome = outcome
            let ollama = OllamaClient()
            self.recorder = recorder
            badge = BadgeController(config: config) {}
            pipeline = Pipeline(
                config: config,
                recorder: recorder,
                sessionProvider: StreamingLatencyBatchAuditor(base: lifecycle, outcome: outcome),
                ducker: StreamingLatencyAudioDucker(),
                warmPolishModel: { mode in
                    guard let model = mode.llmModel, !model.isEmpty else { return }
                    ollama.scheduleWarm(model: model)
                },
                insert: { text in
                    outcome.recordInsert(text)
                    return true
                },
                record: { outcome.record($0) },
                frontmostApp: { "Streaming latency harness" }
            )
            wire()
        }

        // MARK: - composition

        /// Exactly the production wiring: the Badge folds progress through its own
        /// reducer, the caption reads the ungated state, and the caption's own draw
        /// is what "first visible feedback" means.
        private func wire() {
            badge.show()
            badge.captionModel.onRender = { [weak self] _ in
                self?.captionDidRender()
            }
            pipeline.onState = ApplicationRunLoop.handler { [weak self] state in
                self?.apply(state)
            }
            pipeline.onSessionEvent = ApplicationRunLoop.handler { [weak self] event in
                self?.badge.applyLiveTranscript(.session(event))
            }
            pipeline.onTranscript = ApplicationRunLoop.handler { [weak self] transcript in
                self?.apply(transcript)
            }
        }

        private func apply(_ state: PipelineState) {
            if let badgeState = asrBadgePresentation.pipelineDidChange(state) {
                badge.apply(badgeState)
            }
            badge.applyLiveTranscript(.pipeline(state))
            if case let .error(message) = state {
                outcome.record(error: message)
            }
        }

        private func apply(_ transcript: DictationTranscript) {
            badge.applyLiveTranscript(.transcript(transcript))
            if transcript.phase == .locked {
                lockedRawText = transcript.snapshot.committed
            }
        }

        private func captionDidRender() {
            guard captionRenderedAt == nil else { return }
            captionRenderedAt = Pipeline.continuousNow()
        }

        func shutdown() {
            pipeline.shutdown()
            badge.hide()
        }

        func observedRawTranscripts(length: StreamingLatencyFixtureLength) -> [String] {
            (rawTranscripts[length] ?? []).sorted()
        }

        // MARK: - measuring

        func measureClass(
            fixture: StreamingLatencyAudioFixture,
            shape: StreamingLatencyShape
        ) async throws -> StreamingLatencyClassReport {
            let warmUp = try await measureSample(index: 0, fixture: fixture, shape: shape)
            var samples: [StreamingLatencySampleReport] = []
            for index in 1 ... plan.sampleCount {
                samples.append(
                    try await measureSample(index: index, fixture: fixture, shape: shape).report
                )
            }
            return StreamingLatencyClassReport(
                length: fixture.plan.length,
                shape: shape,
                discardedWarmUpRawTranscript: warmUp.rawText,
                samples: samples
            )
        }

        /// One Dictation session end to end: capture at speech pace, release, and
        /// wait for the single atomic insertion to complete.
        private func measureSample(
            index: Int,
            fixture: StreamingLatencyAudioFixture,
            shape: StreamingLatencyShape
        ) async throws -> (report: StreamingLatencySampleReport, rawText: String) {
            resetSampleState()
            recorder.prepare(fixture: fixture)
            pipeline.startRecording()
            await recorder.awaitCaptureCompleted()
            let releasedAt = Pipeline.continuousNow()
            pipeline.stopRecording()
            await pipeline.awaitPendingJob()
            await settleRunLoop()

            if let message = outcome.error {
                throw StreamingLatencyHarnessError.pipeline(message)
            }
            guard let entry = outcome.onlyEntry, let timing = entry.timing else {
                throw StreamingLatencyHarnessError.missingEntry
            }
            rawTranscripts[fixture.plan.length, default: []].insert(entry.rawText)
            if shape != .voiceToText, timing.polishMilliseconds == nil {
                throw StreamingLatencyHarnessError.polishDidNotRun(fixture.plan.length)
            }
            let stubbed = postReleaseMilliseconds(from: releasedAt)
            let report = StreamingLatencySampleReport(
                index: index,
                firstFeedbackMilliseconds: firstFeedbackMilliseconds(),
                postReleaseMilliseconds: stubbed.map { $0 + plan.insertConstantMilliseconds },
                stubbedPostReleaseMilliseconds: stubbed,
                captionRendered: captionRenderedAt != nil,
                batchTranscriptionCalls: outcome.batchTranscriptionCalls,
                insertions: outcome.insertions,
                pipelineRawDigest: Self.digest(lockedRawText),
                historyRawDigest: Self.digest(entry.rawText),
                insertedDigest: Self.digest(outcome.insertedText),
                polishGenerationMilliseconds: timing.polishGenerationMilliseconds,
                sessionTotalMilliseconds: timing.totalMilliseconds
            )
            return (report, entry.rawText)
        }

        private func resetSampleState() {
            outcome.reset()
            lockedRawText = ""
            captionRenderedAt = nil
        }

        private func firstFeedbackMilliseconds() -> Double? {
            guard let captionRenderedAt, let onset = recorder.speechOnset else { return nil }
            return Self.milliseconds(from: onset, to: captionRenderedAt)
        }

        private func postReleaseMilliseconds(from releasedAt: Duration) -> Double? {
            guard let insertCompletedAt = outcome.insertCompletedAt else { return nil }
            return Self.milliseconds(from: releasedAt, to: insertCompletedAt)
        }

        /// Lets the caption's draw callback and the Badge's dismissal land before
        /// the next independent sample starts, outside every measured interval.
        private func settleRunLoop() async {
            try? await Task.sleep(for: .milliseconds(350))
        }

        private static func digest(_ text: String) -> String {
            SHA256.hash(data: Data(text.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
        }

        private static func milliseconds(from start: Duration, to end: Duration) -> Double {
            let components = (end - start).components
            let milliseconds = Double(components.seconds) * 1000
                + Double(components.attoseconds) / 1_000_000_000_000_000
            return max(0, milliseconds)
        }
    }

    /// Plays a private fixture through the production capture buffer at speech
    /// pace, so incremental delivery, the retained batch buffer, and the engine's
    /// chunk cadence are all the ones Dictation uses.
    private final class StreamingLatencyRecorder: AudioRecording, @unchecked Sendable {
        /// 100 ms at 16 kHz — the cadence the production tap converts to.
        static let chunkFrames = 1600

        var onFailure: ((AudioCaptureError) -> Void)?

        private let lock = NSLock()
        private var fixture: StreamingLatencyAudioFixture?
        private var consumer: (([Float]) -> Void)?
        private var buffer = CaptureSampleBuffer()
        private var capture: Task<Void, Never>?
        private var onset: Duration?

        /// The instant the fixture's first voiced sample was captured, which is
        /// the first-feedback origin the budget is written against.
        var speechOnset: Duration? {
            lock.withLock { onset }
        }

        func prepare(fixture: StreamingLatencyAudioFixture) {
            lock.withLock {
                self.fixture = fixture
                onset = nil
            }
        }

        func deliverSamples(to consumer: (([Float]) -> Void)?) {
            let buffer = lock.withLock { () -> CaptureSampleBuffer in
                self.consumer = consumer
                return self.buffer
            }
            buffer.deliver(to: consumer)
        }

        func start() throws {
            let started = lock.withLock { () -> StreamingLatencyAudioFixture? in
                guard let fixture else { return nil }
                let buffer = CaptureSampleBuffer()
                buffer.deliver(to: consumer)
                self.buffer = buffer
                return fixture
            }
            guard let started else {
                throw StreamingLatencyHarnessError.recorderNotPrepared
            }
            let startedAt = Pipeline.continuousNow()
            lock.withLock {
                onset = startedAt + .milliseconds(
                    Int((started.speechOnsetSeconds * 1000).rounded())
                )
            }
            let clock = ContinuousClock()
            let origin = clock.now
            capture = Task { [weak self] in
                var frame = 0
                var chunkIndex = 0
                while frame < started.samples.count {
                    let end = min(frame + Self.chunkFrames, started.samples.count)
                    chunkIndex += 1
                    // A chunk covering the first 100 ms of speech only exists once
                    // those 100 ms have been spoken, so the pace is the audio's own.
                    try? await Task.sleep(
                        until: origin + .milliseconds(chunkIndex * 100),
                        clock: clock
                    )
                    guard let self else { return }
                    let chunk = Array(started.samples[frame ..< end])
                    append(chunk)
                    frame = end
                }
            }
        }

        /// Waits until the whole fixture has been captured, which is where the
        /// user would release the hotkey.
        func awaitCaptureCompleted() async {
            await lock.withLock { capture }?.value
        }

        func stop() -> [Float] {
            let capture = lock.withLock { () -> Task<Void, Never>? in
                let capture = self.capture
                self.capture = nil
                return capture
            }
            capture?.cancel()
            return lock.withLock { buffer }.finish() ?? []
        }

        func close() {
            _ = stop()
        }

        private func append(_ chunk: [Float]) {
            let level = chunk.reduce(Float(0)) { $0 + $1 * $1 }
            let buffer = lock.withLock { self.buffer }
            buffer.append(chunk, level: (level / Float(max(1, chunk.count))).squareRoot())
        }
    }

    /// Watches the batch seam Pipeline would call. A healthy streaming session runs
    /// no batch transcription (ADR-0009), and the only place that fact is
    /// observable is the captured session handle itself.
    private final class StreamingLatencyBatchAuditor: ASRSessionHandleProviding {
        private let base: any ASRSessionHandleProviding
        private let outcome: StreamingLatencyOutcome

        init(base: any ASRSessionHandleProviding, outcome: StreamingLatencyOutcome) {
            self.base = base
            self.outcome = outcome
        }

        var isDictationBlocked: Bool {
            base.isDictationBlocked
        }

        func captureSession() throws -> any ASRSessionHandle {
            StreamingLatencyAuditedSession(base: try base.captureSession(), outcome: outcome)
        }
    }

    private final class StreamingLatencyAuditedSession: ASRSessionHandle {
        private let base: any ASRSessionHandle
        private let outcome: StreamingLatencyOutcome

        init(base: any ASRSessionHandle, outcome: StreamingLatencyOutcome) {
            self.base = base
            self.outcome = outcome
        }

        var canStream: Bool {
            base.canStream
        }

        func makeStream() async throws -> any TranscriptStreaming {
            try await base.makeStream()
        }

        func transcribe(_ samples: [Float]) async throws -> String {
            outcome.recordBatchTranscription()
            return try await base.transcribe(samples)
        }

        func release() {
            base.release()
        }
    }

    private final class StreamingLatencyAudioDucker: AudioDucking {
        func duck() {}
        func restore() {}
    }

    enum StreamingLatencyHarnessError: LocalizedError {
        case unsupportedSchema(Int)
        case notAStreamingModel(String)
        case emptyModel
        case invalidSampleCount
        case invalidInsertConstant(Double)
        case nonFileURL
        case invalidFixtureMatrix
        case missingFixture(URL)
        case invalidAudioFormat(URL, sampleRate: Double, channels: AVAudioChannelCount)
        case invalidAudioLength(URL)
        case unreadableFixture(URL)
        case silentFixture(URL)
        case asrUnavailable(String)
        case unexpectedEffectiveASRModel(requested: String, effective: String)
        case missingShippedModes
        case recorderNotPrepared
        case pipeline(String)
        case missingEntry
        case rawFinalDisagreement
        case polishDidNotRun(StreamingLatencyFixtureLength)

        var errorDescription: String? {
            switch self {
            case let .unsupportedSchema(version):
                "Unsupported streaming latency plan schema \(version)."
            case let .notAStreamingModel(model):
                "\(model) is not a Streaming ASR model in the catalog."
            case .emptyModel:
                "The Polish model identifier must be nonempty."
            case .invalidSampleCount:
                "Recorded samples per class must be greater than zero."
            case let .invalidInsertConstant(value):
                "The measured insert constant \(value) ms is below the unconditional "
                    + "\(StreamingLatencyPlan.minimumInsertConstantMilliseconds) ms paste delay."
            case .nonFileURL:
                "Fixture and output locations must be file URLs."
            case .invalidFixtureMatrix:
                "The fixture matrix must contain Short followed by Long exactly once."
            case let .missingFixture(url):
                "Streaming latency fixture does not exist: \(url.path)"
            case let .invalidAudioFormat(url, sampleRate, channels):
                "\(url.lastPathComponent) is \(sampleRate) Hz with \(channels) channels; "
                    + "fixtures must be 16000 Hz mono WAV."
            case let .invalidAudioLength(url):
                "Streaming latency fixture has an invalid frame length: \(url.path)"
            case let .unreadableFixture(url):
                "Streaming latency fixture could not be decoded as Float audio: \(url.path)"
            case let .silentFixture(url):
                "Streaming latency fixture is too short or silent: \(url.path)"
            case let .asrUnavailable(model):
                "Effective ASR model is unavailable after startup: \(model)"
            case let .unexpectedEffectiveASRModel(requested, effective):
                "Requested ASR model \(requested), but the effective model is \(effective)."
            case .missingShippedModes:
                "Shipped in-place and expanding Modes are required by the harness."
            case .recorderNotPrepared:
                "The streaming latency recorder was started without a prepared fixture."
            case let .pipeline(message):
                "Pipeline reported an error: \(message)"
            case .missingEntry:
                "Pipeline did not record exactly one completed Dictation session."
            case .rawFinalDisagreement:
                "Pipeline and History disagreed on the authoritative raw transcript."
            case let .polishDidNotRun(length):
                "Polish did not run for the \(length.rawValue) fixture."
            }
        }
    }
#endif
