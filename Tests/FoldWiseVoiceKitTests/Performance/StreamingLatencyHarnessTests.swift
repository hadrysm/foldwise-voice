import CryptoKit
import Foundation
import XCTest
@testable import FoldWiseVoiceKit

final class StreamingLatencyHarnessBuildTests: XCTestCase {
    func testBuildAvailabilityMatchesCompilerFlag() {
        #if STREAMING_LATENCY_HARNESS
            XCTAssertTrue(StreamingLatencyHarnessBuild.isEnabled)
        #else
            XCTAssertFalse(StreamingLatencyHarnessBuild.isEnabled)
        #endif
    }
}

#if STREAMING_LATENCY_HARNESS
    final class StreamingLatencyHarnessTests: XCTestCase {
        private let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("foldwise-streaming-latency-\(UUID().uuidString)")

        override func setUpWithError() throws {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        override func tearDownWithError() throws {
            try FileManager.default.removeItem(at: directory)
        }

        func testPlanLoadsOneStreamingModelAndItsPrivateFixtures() throws {
            let loaded = try StreamingLatencyPlan.load(from: try writePlan())

            XCTAssertEqual(
                loaded,
                StreamingLatencyPlan(
                    schemaVersion: 1,
                    asrModel: "parakeet-eou-320",
                    polishModel: "qwen2.5:3b",
                    sampleCount: 20,
                    insertConstantMilliseconds: 62.5,
                    outputURL: directory.appendingPathComponent("result.json"),
                    fixtures: [
                        StreamingLatencyFixturePlan(
                            length: .short,
                            audioURL: directory.appendingPathComponent("short.wav")
                        ),
                        StreamingLatencyFixturePlan(
                            length: .long,
                            audioURL: directory.appendingPathComponent("long.wav")
                        ),
                    ]
                )
            )
        }

        func testPlanRejectsANonStreamingASRModel() throws {
            let url = try writePlan(asrModel: "parakeet-v3")

            XCTAssertThrowsError(try StreamingLatencyPlan.load(from: url))
        }

        func testPlanRejectsAnInsertConstantBelowThePasteDelay() throws {
            let url = try writePlan(insertConstantMilliseconds: 49.9)

            XCTAssertThrowsError(try StreamingLatencyPlan.load(from: url))
        }

        func testPlanRejectsAnIncompleteFixtureMatrix() throws {
            let url = try writePlan(lengths: ["short"])

            XCTAssertThrowsError(try StreamingLatencyPlan.load(from: url))
        }

        func testSpeechOnsetIsTheFirstVoicedSampleRatherThanTheBufferStart() {
            let fixture = StreamingLatencyAudioFixture(
                plan: StreamingLatencyFixturePlan(
                    length: .short,
                    audioURL: directory.appendingPathComponent("short.wav")
                ),
                samples: Array(repeating: 0, count: 8000) + Array(repeating: 0.4, count: 8000),
                sha256: "hash"
            )

            XCTAssertEqual(fixture.speechOnsetSeconds, 0.5, accuracy: 0.0001)
        }

        /// The seam the two halves meet on: what the harness writes has to be what
        /// the gate reads. Without this, a renamed report field would only be
        /// caught by a two-hour run on the reference Mac.
        func testWhatTheHarnessRecordsIsWhatTheGateAccepts() throws {
            let merged = try mergedReport(
                models: StreamingLatencyGate.streamingModelIDs.map { modelReport($0) }
            )

            let result = try StreamingLatencyGate.evaluate(
                reportData: merged,
                baselineData: try shippedBaseline()
            )

            XCTAssertEqual(result, .passed)
        }

        func testTheGateReadsTheHarnessReportedFirstFeedbackAsAViolation() throws {
            let merged = try mergedReport(
                models: StreamingLatencyGate.streamingModelIDs.map {
                    modelReport($0, firstFeedbackMilliseconds: 1300)
                }
            )

            let result = try StreamingLatencyGate.evaluate(
                reportData: merged,
                baselineData: try shippedBaseline()
            )

            XCTAssertEqual(result.firstFeedbackViolations.count, 2)
        }

        /// The envelope `scripts/run_streaming_latency.py` wraps the per-model
        /// reports in, built here from the harness's own encoded output.
        private func mergedReport(models: [StreamingLatencyModelReport]) throws -> Data {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let encoded = try models.map { model in
                try JSONSerialization.jsonObject(with: try encoder.encode(model))
            }
            return try JSONSerialization.data(withJSONObject: [
                "schemaVersion": 1,
                "authoritative": true,
                "recordedSamplesPerClass": StreamingLatencyGate.requiredSampleCount,
                "environment": [
                    "referenceMac": "foldwise-streaming-reference",
                    "buildConfiguration": "Release",
                    "debuggerAttached": false,
                    "codeCoverage": false,
                    "sanitizers": false,
                    "commit": "0123456789abcdef",
                    "appVersion": "0.17.0",
                    "hardwareModel": "Mac15,3",
                    "chip": "Apple M3",
                    "memoryBytes": "17179869184",
                    "macOS": "ProductVersion: 15.0",
                    "xcode": "Xcode 16.0",
                    "power": "AC Power",
                    "thermal": "No thermal warning level has been recorded",
                ],
                "fixtures": [
                    ["length": "short", "sha256": "short-hash", "durationSeconds": 5.1],
                    ["length": "long", "sha256": "long-hash", "durationSeconds": 17.2],
                ],
                "memoryCeiling": [
                    "standaloneMaximumResidentBytes": 1_227_000_000,
                    "humanReviewed": true,
                ],
                "models": encoded,
            ])
        }

        private func modelReport(
            _ asrModel: String,
            firstFeedbackMilliseconds: Double = 900
        ) -> StreamingLatencyModelReport {
            StreamingLatencyModelReport(
                schemaVersion: 1,
                recordedAt: Date(timeIntervalSince1970: 0),
                asrModel: asrModel,
                effectiveASRModel: asrModel,
                polishModel: "qwen2.5:3b",
                recordedSamplesPerClass: StreamingLatencyGate.requiredSampleCount,
                warmUpSamplesDiscardedPerClass: 1,
                insertion: "stubbed plus the separately measured Accessibility constant",
                insertConstantMilliseconds: 62.5,
                fixtures: [
                    StreamingLatencyFixtureReport(
                        length: .short, sha256: "short-hash", durationSeconds: 5.1,
                        speechOnsetSeconds: 0.2, observedRawTranscripts: ["hello there"]
                    ),
                    StreamingLatencyFixtureReport(
                        length: .long, sha256: "long-hash", durationSeconds: 17.2,
                        speechOnsetSeconds: 0.3, observedRawTranscripts: ["hello again"]
                    ),
                ],
                residency: StreamingLatencyResidencyReport(
                    peakFootprintBytes: 900_000_000,
                    maximumResidentBytes: 1_100_000_000,
                    residentASREngineCount: 1
                ),
                classes: StreamingLatencyGate.requiredClasses.map { measured in
                    StreamingLatencyClassReport(
                        length: measured.length,
                        shape: measured.shape,
                        discardedWarmUpRawTranscript: "warm up",
                        samples: (1 ... StreamingLatencyGate.requiredSampleCount).map { index in
                            sampleReport(
                                index: index,
                                measured: measured,
                                firstFeedbackMilliseconds: firstFeedbackMilliseconds
                            )
                        }
                    )
                }
            )
        }

        private func sampleReport(
            index: Int,
            measured: StreamingLatencyClass,
            firstFeedbackMilliseconds: Double
        ) -> StreamingLatencySampleReport {
            let raw = "the raw final"
            let inserted = measured.shape == .voiceToText ? raw : "the shaped final"
            return StreamingLatencySampleReport(
                index: index,
                firstFeedbackMilliseconds: firstFeedbackMilliseconds,
                postReleaseMilliseconds: measured.length == .short ? 700 : 1300,
                stubbedPostReleaseMilliseconds: measured.length == .short ? 637.5 : 1237.5,
                captionRendered: true,
                batchTranscriptionCalls: 0,
                insertions: 1,
                pipelineRawDigest: digest(raw),
                historyRawDigest: digest(raw),
                insertedDigest: digest(inserted),
                polishGenerationMilliseconds: measured.shape == .voiceToText ? nil : 480,
                sessionTotalMilliseconds: 900
            )
        }

        private func digest(_ text: String) -> String {
            SHA256.hash(data: Data(text.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
        }

        private func shippedBaseline() throws -> Data {
            try Data(contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("docs/streaming-latency-baselines.json"))
        }

        private func writePlan(
            asrModel: String = "parakeet-eou-320",
            insertConstantMilliseconds: Double = 62.5,
            lengths: [String] = ["short", "long"]
        ) throws -> URL {
            let fixtures = try lengths.map { length -> String in
                let audio = directory.appendingPathComponent("\(length).wav")
                try Data().write(to: audio)
                return """
                { "length": "\(length)", "audioURL": "\(audio.absoluteString)" }
                """
            }
            let output = directory.appendingPathComponent("result.json")
            let planURL = directory.appendingPathComponent("plan.json")
            try Data("""
            {
              "schemaVersion": 1,
              "asrModel": "\(asrModel)",
              "polishModel": "qwen2.5:3b",
              "sampleCount": 20,
              "insertConstantMilliseconds": \(insertConstantMilliseconds),
              "outputURL": "\(output.absoluteString)",
              "fixtures": [\(fixtures.joined(separator: ","))]
            }
            """.utf8).write(to: planURL)
            return planURL
        }
    }
#endif
