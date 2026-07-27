import Foundation
import XCTest
@testable import FoldWiseVoiceKit

final class DictationBaselineHarnessBuildTests: XCTestCase {
    func testBuildAvailabilityMatchesCompilerFlag() {
        #if DICTATION_BASELINE_HARNESS
            XCTAssertTrue(DictationBaselineHarnessBuild.isEnabled)
        #else
            XCTAssertFalse(DictationBaselineHarnessBuild.isEnabled)
        #endif
    }
}

#if DICTATION_BASELINE_HARNESS
    final class DictationBaselineHarnessTests: XCTestCase {
        private let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("foldwise-dictation-baseline-\(UUID().uuidString)")

        override func setUpWithError() throws {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        override func tearDownWithError() throws {
            try FileManager.default.removeItem(at: directory)
        }

        func testPlanLoadsPrivateFixturesAndMeasurementContract() throws {
            let short = directory.appendingPathComponent("short.wav")
            let long = directory.appendingPathComponent("long.wav")
            try Data().write(to: short)
            try Data().write(to: long)
            let output = directory.appendingPathComponent("result.json")
            let planURL = directory.appendingPathComponent("plan.json")
            let plan = """
            {
              "schemaVersion": 1,
              "asrModel": "whisper-small",
              "polishModel": "qwen2.5:3b",
              "sampleCount": 20,
              "outputURL": "\(output.absoluteString)",
              "fixtures": [
                {
                  "length": "short",
                  "audioURL": "\(short.absoluteString)",
                  "expectedTranscript": "Krótka próbka ma więcej niż czterdzieści znaków."
                },
                {
                  "length": "long",
                  "audioURL": "\(long.absoluteString)",
                  "expectedTranscript": "Dłuższa próbka ma zdecydowanie więcej niż czterdzieści znaków."
                }
              ]
            }
            """
            try Data(plan.utf8).write(to: planURL)

            let loaded = try DictationBaselinePlan.load(from: planURL)

            XCTAssertEqual(
                loaded,
                DictationBaselinePlan(
                    schemaVersion: 1,
                    asrModel: "whisper-small",
                    polishModel: "qwen2.5:3b",
                    sampleCount: 20,
                    outputURL: output,
                    fixtures: [
                        DictationBaselineFixturePlan(
                            length: .short,
                            audioURL: short,
                            expectedTranscript:
                            "Krótka próbka ma więcej niż czterdzieści znaków."
                        ),
                        DictationBaselineFixturePlan(
                            length: .long,
                            audioURL: long,
                            expectedTranscript:
                            "Dłuższa próbka ma zdecydowanie więcej niż czterdzieści znaków."
                        ),
                    ]
                )
            )
        }

        func testStatisticsUseObservedP95() throws {
            let statistics = try DictationBaselineStatistics(
                samplesMilliseconds: [
                    10, 20, 30, 40, 50,
                    60, 70, 80, 90, 100,
                ]
            )

            XCTAssertEqual(
                statistics,
                DictationBaselineStatistics(
                    medianMilliseconds: 55,
                    p95Milliseconds: 100,
                    worstMilliseconds: 100
                )
            )
        }
    }
#endif
