import Foundation
import XCTest
@testable import FoldWiseVoiceKit

final class StreamingLatencyGateTests: XCTestCase {
    // MARK: - the locked limits

    func testFirstFeedbackPassesAtExactlyTwelveHundredMilliseconds() throws {
        let result = try evaluate(Run(firstFeedback: 1200))

        XCTAssertEqual(result.firstFeedbackViolations, [])
    }

    func testFirstFeedbackFailsJustAboveTwelveHundredMilliseconds() throws {
        let result = try evaluate(Run(firstFeedback: 1200.001))

        XCTAssertEqual(result.firstFeedbackViolations.count, 2)
    }

    func testFirstFeedbackViolationNamesTheModelAndBothNumbers() throws {
        let result = try evaluate(Run(firstFeedback: 1300))

        XCTAssertEqual(
            result.firstFeedbackViolations,
            [
                "nemotron-560: first feedback p95 1300.0 ms exceeds 1200.0 ms",
                "parakeet-eou-320: first feedback p95 1300.0 ms exceeds 1200.0 ms",
            ]
        )
    }

    func testShortPostReleasePassesAtExactlyOneThousandMilliseconds() throws {
        let result = try evaluate(Run(shortPostRelease: 1000))

        XCTAssertEqual(result.postReleaseViolations, [])
    }

    func testShortPostReleaseFailsJustAboveOneThousandMillisecondsInEveryShape() throws {
        let result = try evaluate(Run(shortPostRelease: 1000.001))

        XCTAssertEqual(
            result.postReleaseViolations.map { String($0.prefix(while: { $0 != ":" })) },
            [
                "nemotron-560/short/expanding",
                "nemotron-560/short/inPlace",
                "nemotron-560/short/voiceToText",
                "parakeet-eou-320/short/expanding",
                "parakeet-eou-320/short/inPlace",
                "parakeet-eou-320/short/voiceToText",
            ]
        )
    }

    func testLongVoiceToTextPassesAtExactlyFifteenHundredMilliseconds() throws {
        let result = try evaluate(Run(longVoiceToTextPostRelease: 1500))

        XCTAssertEqual(result.postReleaseViolations, [])
    }

    func testLongVoiceToTextFailsJustAboveFifteenHundredMilliseconds() throws {
        let result = try evaluate(Run(longVoiceToTextPostRelease: 1500.001))

        XCTAssertEqual(
            result.postReleaseViolations.map { String($0.prefix(while: { $0 != ":" })) },
            ["nemotron-560/long/voiceToText", "parakeet-eou-320/long/voiceToText"]
        )
    }

    func testLongPolishClassesAreRecordedButNeverGated() throws {
        let result = try evaluate(Run(longPolishPostRelease: 9999))

        XCTAssertEqual(result.postReleaseViolations, [])
    }

    // MARK: - p95

    func testP95ReadsTheObservedSampleRatherThanInterpolating() throws {
        let p95 = try StreamingLatencyGate.p95Milliseconds(
            of: [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
        )

        XCTAssertEqual(p95, 100)
    }

    func testP95IsRecomputedFromRawSamplesRatherThanReadFromTheReport() throws {
        let result = try evaluate(Run(firstFeedback: 5000))

        XCTAssertEqual(result.firstFeedbackViolations.count, 2)
    }

    // MARK: - matrix completeness

    func testAuthoritativeRunRequiresEveryClassOfBothStreamingModels() throws {
        var payload = report()
        payload["models"] = Array(models(Run()).prefix(1))

        let result = try evaluate(payload)

        XCTAssertEqual(result.missingClasses.count, StreamingLatencyGate.requiredClasses.count)
    }

    func testAuthoritativeRunRequiresTwentySamplesPerClass() throws {
        let result = try evaluate(Run(samplesPerClass: 19))

        XCTAssertEqual(result.sampleCountViolations.count, 1 + 2 * 6)
    }

    func testSmokeRunSkipsCompletenessButCannotUpdateTheBaseline() throws {
        let result = try evaluate(Run(samplesPerClass: 1, authoritative: false))

        XCTAssertEqual(
            [result.isPassing, result.isAuthoritative, result.permitsBaselineUpdate],
            [true, false, false]
        )
    }

    // MARK: - authority

    func testHealthyStreamingSessionMayNotRunBatchTranscription() throws {
        let result = try evaluate(Run(batchTranscriptionCalls: 1))

        XCTAssertEqual(result.authorityViolations.count, 2 * 6 * 20)
    }

    func testMoreThanOneInsertionFailsTheRun() throws {
        let result = try evaluate(Run(insertions: 2))

        XCTAssertEqual(result.authorityViolations.count, 2 * 6 * 20)
    }

    func testPipelineAndHistoryMustConsumeTheSameRawFinal() throws {
        let result = try evaluate(Run(historyRawDigest: "different"))

        XCTAssertEqual(result.authorityViolations.count, 2 * 6 * 20)
    }

    func testVoiceToTextMustInsertTheRawFinalUnchanged() throws {
        let result = try evaluate(Run(insertedDigest: "polished"))

        XCTAssertEqual(result.authorityViolations.count, 2 * 2 * 20)
    }

    func testFirstFeedbackMayNotBeClaimedWithoutACaptionRender() throws {
        let result = try evaluate(Run(captionRendered: false))

        XCTAssertEqual(result.authorityViolations.count, 2 * 6 * 20)
    }

    func testFallbackToAnUnexpectedEffectiveASRModelFailsTheRun() throws {
        let result = try evaluate(Run(effectiveASRModel: "parakeet-v3"))

        XCTAssertEqual(
            result.authorityViolations,
            [
                "nemotron-560: effective ASR model fell back to parakeet-v3",
                "parakeet-eou-320: effective ASR model fell back to parakeet-v3",
            ]
        )
    }

    // MARK: - evidence

    func testMissingCaptionTimingIsAnEvidenceFailure() throws {
        let result = try evaluate(Run(firstFeedback: nil))

        XCTAssertEqual(result.missingEvidence.count, 2 * 6 * 20)
    }

    func testMissingFinishTimingIsAnEvidenceFailure() throws {
        let result = try evaluate(
            Run(
                shortPostRelease: nil,
                longVoiceToTextPostRelease: nil,
                longPolishPostRelease: nil
            )
        )

        XCTAssertEqual(result.missingEvidence.count, 2 * 6 * 20)
    }

    func testFixtureDriftFromTheAcceptedHashFailsTheRun() throws {
        let result = try evaluate(
            baseline: baseline(fixtures: ["short": "accepted-short-hash"])
        )

        XCTAssertEqual(
            result.fixtureDrift,
            ["short fixture is short-hash, not the accepted accepted-short-hash"]
        )
    }

    // MARK: - environment

    func testANonReferenceMacFailsTheRun() throws {
        let result = try evaluate(
            Run(environment: Self.environment(referenceMac: "someone's laptop"))
        )

        XCTAssertEqual(
            result.environmentViolations,
            ["measured on someone's laptop, not the reference foldwise-streaming-reference"]
        )
    }

    func testADebuggerCoverageOrSanitizerBuildFailsTheRun() throws {
        let result = try evaluate(
            Run(
                environment: Self.environment(
                    buildConfiguration: "Debug",
                    debuggerAttached: true,
                    codeCoverage: true,
                    sanitizers: true
                )
            )
        )

        XCTAssertEqual(result.environmentViolations.count, 4)
    }

    func testEnvironmentMustRecordEveryDocumentedFact() throws {
        let result = try evaluate(Run(environment: Self.environment(thermal: "")))

        XCTAssertEqual(result.environmentViolations, ["environment did not record thermal"])
    }

    // MARK: - single-model residency

    func testTwoResidentASREnginesFailTheRun() throws {
        let result = try evaluate(Run(residentASREngineCount: 2))

        XCTAssertEqual(result.residencyViolations.count, 2)
    }

    func testMissingResidencyEvidenceFailsTheRun() throws {
        let result = try evaluate(Run(peakFootprintBytes: 0, maximumResidentBytes: 0))

        XCTAssertEqual(result.residencyViolations.count, 4)
    }

    func testMemoryCeilingMustCompareAgainstTheDocumentedStandaloneObservation() throws {
        let result = try evaluate(Run(standaloneMaximumResidentBytes: 900_000_000))

        XCTAssertEqual(
            result.residencyViolations,
            [
                "memory ceiling compares against 900000000 bytes, not the documented "
                    + "1227000000 bytes",
            ]
        )
    }

    // MARK: - baseline updates

    func testAPassingAuthoritativeReviewedRunMayUpdateTheBaseline() throws {
        let result = try evaluate()

        XCTAssertEqual(result, .passed)
    }

    func testAnUnreviewedMemoryCeilingBlocksAcceptanceWithoutFailingTheGate() throws {
        let result = try evaluate(Run(memoryCeilingReviewed: false))

        XCTAssertEqual([result.isPassing, result.permitsBaselineUpdate], [true, false])
    }

    func testAnUnsupportedReportSchemaIsRejected() throws {
        var payload = report()
        payload["schemaVersion"] = 2

        XCTAssertThrowsError(try evaluate(payload))
    }

    func testTheShippedBaselineIsReadableByTheGate() throws {
        let result = try StreamingLatencyGate.evaluate(
            reportData: try JSONSerialization.data(withJSONObject: report()),
            baselineData: try Data(contentsOf: Self.shippedBaselineURL)
        )

        XCTAssertEqual(result, .passed)
    }

    // MARK: - the retained fixed-Mac report

    func testFixedMacReportMeetsTheLockedLatencyBudget() throws {
        let variables = ProcessInfo.processInfo.environment
        guard let reportPath = variables["FOLDWISE_STREAMING_LATENCY_REPORT"],
              let baselinePath = variables["FOLDWISE_STREAMING_LATENCY_BASELINES"]
        else {
            throw XCTSkip(
                "The fixed-Mac Release lane supplies its retained report and baselines."
            )
        }

        let result = try StreamingLatencyGate.evaluate(
            reportData: try Data(contentsOf: URL(fileURLWithPath: reportPath)),
            baselineData: try Data(contentsOf: URL(fileURLWithPath: baselinePath))
        )

        XCTAssertEqual(result, .passed)
    }

    // MARK: - fixtures

    /// The knobs a test turns. One value rather than a dozen parameters threaded
    /// through three builders: every field defaults to a run that passes every
    /// gate, so a test names only the fact it is changing.
    private struct Run {
        var samplesPerClass = 20
        var authoritative = true
        var firstFeedback: Double? = 900
        var shortPostRelease: Double? = 700
        var longVoiceToTextPostRelease: Double? = 1100
        var longPolishPostRelease: Double? = 1400
        var captionRendered = true
        var batchTranscriptionCalls = 0
        var insertions = 1
        var historyRawDigest = "raw"
        var insertedDigest = "raw"
        var effectiveASRModel: String?
        var peakFootprintBytes = 900_000_000
        var maximumResidentBytes = 1_100_000_000
        var residentASREngineCount = 1
        var standaloneMaximumResidentBytes = 1_227_000_000
        var memoryCeilingReviewed = true
        var environment: [String: Any] = StreamingLatencyGateTests.environment()

        func postRelease(for measured: StreamingLatencyClass) -> Double? {
            switch (measured.length, measured.shape) {
            case (.short, _): shortPostRelease
            case (.long, .voiceToText): longVoiceToTextPostRelease
            case (.long, .inPlace), (.long, .expanding): longPolishPostRelease
            }
        }
    }

    /// `docs/streaming-latency-baselines.json`, reached from this file rather than
    /// from the working directory so the check does not depend on how tests are run.
    private static let shippedBaselineURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("docs/streaming-latency-baselines.json")

    private func evaluate(
        _ run: Run = Run(),
        baseline: [String: Any]? = nil
    ) throws -> StreamingLatencyGate.Result {
        try evaluate(report(run), baseline: baseline)
    }

    private func evaluate(
        _ report: [String: Any],
        baseline: [String: Any]? = nil
    ) throws -> StreamingLatencyGate.Result {
        try StreamingLatencyGate.evaluate(
            reportData: try JSONSerialization.data(withJSONObject: report),
            baselineData: try JSONSerialization.data(withJSONObject: baseline ?? self.baseline())
        )
    }

    private func report(_ run: Run = Run()) -> [String: Any] {
        [
            "schemaVersion": 1,
            "authoritative": run.authoritative,
            "recordedSamplesPerClass": run.samplesPerClass,
            "environment": run.environment,
            "fixtures": [
                ["length": "short", "sha256": "short-hash", "durationSeconds": 5.1],
                ["length": "long", "sha256": "long-hash", "durationSeconds": 17.2],
            ],
            "memoryCeiling": [
                "standaloneMaximumResidentBytes": run.standaloneMaximumResidentBytes,
                "humanReviewed": run.memoryCeilingReviewed,
            ],
            "models": models(run),
        ]
    }

    private func models(_ run: Run) -> [[String: Any]] {
        StreamingLatencyGate.streamingModelIDs.map { modelID in
            [
                "asrModel": modelID,
                "effectiveASRModel": run.effectiveASRModel ?? modelID,
                "residency": [
                    "peakFootprintBytes": run.peakFootprintBytes,
                    "maximumResidentBytes": run.maximumResidentBytes,
                    "residentASREngineCount": run.residentASREngineCount,
                ],
                "classes": StreamingLatencyGate.requiredClasses.map { measured in
                    self.measuredClass(measured, run: run)
                },
            ]
        }
    }

    private func measuredClass(
        _ measured: StreamingLatencyClass,
        run: Run
    ) -> [String: Any] {
        [
            "length": measured.length.rawValue,
            "shape": measured.shape.rawValue,
            "samples": (1 ... run.samplesPerClass).map { index in
                self.sample(index: index, run: run, measured: measured)
            },
        ]
    }

    private func sample(
        index: Int,
        run: Run,
        measured: StreamingLatencyClass
    ) -> [String: Any] {
        [
            "index": index,
            "firstFeedbackMilliseconds": json(run.firstFeedback),
            "postReleaseMilliseconds": json(run.postRelease(for: measured)),
            "captionRendered": run.captionRendered,
            "batchTranscriptionCalls": run.batchTranscriptionCalls,
            "insertions": run.insertions,
            "pipelineRawDigest": "raw",
            "historyRawDigest": run.historyRawDigest,
            "insertedDigest": run.insertedDigest,
        ]
    }

    private static func environment(
        referenceMac: String = "foldwise-streaming-reference",
        buildConfiguration: String = "Release",
        debuggerAttached: Bool = false,
        codeCoverage: Bool = false,
        sanitizers: Bool = false,
        thermal: String = "No thermal warning level has been recorded"
    ) -> [String: Any] {
        [
            "referenceMac": referenceMac,
            "buildConfiguration": buildConfiguration,
            "debuggerAttached": debuggerAttached,
            "codeCoverage": codeCoverage,
            "sanitizers": sanitizers,
            "commit": "0123456789abcdef",
            "appVersion": "0.17.0",
            "hardwareModel": "Mac15,3",
            "chip": "Apple M3",
            "memoryBytes": "17179869184",
            "macOS": "ProductVersion: 15.0",
            "xcode": "Xcode 16.0",
            "power": "AC Power",
            "thermal": thermal,
        ]
    }

    private func baseline(fixtures: [String: String] = [:]) -> [String: Any] {
        [
            "schemaVersion": 1,
            "referenceMac": "foldwise-streaming-reference",
            "standaloneMaximumResidentBytes": 1_227_000_000,
            "fixtures": fixtures,
        ]
    }

    private func json(_ value: Double?) -> Any {
        value.map { $0 as Any } ?? NSNull()
    }
}
