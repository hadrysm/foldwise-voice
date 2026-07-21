import Foundation
import XCTest

final class CoveragePolicyCommandTests: XCTestCase {
    private let fileManager = FileManager.default
    private var directory = FileManager.default.temporaryDirectory
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    override func setUpWithError() throws {
        directory = fileManager.temporaryDirectory
            .appendingPathComponent("foldwise-coverage-tests-\(UUID().uuidString)")
        try fileManager.createDirectory(
            at: directory.appendingPathComponent("Sources/FoldWiseVoiceKit"),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try fileManager.removeItem(at: directory)
    }

    func testCheckerReportsUncoveredChangedIncludedLines() throws {
        let sourceDirectory = directory.appendingPathComponent("Sources/FoldWiseVoiceKit")
        let core = sourceDirectory.appendingPathComponent("Core.swift")
        let view = sourceDirectory.appendingPathComponent("View.swift")
        try "let covered = 1\nlet uncovered = 2\n".write(to: core, atomically: true, encoding: .utf8)
        try "let declarative = true\n".write(to: view, atomically: true, encoding: .utf8)

        let policy = directory.appendingPathComponent("coverage-policy.json")
        try writeJSON([
            "production_source_root": "Sources/FoldWiseVoiceKit",
            "overall_floor": 0.0,
            "included_core_floor": 90.0,
            "changed_line_floor": 90.0,
            "minimum_file_coverage": 90.0,
            "exemptions": [
                ["path": "Sources/FoldWiseVoiceKit/View.swift", "reason": "Declarative test fixture"],
            ],
        ], to: policy)

        let report = directory.appendingPathComponent("coverage.json")
        try writeJSON([
            "data": [[
                "files": [
                    coverageFile(core.path, count: 2, covered: 1, segments: [
                        [1, 1, 1, true, true, false],
                        [1, 16, 0, false, false, false],
                        [2, 1, 0, true, true, false],
                        [2, 18, 0, false, false, false],
                    ]),
                    coverageFile(view.path, count: 1, covered: 0, segments: [
                        [1, 1, 0, true, true, false],
                        [1, 23, 0, false, false, false],
                    ]),
                ],
            ]],
            "type": "llvm.coverage.json.export",
            "version": "2.0.1",
        ], to: report)

        let diff = directory.appendingPathComponent("changes.diff")
        try """
        diff --git a/Sources/FoldWiseVoiceKit/Core.swift b/Sources/FoldWiseVoiceKit/Core.swift
        --- a/Sources/FoldWiseVoiceKit/Core.swift
        +++ b/Sources/FoldWiseVoiceKit/Core.swift
        @@ -1,1 +1,2 @@
         let covered = 1
        +let uncovered = 2

        """.write(to: diff, atomically: true, encoding: .utf8)

        let result = try runChecker(report: report, policy: policy, diff: diff)

        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.output.contains("Changed included lines: 0.00% (0/1), required 90.00%"))
        XCTAssertTrue(result.output.contains("Core.swift:2"))
    }

    func testCheckerRejectsOverallProductionRegression() throws {
        let sourceDirectory = directory.appendingPathComponent("Sources/FoldWiseVoiceKit")
        let core = sourceDirectory.appendingPathComponent("Core.swift")
        try "let uncovered = 1\n".write(to: core, atomically: true, encoding: .utf8)

        let policy = directory.appendingPathComponent("coverage-policy.json")
        try writeJSON([
            "production_source_root": "Sources/FoldWiseVoiceKit",
            "overall_floor": 50.0,
            "included_core_floor": 90.0,
            "changed_line_floor": 90.0,
            "minimum_file_coverage": 90.0,
            "exemptions": [],
        ], to: policy)
        let report = directory.appendingPathComponent("coverage.json")
        try writeJSON([
            "data": [[
                "files": [
                    coverageFile(core.path, count: 1, covered: 0, segments: [
                        [1, 1, 0, true, true, false],
                        [1, 18, 0, false, false, false],
                    ]),
                ],
            ]],
        ], to: report)
        let diff = directory.appendingPathComponent("changes.diff")
        try "".write(to: diff, atomically: true, encoding: .utf8)

        let result = try runChecker(report: report, policy: policy, diff: diff)

        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.output.contains("overall production coverage 0.00% is below 50.00%"))
    }

    func testCheckerRejectsIncludedCoreRegression() throws {
        let sourceDirectory = directory.appendingPathComponent("Sources/FoldWiseVoiceKit")
        let core = sourceDirectory.appendingPathComponent("Core.swift")
        try "let uncovered = 1\n".write(to: core, atomically: true, encoding: .utf8)

        let policy = directory.appendingPathComponent("coverage-policy.json")
        try writeJSON([
            "production_source_root": "Sources/FoldWiseVoiceKit",
            "overall_floor": 0.0,
            "included_core_floor": 90.0,
            "changed_line_floor": 90.0,
            "minimum_file_coverage": 90.0,
            "exemptions": [],
        ], to: policy)
        let report = directory.appendingPathComponent("coverage.json")
        try writeJSON([
            "data": [[
                "files": [
                    coverageFile(core.path, count: 1, covered: 0, segments: [
                        [1, 1, 0, true, true, false],
                        [1, 18, 0, false, false, false],
                    ]),
                ],
            ]],
        ], to: report)
        let diff = directory.appendingPathComponent("changes.diff")
        try "".write(to: diff, atomically: true, encoding: .utf8)

        let result = try runChecker(report: report, policy: policy, diff: diff)

        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.output.contains("included core coverage 0.00% is below 90.00%"))
    }

    func testCheckerRejectsPerFileRegression() throws {
        let sourceDirectory = directory.appendingPathComponent("Sources/FoldWiseVoiceKit")
        let core = sourceDirectory.appendingPathComponent("Core.swift")
        try "let uncovered = 1\n".write(to: core, atomically: true, encoding: .utf8)

        let policy = directory.appendingPathComponent("coverage-policy.json")
        try writeJSON([
            "production_source_root": "Sources/FoldWiseVoiceKit",
            "overall_floor": 0.0,
            "included_core_floor": 90.0,
            "changed_line_floor": 90.0,
            "minimum_file_coverage": 90.0,
            "exemptions": [],
        ], to: policy)
        let report = directory.appendingPathComponent("coverage.json")
        try writeJSON([
            "data": [[
                "files": [
                    coverageFile(core.path, count: 1, covered: 0, segments: [
                        [1, 1, 0, true, true, false],
                        [1, 18, 0, false, false, false],
                    ]),
                ],
            ]],
        ], to: report)
        let diff = directory.appendingPathComponent("changes.diff")
        try "".write(to: diff, atomically: true, encoding: .utf8)

        let result = try runChecker(report: report, policy: policy, diff: diff)

        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.output.contains("Core.swift coverage 0.00% is below 90.00%"))
    }

    func testCheckerAcceptsSatisfiedPolicy() throws {
        let sourceDirectory = directory.appendingPathComponent("Sources/FoldWiseVoiceKit")
        let core = sourceDirectory.appendingPathComponent("Core.swift")
        try "let covered = 1\n".write(to: core, atomically: true, encoding: .utf8)

        let policy = directory.appendingPathComponent("coverage-policy.json")
        try writeJSON([
            "production_source_root": "Sources/FoldWiseVoiceKit",
            "overall_floor": 100.0,
            "included_core_floor": 100.0,
            "changed_line_floor": 90.0,
            "minimum_file_coverage": 100.0,
            "exemptions": [],
        ], to: policy)
        let report = directory.appendingPathComponent("coverage.json")
        try writeJSON([
            "data": [[
                "files": [
                    coverageFile(core.path, count: 1, covered: 1, segments: [
                        [1, 1, 1, true, true, false],
                        [1, 16, 0, false, false, false],
                    ]),
                ],
            ]],
        ], to: report)
        let diff = directory.appendingPathComponent("changes.diff")
        try "".write(to: diff, atomically: true, encoding: .utf8)

        let result = try runChecker(report: report, policy: policy, diff: diff)

        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("Coverage policy PASSED"))
    }

    func testCheckerIncludesNewProductionFilesByDefault() throws {
        let sourceDirectory = directory.appendingPathComponent("Sources/FoldWiseVoiceKit")
        let core = sourceDirectory.appendingPathComponent("Core.swift")
        let newFile = sourceDirectory.appendingPathComponent("NewBehavior.swift")
        try "let covered = 1\n".write(to: core, atomically: true, encoding: .utf8)
        try "func behavior() {}\n".write(to: newFile, atomically: true, encoding: .utf8)

        let policy = directory.appendingPathComponent("coverage-policy.json")
        try writeJSON([
            "production_source_root": "Sources/FoldWiseVoiceKit",
            "overall_floor": 0.0,
            "included_core_floor": 90.0,
            "changed_line_floor": 90.0,
            "minimum_file_coverage": 90.0,
            "exemptions": [],
        ], to: policy)
        let report = directory.appendingPathComponent("coverage.json")
        try writeJSON([
            "data": [[
                "files": [
                    coverageFile(core.path, count: 1, covered: 1, segments: [
                        [1, 1, 1, true, true, false],
                        [1, 16, 0, false, false, false],
                    ]),
                ],
            ]],
        ], to: report)
        let diff = directory.appendingPathComponent("changes.diff")
        try "".write(to: diff, atomically: true, encoding: .utf8)

        let result = try runChecker(report: report, policy: policy, diff: diff)

        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.output.contains("missing production files"))
        XCTAssertTrue(result.output.contains("NewBehavior.swift"))
    }

    func testCheckerRejectsMissingCoverageDataForOrdinaryExemption() throws {
        let sourceDirectory = directory.appendingPathComponent("Sources/FoldWiseVoiceKit")
        let core = sourceDirectory.appendingPathComponent("Core.swift")
        let adapter = sourceDirectory.appendingPathComponent("Adapter.swift")
        try "let covered = 1\n".write(to: core, atomically: true, encoding: .utf8)
        try "func platformEffect() {}\n".write(to: adapter, atomically: true, encoding: .utf8)

        let policy = directory.appendingPathComponent("coverage-policy.json")
        try writeJSON([
            "production_source_root": "Sources/FoldWiseVoiceKit",
            "overall_floor": 0.0,
            "included_core_floor": 90.0,
            "changed_line_floor": 90.0,
            "minimum_file_coverage": 90.0,
            "exemptions": [
                ["path": "Sources/FoldWiseVoiceKit/Adapter.swift", "reason": "Platform fixture"],
            ],
        ], to: policy)
        let report = directory.appendingPathComponent("coverage.json")
        try writeJSON([
            "data": [[
                "files": [
                    coverageFile(core.path, count: 1, covered: 1, segments: [
                        [1, 1, 1, true, true, false],
                        [1, 16, 0, false, false, false],
                    ]),
                ],
            ]],
        ], to: report)
        let diff = directory.appendingPathComponent("changes.diff")
        try "".write(to: diff, atomically: true, encoding: .utf8)

        let result = try runChecker(report: report, policy: policy, diff: diff)

        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.output.contains("coverage report is missing production files: "))
        XCTAssertTrue(result.output.contains("Adapter.swift"))
    }

    func testCheckerRejectsLoweredAcceptedFloor() throws {
        let sourceDirectory = directory.appendingPathComponent("Sources/FoldWiseVoiceKit")
        let core = sourceDirectory.appendingPathComponent("Core.swift")
        try "let covered = 1\n".write(to: core, atomically: true, encoding: .utf8)

        let policy = directory.appendingPathComponent("coverage-policy.json")
        let baselinePolicy = directory.appendingPathComponent("baseline-coverage-policy.json")
        let policyValue: [String: Any] = [
            "production_source_root": "Sources/FoldWiseVoiceKit",
            "overall_floor": 40.0,
            "included_core_floor": 90.0,
            "changed_line_floor": 90.0,
            "minimum_file_coverage": 90.0,
            "exemptions": [],
        ]
        try writeJSON(policyValue, to: policy)
        var baselineValue = policyValue
        baselineValue["overall_floor"] = 50.0
        try writeJSON(baselineValue, to: baselinePolicy)

        let report = directory.appendingPathComponent("coverage.json")
        try writeJSON([
            "data": [[
                "files": [
                    coverageFile(core.path, count: 1, covered: 1, segments: [
                        [1, 1, 1, true, true, false],
                        [1, 16, 0, false, false, false],
                    ]),
                ],
            ]],
        ], to: report)
        let diff = directory.appendingPathComponent("changes.diff")
        try "".write(to: diff, atomically: true, encoding: .utf8)

        let result = try runChecker(
            report: report,
            policy: policy,
            diff: diff,
            baselinePolicy: baselinePolicy
        )

        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.output.contains("overall_floor cannot decrease from 50.00% to 40.00%"))
    }

    func testCheckerAcceptsBalancedThresholdResetInVersionTwo() throws {
        let result = try policyValidationResult(
            policy: PolicyFixture(
                policyVersion: 2,
                overallFloor: 50.0,
                includedCoreFloor: 90.0,
                changedLineFloor: 85.0,
                minimumFileCoverage: 80.0
            ),
            baseline: PolicyFixture(
                policyVersion: 1,
                overallFloor: 50.0,
                includedCoreFloor: 95.0,
                changedLineFloor: 90.0,
                minimumFileCoverage: 90.0
            )
        )

        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("Coverage policy PASSED"))
    }

    func testCheckerRejectsBalancedThresholdsInVersionOne() throws {
        let result = try policyValidationResult(
            policy: PolicyFixture(
                policyVersion: 1,
                includedCoreFloor: 90.0,
                changedLineFloor: 85.0,
                minimumFileCoverage: 80.0
            )
        )

        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.output.contains("changed_line_floor must remain at least 90.00%"))
    }

    func testCheckerRejectsTemporarySubNinetyAggregateCoreFloor() throws {
        let result = try policyValidationResult(
            policy: PolicyFixture(includedCoreFloor: 89.0)
        )

        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.output.contains("included_core_floor must remain at least 90.00%"))
    }

    func testCheckerRejectsSubEightyFiveChangedLineFloor() throws {
        let result = try policyValidationResult(
            policy: PolicyFixture(
                policyVersion: 2,
                changedLineFloor: 84.0,
                minimumFileCoverage: 80.0
            )
        )

        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.output.contains("changed_line_floor must remain at least 85.00%"))
    }

    func testCheckerRejectsSubEightyPerFileFloor() throws {
        let result = try policyValidationResult(
            policy: PolicyFixture(
                policyVersion: 2,
                changedLineFloor: 85.0,
                minimumFileCoverage: 79.0
            )
        )

        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.output.contains("minimum_file_coverage must remain at least 80.00%"))
    }

    func testCheckerKeepsOverallFloorRatchetedDuringVersionTwoReset() throws {
        let result = try policyValidationResult(
            policy: PolicyFixture(
                policyVersion: 2,
                overallFloor: 40.0,
                includedCoreFloor: 90.0,
                changedLineFloor: 85.0,
                minimumFileCoverage: 80.0
            ),
            baseline: PolicyFixture(
                policyVersion: 1,
                overallFloor: 50.0,
                includedCoreFloor: 95.0,
                changedLineFloor: 90.0,
                minimumFileCoverage: 90.0
            )
        )

        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.output.contains("overall_floor cannot decrease from 50.00% to 40.00%"))
    }

    func testCheckerRejectsUnreviewedPolicyVersionReset() throws {
        let result = try policyValidationResult(
            policy: PolicyFixture(
                policyVersion: 3,
                includedCoreFloor: 90.0,
                changedLineFloor: 85.0,
                minimumFileCoverage: 80.0
            )
        )

        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.output.contains("policy_version 3 is not supported"))
    }

    private struct PolicyFixture {
        let policyVersion: Int?
        let overallFloor: Double
        let includedCoreFloor: Double
        let changedLineFloor: Double
        let minimumFileCoverage: Double

        init(
            policyVersion: Int? = nil,
            overallFloor: Double = 0.0,
            includedCoreFloor: Double = 90.0,
            changedLineFloor: Double = 90.0,
            minimumFileCoverage: Double = 90.0
        ) {
            self.policyVersion = policyVersion
            self.overallFloor = overallFloor
            self.includedCoreFloor = includedCoreFloor
            self.changedLineFloor = changedLineFloor
            self.minimumFileCoverage = minimumFileCoverage
        }

        var jsonValue: [String: Any] {
            var value: [String: Any] = [
                "production_source_root": "Sources/FoldWiseVoiceKit",
                "overall_floor": overallFloor,
                "included_core_floor": includedCoreFloor,
                "changed_line_floor": changedLineFloor,
                "minimum_file_coverage": minimumFileCoverage,
                "exemptions": [],
            ]
            if let policyVersion {
                value["policy_version"] = policyVersion
            }
            return value
        }
    }

    private func policyValidationResult(
        policy fixture: PolicyFixture,
        baseline baselineFixture: PolicyFixture? = nil
    ) throws -> (status: Int32, output: String) {
        let sourceDirectory = directory.appendingPathComponent("Sources/FoldWiseVoiceKit")
        let core = sourceDirectory.appendingPathComponent("Core.swift")
        try "let covered = 1\n".write(to: core, atomically: true, encoding: .utf8)

        let policy = directory.appendingPathComponent("coverage-policy.json")
        try writeJSON(fixture.jsonValue, to: policy)
        let report = directory.appendingPathComponent("coverage.json")
        try writeJSON([
            "data": [[
                "files": [
                    coverageFile(core.path, count: 1, covered: 1, segments: [
                        [1, 1, 1, true, true, false],
                        [1, 16, 0, false, false, false],
                    ]),
                ],
            ]],
        ], to: report)
        let diff = directory.appendingPathComponent("changes.diff")
        try "".write(to: diff, atomically: true, encoding: .utf8)

        guard let baselineFixture else {
            return try runChecker(report: report, policy: policy, diff: diff)
        }

        let baselinePolicy = directory.appendingPathComponent("baseline-coverage-policy.json")
        try writeJSON(baselineFixture.jsonValue, to: baselinePolicy)
        return try runChecker(
            report: report,
            policy: policy,
            diff: diff,
            baselinePolicy: baselinePolicy
        )
    }

    func testCoverageCommandDocumentsTargetBranchOverride() throws {
        let result = try coverageCommandHelp()

        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("COVERAGE_BASE_REF"))
    }

    func testCoverageCommandPromisesSingleTestExecution() throws {
        let result = try coverageCommandHelp()

        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("Runs the XCTest suite exactly once"))
    }

    private func coverageCommandHelp() throws -> (status: Int32, output: String) {
        let process = Process()
        let output = Pipe()
        process.executableURL = repositoryRoot.appendingPathComponent("scripts/coverage.sh")
        process.arguments = ["--help"]
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()
        let text = try XCTUnwrap(
            String(bytes: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        )
        return (process.terminationStatus, text)
    }

    private func coverageFile(
        _ filename: String,
        count: Int,
        covered: Int,
        segments: [[Any]]
    ) -> [String: Any] {
        [
            "filename": filename,
            "segments": segments,
            "summary": [
                "lines": [
                    "count": count,
                    "covered": covered,
                    "percent": count == 0 ? 0 : Double(covered) / Double(count) * 100,
                ],
            ],
        ]
    }

    private func writeJSON(_ value: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    private func runChecker(
        report: URL,
        policy: URL,
        diff: URL,
        baselinePolicy: URL? = nil
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            repositoryRoot.appendingPathComponent("scripts/check_coverage.py").path,
            "--report", report.path,
            "--policy", policy.path,
            "--diff", diff.path,
            "--root", directory.path,
        ]
        if let baselinePolicy {
            process.arguments?.append(contentsOf: ["--baseline-policy", baselinePolicy.path])
        }
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, try XCTUnwrap(String(bytes: data, encoding: .utf8)))
    }
}
