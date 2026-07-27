enum DictationBaselineHarnessBuild {
    static var isEnabled: Bool {
        #if DICTATION_BASELINE_HARNESS
            true
        #else
            false
        #endif
    }
}

#if DICTATION_BASELINE_HARNESS
    import AppKit
    import AVFoundation
    import CryptoKit
    import Foundation

    enum DictationBaselineFixtureLength: String, Codable, CaseIterable {
        case short
        case long
    }

    struct DictationBaselineFixturePlan: Codable, Equatable {
        let length: DictationBaselineFixtureLength
        let audioURL: URL
        let expectedTranscript: String
    }

    struct DictationBaselinePlan: Codable, Equatable {
        let schemaVersion: Int
        let asrModel: String
        let polishModel: String
        let sampleCount: Int
        let outputURL: URL
        let fixtures: [DictationBaselineFixturePlan]

        static func load(from url: URL) throws -> DictationBaselinePlan {
            let plan = try JSONDecoder().decode(
                DictationBaselinePlan.self,
                from: Data(contentsOf: url)
            )
            guard plan.schemaVersion == 1 else {
                throw DictationBaselineHarnessError.unsupportedSchema(plan.schemaVersion)
            }
            guard !plan.asrModel.isEmpty, !plan.polishModel.isEmpty else {
                throw DictationBaselineHarnessError.emptyModel
            }
            guard plan.sampleCount > 0 else {
                throw DictationBaselineHarnessError.invalidSampleCount
            }
            guard plan.outputURL.isFileURL,
                  plan.fixtures.allSatisfy(\.audioURL.isFileURL)
            else {
                throw DictationBaselineHarnessError.nonFileURL
            }
            guard plan.fixtures.map(\.length) == DictationBaselineFixtureLength.allCases else {
                throw DictationBaselineHarnessError.invalidFixtureMatrix
            }
            for fixture in plan.fixtures {
                guard FileManager.default.fileExists(atPath: fixture.audioURL.path) else {
                    throw DictationBaselineHarnessError.missingFixture(fixture.audioURL)
                }
                guard fixture.expectedTranscript.count > MIN_CHARS_FOR_LLM else {
                    throw DictationBaselineHarnessError.shortExpectedTranscript(
                        fixture.length
                    )
                }
            }
            return plan
        }
    }

    struct DictationBaselineStatistics: Codable, Equatable {
        let medianMilliseconds: Double
        let p95Milliseconds: Double
        let worstMilliseconds: Double

        init(samplesMilliseconds: [Double]) throws {
            guard !samplesMilliseconds.isEmpty else {
                throw DictationBaselineHarnessError.emptySamples
            }
            let sorted = samplesMilliseconds.sorted()
            if sorted.count.isMultiple(of: 2) {
                let upper = sorted.count / 2
                medianMilliseconds = (sorted[upper - 1] + sorted[upper]) / 2
            } else {
                medianMilliseconds = sorted[sorted.count / 2]
            }
            let p95Index = max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)
            p95Milliseconds = sorted[p95Index]
            worstMilliseconds = sorted[sorted.count - 1]
        }

        init(
            medianMilliseconds: Double,
            p95Milliseconds: Double,
            worstMilliseconds: Double
        ) {
            self.medianMilliseconds = medianMilliseconds
            self.p95Milliseconds = p95Milliseconds
            self.worstMilliseconds = worstMilliseconds
        }
    }

    private struct DictationBaselineAudioFixture {
        let plan: DictationBaselineFixturePlan
        let samples: [Float]
        let sha256: String

        var durationMilliseconds: Int {
            Int(Double(samples.count) / AudioRecorder.sampleRate * 1000)
        }

        static func load(_ plan: DictationBaselineFixturePlan) throws
            -> DictationBaselineAudioFixture {
            let file = try AVAudioFile(forReading: plan.audioURL)
            let format = file.processingFormat
            guard format.channelCount == 1,
                  abs(format.sampleRate - AudioRecorder.sampleRate) < 0.01
            else {
                throw DictationBaselineHarnessError.invalidAudioFormat(
                    plan.audioURL,
                    sampleRate: format.sampleRate,
                    channels: format.channelCount
                )
            }
            guard file.length > 0, file.length <= AVAudioFramePosition(UInt32.max) else {
                throw DictationBaselineHarnessError.invalidAudioLength(plan.audioURL)
            }
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(file.length)
            ) else {
                throw DictationBaselineHarnessError.unreadableFixture(plan.audioURL)
            }
            try file.read(into: buffer)
            guard let channel = buffer.floatChannelData?.pointee else {
                throw DictationBaselineHarnessError.unreadableFixture(plan.audioURL)
            }
            let samples = Array(
                UnsafeBufferPointer(
                    start: channel,
                    count: Int(buffer.frameLength)
                )
            )
            guard samples.count >= 1600,
                  samples.contains(where: { abs($0) >= 0.005 })
            else {
                throw DictationBaselineHarnessError.silentFixture(plan.audioURL)
            }
            let digest = SHA256.hash(data: try Data(contentsOf: plan.audioURL))
                .map { String(format: "%02x", $0) }
                .joined()
            return DictationBaselineAudioFixture(
                plan: plan,
                samples: samples,
                sha256: digest
            )
        }
    }

    enum DictationBaselineShape: String, Codable, CaseIterable {
        case voiceToText
        case inPlace
        case expanding
    }

    enum DictationBaselineTranscriptContract {
        static func clearsPolishFloor(_ transcript: String) -> Bool {
            transcript.count > MIN_CHARS_FOR_LLM
        }
    }

    struct DictationBaselineStageReport: Codable, Equatable {
        let samplesMilliseconds: [Double]
        let statistics: DictationBaselineStatistics

        init(samplesMilliseconds: [Double]) throws {
            self.samplesMilliseconds = samplesMilliseconds
            statistics = try DictationBaselineStatistics(
                samplesMilliseconds: samplesMilliseconds
            )
        }
    }

    struct DictationBaselineSampleReport: Codable, Equatable {
        let index: Int
        let rawTranscript: String
        let insertedText: String
        let isPolished: Bool
        let timing: DictationSessionTiming
    }

    struct DictationBaselineClassReport: Codable, Equatable {
        let shape: DictationBaselineShape
        let length: DictationBaselineFixtureLength
        let discardedWarmUpTranscript: String
        let samples: [DictationBaselineSampleReport]
        let stages: [String: DictationBaselineStageReport]

        init(
            shape: DictationBaselineShape,
            length: DictationBaselineFixtureLength,
            discardedWarmUpTranscript: String,
            entries: [HistoryEntry]
        ) throws {
            self.shape = shape
            self.length = length
            self.discardedWarmUpTranscript = discardedWarmUpTranscript
            samples = try entries.enumerated().map { index, entry in
                guard let timing = entry.timing else {
                    throw DictationBaselineHarnessError.missingTiming
                }
                return DictationBaselineSampleReport(
                    index: index + 1,
                    rawTranscript: entry.rawText,
                    insertedText: entry.text,
                    isPolished: entry.isPolished,
                    timing: timing
                )
            }
            stages = try Self.makeStages(entries)
        }

        private static func makeStages(
            _ entries: [HistoryEntry]
        ) throws -> [String: DictationBaselineStageReport] {
            let extractors: [(String, (DictationSessionTiming) -> Double?)] = [
                ("total", { $0.totalMilliseconds }),
                ("queued", { $0.queuedMilliseconds }),
                ("transcribe", { $0.transcribeMilliseconds }),
                ("polish", { $0.polishMilliseconds }),
                ("serverTotal", { $0.polishServerMilliseconds }),
                ("modelLoad", { $0.polishModelLoadMilliseconds }),
                ("promptEval", { $0.polishPromptEvalMilliseconds }),
                ("generation", { $0.polishGenerationMilliseconds }),
                ("insert", { $0.insertMilliseconds }),
                ("serialTail", { $0.serialTailMilliseconds }),
            ]
            var result: [String: DictationBaselineStageReport] = [:]
            for (name, value) in extractors {
                let samples = entries.compactMap { entry in
                    entry.timing.flatMap(value)
                }
                if !samples.isEmpty {
                    result[name] = try DictationBaselineStageReport(
                        samplesMilliseconds: samples
                    )
                }
            }
            return result
        }
    }

    struct DictationBaselineFixtureReport: Codable, Equatable {
        let length: DictationBaselineFixtureLength
        let sha256: String
        let expectedTranscript: String
        let durationMilliseconds: Int
        let sampleCount: Int
        let observedRawTranscripts: [String]
    }

    struct DictationBaselineRunReport: Codable, Equatable {
        let schemaVersion: Int
        let recordedAt: Date
        let asrModel: String
        let polishModel: String
        let recordedSamplesPerClass: Int
        let warmUpSamplesDiscardedPerClass: Int
        let insertion: String
        let fixtures: [DictationBaselineFixtureReport]
        let classes: [DictationBaselineClassReport]

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

    @MainActor
    final class DictationBaselineApplication {
        private let plan: DictationBaselinePlan
        private var processActivity: NSObjectProtocol?

        init(plan: DictationBaselinePlan) {
            self.plan = plan
        }

        func start() {
            processActivity = ProcessInfo.processInfo.beginActivity(
                options: [.latencyCritical, .idleSystemSleepDisabled],
                reason: "FoldWise Dictation baseline measurement"
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

        private func run() async throws -> DictationBaselineRunReport {
            let fixtures = try plan.fixtures.map(DictationBaselineAudioFixture.load)
            let config = try makeConfig()
            let lifecycle = ASRModelLifecycle(
                storedSelection: plan.asrModel,
                adapters: [ParakeetASRModelAdapter(), WhisperASRModelAdapter()]
            )
            await lifecycle.start()
            let lifecycleSnapshot = await lifecycle.snapshot()
            guard !lifecycle.isDictationBlocked,
                  lifecycleSnapshot.effectiveSelection == plan.asrModel
            else {
                if let effective = lifecycleSnapshot.effectiveSelection {
                    throw DictationBaselineHarnessError.unexpectedEffectiveASRModel(
                        requested: plan.asrModel,
                        effective: effective
                    )
                }
                throw DictationBaselineHarnessError.asrUnavailable(plan.asrModel)
            }

            let recorder = DictationBaselineRecorder()
            let entries = DictationBaselineEntryCollector()
            let errors = DictationBaselineErrorCollector()
            let ollama = OllamaClient()
            let pipeline = Pipeline(
                config: config,
                recorder: recorder,
                sessionProvider: lifecycle,
                ducker: DictationBaselineAudioDucker(),
                warmPolishModel: { mode in
                    guard let model = mode.llmModel, !model.isEmpty else { return }
                    ollama.scheduleWarm(model: model)
                },
                insert: { _ in true },
                record: { entries.append($0) },
                frontmostApp: { "Dictation baseline harness" }
            )
            pipeline.onState = { state in
                if case let .error(message) = state {
                    errors.record(message)
                }
            }
            defer { pipeline.shutdown() }

            var classReports: [DictationBaselineClassReport] = []
            for shape in DictationBaselineShape.allCases {
                try select(shape, in: config)
                for fixture in fixtures {
                    let warmUp = try await runOne(
                        pipeline: pipeline,
                        recorder: recorder,
                        entries: entries,
                        errors: errors,
                        fixture: fixture,
                        shape: shape
                    )
                    var recorded: [HistoryEntry] = []
                    for _ in 0 ..< plan.sampleCount {
                        recorded.append(try await runOne(
                            pipeline: pipeline,
                            recorder: recorder,
                            entries: entries,
                            errors: errors,
                            fixture: fixture,
                            shape: shape
                        ))
                    }
                    classReports.append(try DictationBaselineClassReport(
                        shape: shape,
                        length: fixture.plan.length,
                        discardedWarmUpTranscript: warmUp.rawText,
                        entries: recorded
                    ))
                }
            }

            let fixtureReports = fixtures.map { fixture in
                let observed = Set(
                    classReports
                        .filter { $0.length == fixture.plan.length }
                        .flatMap(\.samples)
                        .map(\.rawTranscript)
                ).sorted()
                return DictationBaselineFixtureReport(
                    length: fixture.plan.length,
                    sha256: fixture.sha256,
                    expectedTranscript: fixture.plan.expectedTranscript,
                    durationMilliseconds: fixture.durationMilliseconds,
                    sampleCount: fixture.samples.count,
                    observedRawTranscripts: observed
                )
            }
            return DictationBaselineRunReport(
                schemaVersion: 1,
                recordedAt: Date(),
                asrModel: plan.asrModel,
                polishModel: plan.polishModel,
                recordedSamplesPerClass: plan.sampleCount,
                warmUpSamplesDiscardedPerClass: 1,
                insertion: "stubbed",
                fixtures: fixtureReports,
                classes: classReports
            )
        }

        private func makeConfig() throws -> Config {
            let configURL = plan.outputURL
                .deletingLastPathComponent()
                .appendingPathComponent("dictation-baseline-config.json")
            var modes = Config.defaultConfig(path: configURL).orderedModes
            for index in modes.indices {
                modes[index].asrModel = plan.asrModel
                modes[index].llmModel = plan.polishModel
            }
            guard modes.contains(where: { $0.transformation == .inPlace }),
                  modes.contains(where: { $0.transformation == .expanding })
            else {
                throw DictationBaselineHarnessError.missingShippedModes
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

        private func select(_ shape: DictationBaselineShape, in config: Config) throws {
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
                    throw DictationBaselineHarnessError.missingShippedModes
                }
                try config.select(.mode(id))
            }
        }

        private func runOne(
            pipeline: Pipeline,
            recorder: DictationBaselineRecorder,
            entries: DictationBaselineEntryCollector,
            errors: DictationBaselineErrorCollector,
            fixture: DictationBaselineAudioFixture,
            shape: DictationBaselineShape
        ) async throws -> HistoryEntry {
            recorder.prepare(samples: fixture.samples)
            entries.reset()
            errors.reset()
            pipeline.startRecording()
            pipeline.stopRecording()
            await pipeline.awaitPendingJob()
            if let message = errors.message {
                throw DictationBaselineHarnessError.pipeline(message)
            }
            guard let entry = entries.onlyEntry else {
                throw DictationBaselineHarnessError.missingEntry
            }
            guard DictationBaselineTranscriptContract.clearsPolishFloor(entry.rawText) else {
                throw DictationBaselineHarnessError.transcriptBelowPolishFloor(
                    fixture.plan.length,
                    transcript: entry.rawText
                )
            }
            if shape != .voiceToText {
                guard entry.timing?.polishMilliseconds != nil else {
                    throw DictationBaselineHarnessError.polishDidNotRun(
                        fixture.plan.length,
                        transcript: entry.rawText
                    )
                }
            }
            return entry
        }

        private func finish() {
            guard let processActivity else { return }
            ProcessInfo.processInfo.endActivity(processActivity)
            self.processActivity = nil
        }

        private func fail(_ error: Error) {
            finish()
            let message = "Dictation baseline failed: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
            let failureURL = plan.outputURL
                .deletingPathExtension()
                .appendingPathExtension("failure.txt")
            do {
                try message.write(to: failureURL, atomically: true, encoding: .utf8)
            } catch {
                let writeFailure = "Could not write Dictation baseline failure artifact: "
                    + "\(error.localizedDescription)\n"
                FileHandle.standardError.write(Data(writeFailure.utf8))
            }
            NSApp.terminate(nil)
        }
    }

    private final class DictationBaselineRecorder: AudioRecording {
        var onFailure: ((AudioCaptureError) -> Void)?
        private let lock = NSLock()
        private var samples: [Float] = []

        func prepare(samples: [Float]) {
            lock.withLock {
                self.samples = samples
            }
        }

        func start() throws {}

        func stop() -> [Float] {
            lock.withLock { samples }
        }

        func close() {}
    }

    private final class DictationBaselineAudioDucker: AudioDucking {
        func duck() {}
        func restore() {}
    }

    private final class DictationBaselineEntryCollector {
        private let lock = NSLock()
        private var entries: [HistoryEntry] = []

        func append(_ entry: HistoryEntry) {
            lock.withLock {
                entries.append(entry)
            }
        }

        func reset() {
            lock.withLock {
                entries.removeAll(keepingCapacity: true)
            }
        }

        var onlyEntry: HistoryEntry? {
            lock.withLock {
                entries.count == 1 ? entries[0] : nil
            }
        }
    }

    private final class DictationBaselineErrorCollector {
        private let lock = NSLock()
        private var storedMessage: String?

        func record(_ message: String) {
            lock.withLock {
                storedMessage = message
            }
        }

        func reset() {
            lock.withLock {
                storedMessage = nil
            }
        }

        var message: String? {
            lock.withLock { storedMessage }
        }
    }

    enum DictationBaselineHarnessError: LocalizedError {
        case unsupportedSchema(Int)
        case emptyModel
        case invalidSampleCount
        case nonFileURL
        case invalidFixtureMatrix
        case missingFixture(URL)
        case shortExpectedTranscript(DictationBaselineFixtureLength)
        case invalidAudioFormat(URL, sampleRate: Double, channels: AVAudioChannelCount)
        case invalidAudioLength(URL)
        case unreadableFixture(URL)
        case silentFixture(URL)
        case emptySamples
        case asrUnavailable(String)
        case unexpectedEffectiveASRModel(requested: String, effective: String)
        case missingShippedModes
        case pipeline(String)
        case missingEntry
        case missingTiming
        case transcriptBelowPolishFloor(
            DictationBaselineFixtureLength,
            transcript: String
        )
        case polishDidNotRun(DictationBaselineFixtureLength, transcript: String)

        var errorDescription: String? {
            switch self {
            case let .unsupportedSchema(version):
                "Unsupported Dictation baseline plan schema \(version)."
            case .emptyModel:
                "ASR and Polish model identifiers must be nonempty."
            case .invalidSampleCount:
                "Recorded samples per class must be greater than zero."
            case .nonFileURL:
                "Fixture and output locations must be file URLs."
            case .invalidFixtureMatrix:
                "The fixture matrix must contain Short followed by Long exactly once."
            case let .missingFixture(url):
                "Dictation fixture does not exist: \(url.path)"
            case let .shortExpectedTranscript(length):
                "The \(length.rawValue) expected transcript must exceed the Polish floor."
            case let .invalidAudioFormat(url, sampleRate, channels):
                "\(url.lastPathComponent) is \(sampleRate) Hz with \(channels) channels; "
                    + "fixtures must be 16000 Hz mono WAV."
            case let .invalidAudioLength(url):
                "Dictation fixture has an invalid frame length: \(url.path)"
            case let .unreadableFixture(url):
                "Dictation fixture could not be decoded as Float audio: \(url.path)"
            case let .silentFixture(url):
                "Dictation fixture is too short or silent: \(url.path)"
            case .emptySamples:
                "Dictation baseline statistics require at least one sample."
            case let .asrUnavailable(model):
                "Effective ASR model is unavailable after startup: \(model)"
            case let .unexpectedEffectiveASRModel(requested, effective):
                "Requested ASR model \(requested), but the effective model is \(effective)."
            case .missingShippedModes:
                "Shipped in-place and expanding Modes are required by the harness."
            case let .pipeline(message):
                "Pipeline reported an error: \(message)"
            case .missingEntry:
                "Pipeline did not record exactly one completed Dictation session."
            case .missingTiming:
                "Pipeline completed without Dictation-session timing."
            case let .transcriptBelowPolishFloor(length, transcript):
                "The \(length.rawValue) fixture transcript did not clear the Polish "
                    + "floor (\(transcript.count) characters): \(transcript)"
            case let .polishDidNotRun(length, transcript):
                "Polish did not run for the \(length.rawValue) fixture "
                    + "(\(transcript.count) characters): \(transcript)"
            }
        }
    }
#endif
