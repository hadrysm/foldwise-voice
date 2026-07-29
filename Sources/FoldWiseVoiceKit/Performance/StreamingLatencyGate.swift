// The locked perceived-latency budget as an executable release gate (PRD #351).
//
// The three limits are absolute: they came from measured baselines in issue #342
// and this file is the only place that decides whether a run met them. The gate
// recomputes p95 from the raw samples rather than trusting the statistics the
// harness reported, so a harness bug can fail a run but cannot pass one.
//
// Deciding lives here and doing lives in `StreamingLatencyHarness`: everything
// below takes report bytes and returns a verdict, which is why the limits are
// testable without a reference Mac, a speech model, or a microphone.

import Foundation

enum StreamingLatencyFixtureLength: String, Codable, CaseIterable {
    case short
    case long
}

enum StreamingLatencyShape: String, Codable, CaseIterable {
    case voiceToText
    case inPlace
    case expanding
}

/// One measured class of the release matrix. `gated` is a property of the class
/// rather than of the report, so a harness cannot exempt itself from a limit by
/// declaring its own class un-gated.
struct StreamingLatencyClass: Hashable {
    let length: StreamingLatencyFixtureLength
    let shape: StreamingLatencyShape

    /// The post-release limit this class is judged against, or `nil` when the
    /// class is recorded as evidence only. Long-form Polish generation is
    /// deliberately un-gated by this PRD.
    var postReleaseLimitMilliseconds: Double? {
        switch (length, shape) {
        case (.short, _): StreamingLatencyGate.shortPostReleaseLimitMilliseconds
        case (.long, .voiceToText): StreamingLatencyGate.longPostReleaseLimitMilliseconds
        case (.long, .inPlace), (.long, .expanding): nil
        }
    }

    func key(model: String) -> String {
        "\(model)/\(length.rawValue)/\(shape.rawValue)"
    }
}

/// Observed statistics over one class's raw samples. Shared by the harness that
/// records them and the gate that recomputes them, so "the p95 the report shows"
/// and "the p95 the gate judged" can never drift apart.
struct StreamingLatencyStatistics: Codable, Equatable {
    let medianMilliseconds: Double
    let p95Milliseconds: Double
    let worstMilliseconds: Double

    init(samplesMilliseconds: [Double]) throws {
        guard !samplesMilliseconds.isEmpty else {
            throw StreamingLatencyGate.ValidationError.emptySamples
        }
        let sorted = samplesMilliseconds.sorted()
        if sorted.count.isMultiple(of: 2) {
            let upper = sorted.count / 2
            medianMilliseconds = (sorted[upper - 1] + sorted[upper]) / 2
        } else {
            medianMilliseconds = sorted[sorted.count / 2]
        }
        p95Milliseconds = sorted[max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)]
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

enum StreamingLatencyGate {
    /// Speech onset to the first non-empty Live transcript caption render.
    static let firstFeedbackLimitMilliseconds: Double = 1200
    /// Hotkey release to the completed insert effect, short fixture.
    static let shortPostReleaseLimitMilliseconds: Double = 1000
    /// Hotkey release to the completed insert effect, long fixture.
    static let longPostReleaseLimitMilliseconds: Double = 1500
    /// The samples an authoritative run records per class, after one discarded
    /// warm-up.
    static let requiredSampleCount = 20

    /// Every Streaming ASR model the catalog ships, read from the catalog rather
    /// than restated, so shipping a third one fails the matrix until it is
    /// measured.
    static var streamingModelIDs: [String] {
        ASRModelCatalog.entries.filter(\.streaming).map(\.id)
    }

    /// The full matrix. Short covers all three Dictation shapes because the
    /// 1 second target names all three; long records Polish evidence beyond its
    /// one gated Voice to Text class.
    static let requiredClasses: [StreamingLatencyClass] = StreamingLatencyFixtureLength
        .allCases
        .flatMap { length in
            StreamingLatencyShape.allCases.map {
                StreamingLatencyClass(length: length, shape: $0)
            }
        }

    struct Result: Equatable {
        var firstFeedbackViolations: [String] = []
        var postReleaseViolations: [String] = []
        var missingClasses: [String] = []
        var sampleCountViolations: [String] = []
        var authorityViolations: [String] = []
        var environmentViolations: [String] = []
        var residencyViolations: [String] = []
        var fixtureDrift: [String] = []
        var missingEvidence: [String] = []
        var isAuthoritative = false
        /// Whether this run may replace the accepted baseline. An unreviewed
        /// memory ceiling blocks acceptance without failing the duration gate,
        /// because the ceiling is a human judgment and the limits are not.
        var permitsBaselineUpdate = false

        static let passed = Result(isAuthoritative: true, permitsBaselineUpdate: true)

        /// Whether every limit this run was judged against held.
        var isPassing: Bool {
            [
                firstFeedbackViolations,
                postReleaseViolations,
                missingClasses,
                sampleCountViolations,
                authorityViolations,
                environmentViolations,
                residencyViolations,
                fixtureDrift,
                missingEvidence,
            ].allSatisfy(\.isEmpty)
        }

        /// Report order is matrix-iteration order, which makes a diff between two
        /// runs read as noise. Sorting makes the evidence comparable.
        fileprivate mutating func sort() {
            firstFeedbackViolations.sort()
            postReleaseViolations.sort()
            missingClasses.sort()
            sampleCountViolations.sort()
            authorityViolations.sort()
            environmentViolations.sort()
            residencyViolations.sort()
            fixtureDrift.sort()
            missingEvidence.sort()
        }
    }

    enum ValidationError: LocalizedError {
        case emptySamples
        case unsupportedReportSchema(Int)
        case unsupportedBaselineSchema(Int)

        var errorDescription: String? {
            switch self {
            case .emptySamples:
                "Streaming latency statistics require at least one sample."
            case let .unsupportedReportSchema(version):
                "Unsupported streaming latency report schema \(version)."
            case let .unsupportedBaselineSchema(version):
                "Unsupported streaming latency baseline schema \(version)."
            }
        }
    }

    /// Judges one recorded run. Completeness and sample counts are only asked of
    /// an authoritative run: a smoke run deliberately measures a subset, and it
    /// is stopped from becoming a baseline by `permitsBaselineUpdate` rather than
    /// by failing checks it never claimed to satisfy.
    static func evaluate(reportData: Data, baselineData: Data) throws -> Result {
        let report = try decodeReport(reportData)
        let baseline = try decodeBaseline(baselineData)
        var result = Result(isAuthoritative: report.authoritative)
        result.environmentViolations = environmentViolations(report, baseline: baseline)
        result.fixtureDrift = fixtureDrift(report, baseline: baseline)
        result.missingEvidence = missingFixtureEvidence(report)
        result.residencyViolations = memoryCeilingViolations(report, baseline: baseline)

        let measured = Dictionary(
            report.models.map { ($0.asrModel, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        if report.authoritative, report.recordedSamplesPerClass != requiredSampleCount {
            result.sampleCountViolations.append(
                "report records \(report.recordedSamplesPerClass) samples per class, not "
                    + "\(requiredSampleCount)"
            )
        }
        for modelID in streamingModelIDs {
            guard let model = measured[modelID] else {
                if report.authoritative {
                    result.missingClasses += requiredClasses.map { $0.key(model: modelID) }
                }
                continue
            }
            evaluate(model, authoritative: report.authoritative, into: &result)
        }
        result.sort()
        result.permitsBaselineUpdate = result.isPassing
            && report.authoritative
            && report.memoryCeiling.humanReviewed
        return result
    }

    /// Recomputed rather than read back from the report, and exposed so the exact
    /// index the limits are read at is pinned by its own test.
    static func p95Milliseconds(of samplesMilliseconds: [Double]) throws -> Double {
        try StreamingLatencyStatistics(samplesMilliseconds: samplesMilliseconds)
            .p95Milliseconds
    }

    // MARK: - per model

    private static func evaluate(
        _ model: Model,
        authoritative: Bool,
        into result: inout Result
    ) {
        if model.effectiveASRModel != model.asrModel {
            result.authorityViolations.append(
                "\(model.asrModel): effective ASR model fell back to \(model.effectiveASRModel)"
            )
        }
        result.residencyViolations += residencyViolations(model)

        let classes = Dictionary(
            model.classes.map {
                (StreamingLatencyClass(length: $0.length, shape: $0.shape), $0)
            },
            uniquingKeysWith: { first, _ in first }
        )
        var firstFeedback: [Double] = []
        for required in requiredClasses {
            let key = required.key(model: model.asrModel)
            guard let measured = classes[required] else {
                if authoritative {
                    result.missingClasses.append(key)
                }
                continue
            }
            if authoritative, measured.samples.count != requiredSampleCount {
                result.sampleCountViolations.append(
                    "\(key) recorded \(measured.samples.count) samples, not \(requiredSampleCount)"
                )
            }
            firstFeedback += measured.samples.compactMap(\.firstFeedbackMilliseconds)
            result.missingEvidence += missingEvidence(in: measured, key: key)
            result.authorityViolations += authorityViolations(in: measured, key: key)
            evaluatePostRelease(measured, required: required, key: key, into: &result)
        }
        evaluateFirstFeedback(firstFeedback, model: model.asrModel, into: &result)
    }

    private static func evaluateFirstFeedback(
        _ samples: [Double],
        model: String,
        into result: inout Result
    ) {
        guard let p95 = try? p95Milliseconds(of: samples) else { return }
        guard p95 > firstFeedbackLimitMilliseconds else { return }
        result.firstFeedbackViolations.append(
            "\(model): first feedback p95 \(formatted(p95)) ms exceeds "
                + "\(formatted(firstFeedbackLimitMilliseconds)) ms"
        )
    }

    private static func evaluatePostRelease(
        _ measured: MeasuredClass,
        required: StreamingLatencyClass,
        key: String,
        into result: inout Result
    ) {
        guard let limit = required.postReleaseLimitMilliseconds else { return }
        let samples = measured.samples.compactMap(\.postReleaseMilliseconds)
        guard let p95 = try? p95Milliseconds(of: samples), p95 > limit else { return }
        result.postReleaseViolations.append(
            "\(key): post-release p95 \(formatted(p95)) ms exceeds \(formatted(limit)) ms"
        )
    }

    // MARK: - authority

    /// One Dictation session's authority invariants (ADR-0009). Read per sample
    /// rather than per class so a single bad session cannot be averaged away.
    private static func authorityViolations(
        in measured: MeasuredClass,
        key: String
    ) -> [String] {
        var violations: [String] = []
        for sample in measured.samples {
            let label = "\(key) sample \(sample.index)"
            if sample.batchTranscriptionCalls > 0 {
                violations.append(
                    "\(label): healthy streaming session ran "
                        + "\(sample.batchTranscriptionCalls) batch transcriptions"
                )
            }
            if sample.insertions != 1 {
                violations.append("\(label): \(sample.insertions) insertions, not exactly one")
            }
            if sample.pipelineRawDigest.isEmpty
                || sample.pipelineRawDigest != sample.historyRawDigest {
                violations.append("\(label): Pipeline and History disagree on the raw final")
            }
            if measured.shape == .voiceToText, sample.insertedDigest != sample.pipelineRawDigest {
                violations.append("\(label): Voice to Text inserted text is not the raw final")
            }
            if sample.firstFeedbackMilliseconds != nil, !sample.captionRendered {
                violations.append("\(label): first feedback claimed without a caption render")
            }
        }
        return violations
    }

    private static func missingEvidence(in measured: MeasuredClass, key: String) -> [String] {
        var missing: [String] = []
        for sample in measured.samples {
            let label = "\(key) sample \(sample.index)"
            if sample.firstFeedbackMilliseconds == nil {
                missing.append("\(label): no caption render timing")
            }
            if sample.postReleaseMilliseconds == nil {
                missing.append("\(label): no post-release finish timing")
            }
        }
        return missing
    }

    // MARK: - residency

    /// One Effective ASR model at a time (ADR-0005). The gate refuses a run that
    /// measured two resident engines rather than quietly reporting the sum.
    private static func residencyViolations(_ model: Model) -> [String] {
        var violations: [String] = []
        let residency = model.residency
        if residency.residentASREngineCount != 1 {
            violations.append(
                "\(model.asrModel): \(residency.residentASREngineCount) resident ASR engines, "
                    + "not exactly one"
            )
        }
        if residency.peakFootprintBytes <= 0 {
            violations.append("\(model.asrModel): no integrated peak footprint recorded")
        }
        if residency.maximumResidentBytes <= 0 {
            violations.append("\(model.asrModel): no integrated maximum RSS recorded")
        }
        return violations
    }

    private static func memoryCeilingViolations(
        _ report: Report,
        baseline: Baseline
    ) -> [String] {
        let observed = report.memoryCeiling.standaloneMaximumResidentBytes
        guard observed == baseline.standaloneMaximumResidentBytes else {
            return [
                "memory ceiling compares against \(observed) bytes, not the documented "
                    + "\(baseline.standaloneMaximumResidentBytes) bytes",
            ]
        }
        return []
    }

    // MARK: - environment and fixtures

    private static func environmentViolations(_ report: Report, baseline: Baseline) -> [String] {
        var violations: [String] = []
        let environment = report.environment
        if environment.referenceMac != baseline.referenceMac {
            violations.append(
                "measured on \(environment.referenceMac), not the reference "
                    + "\(baseline.referenceMac)"
            )
        }
        if environment.buildConfiguration != "Release" {
            violations.append("build configuration is \(environment.buildConfiguration)")
        }
        if environment.debuggerAttached {
            violations.append("a debugger was attached")
        }
        if environment.codeCoverage {
            violations.append("code coverage instrumentation was enabled")
        }
        if environment.sanitizers {
            violations.append("sanitizers were enabled")
        }
        let recorded: [(String, String)] = [
            ("commit", environment.commit),
            ("appVersion", environment.appVersion),
            ("hardwareModel", environment.hardwareModel),
            ("chip", environment.chip),
            ("memoryBytes", environment.memoryBytes),
            ("macOS", environment.macOS),
            ("xcode", environment.xcode),
            ("power", environment.power),
            ("thermal", environment.thermal),
        ]
        violations += recorded
            .filter(\.1.isEmpty)
            .map { "environment did not record \($0.0)" }
        return violations
    }

    /// A fixture the accepted baseline has not pinned yet is not drift — the
    /// first accepted run is what pins it.
    private static func fixtureDrift(_ report: Report, baseline: Baseline) -> [String] {
        report.fixtures.compactMap { fixture in
            guard let accepted = baseline.fixtures[fixture.length.rawValue],
                  accepted != fixture.sha256
            else { return nil }
            return "\(fixture.length.rawValue) fixture is \(fixture.sha256), "
                + "not the accepted \(accepted)"
        }
    }

    private static func missingFixtureEvidence(_ report: Report) -> [String] {
        let recorded = Dictionary(
            report.fixtures.map { ($0.length, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return StreamingLatencyFixtureLength.allCases.compactMap { length in
            guard let fixture = recorded[length] else {
                return "\(length.rawValue) fixture is missing from the report"
            }
            guard fixture.sha256.isEmpty || fixture.durationSeconds <= 0 else { return nil }
            return "\(length.rawValue) fixture recorded no hash or no duration"
        }
    }

    private static func formatted(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    // MARK: - decoding

    private static func decodeReport(_ data: Data) throws -> Report {
        let report = try JSONDecoder().decode(Report.self, from: data)
        guard report.schemaVersion == 1 else {
            throw ValidationError.unsupportedReportSchema(report.schemaVersion)
        }
        return report
    }

    private static func decodeBaseline(_ data: Data) throws -> Baseline {
        let baseline = try JSONDecoder().decode(Baseline.self, from: data)
        guard baseline.schemaVersion == 1 else {
            throw ValidationError.unsupportedBaselineSchema(baseline.schemaVersion)
        }
        return baseline
    }

    /// The reviewed facts a run is held against. Deliberately small: the three
    /// duration limits are locked in code, not in a file a run could edit, so the
    /// baseline only records what a reference Mac and its fixtures are.
    private struct Baseline: Decodable {
        let schemaVersion: Int
        let referenceMac: String
        let standaloneMaximumResidentBytes: Int
        /// Accepted fixture hashes by length. Empty until a first authoritative run
        /// is accepted, which is what pins them.
        let fixtures: [String: String]
    }

    private struct Report: Decodable {
        let schemaVersion: Int
        let authoritative: Bool
        let recordedSamplesPerClass: Int
        let environment: Environment
        let fixtures: [Fixture]
        let memoryCeiling: MemoryCeiling
        let models: [Model]
    }

    private struct Environment: Decodable {
        let referenceMac: String
        let buildConfiguration: String
        let debuggerAttached: Bool
        let codeCoverage: Bool
        let sanitizers: Bool
        let commit: String
        let appVersion: String
        let hardwareModel: String
        let chip: String
        let memoryBytes: String
        let macOS: String
        let xcode: String
        let power: String
        let thermal: String
    }

    private struct Fixture: Decodable {
        let length: StreamingLatencyFixtureLength
        let sha256: String
        let durationSeconds: Double
    }

    private struct MemoryCeiling: Decodable {
        let standaloneMaximumResidentBytes: Int
        let humanReviewed: Bool
    }

    private struct Model: Decodable {
        let asrModel: String
        let effectiveASRModel: String
        let residency: Residency
        let classes: [MeasuredClass]
    }

    private struct Residency: Decodable {
        let peakFootprintBytes: Int
        let maximumResidentBytes: Int
        let residentASREngineCount: Int
    }

    private struct MeasuredClass: Decodable {
        let length: StreamingLatencyFixtureLength
        let shape: StreamingLatencyShape
        let samples: [Sample]
    }

    private struct Sample: Decodable {
        let index: Int
        let firstFeedbackMilliseconds: Double?
        let postReleaseMilliseconds: Double?
        let captionRendered: Bool
        let batchTranscriptionCalls: Int
        let insertions: Int
        let pipelineRawDigest: String
        let historyRawDigest: String
        let insertedDigest: String
    }
}
