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
            "included_core_floor": 0.0,
            "changed_line_floor": 90.0,
            "minimum_file_coverage": 0.0,
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
            "included_core_floor": 0.0,
            "changed_line_floor": 90.0,
            "minimum_file_coverage": 0.0,
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
            "included_core_floor": 50.0,
            "changed_line_floor": 90.0,
            "minimum_file_coverage": 0.0,
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
        XCTAssertTrue(result.output.contains("included core coverage 0.00% is below 50.00%"))
    }

    func testCheckerRejectsPerFileRegression() throws {
        let sourceDirectory = directory.appendingPathComponent("Sources/FoldWiseVoiceKit")
        let core = sourceDirectory.appendingPathComponent("Core.swift")
        try "let uncovered = 1\n".write(to: core, atomically: true, encoding: .utf8)

        let policy = directory.appendingPathComponent("coverage-policy.json")
        try writeJSON([
            "production_source_root": "Sources/FoldWiseVoiceKit",
            "overall_floor": 0.0,
            "included_core_floor": 0.0,
            "changed_line_floor": 90.0,
            "minimum_file_coverage": 50.0,
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
        XCTAssertTrue(result.output.contains("Core.swift coverage 0.00% is below 50.00%"))
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
            "included_core_floor": 0.0,
            "changed_line_floor": 90.0,
            "minimum_file_coverage": 0.0,
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

    func testCheckerRejectsLoweredAcceptedFloor() throws {
        let sourceDirectory = directory.appendingPathComponent("Sources/FoldWiseVoiceKit")
        let core = sourceDirectory.appendingPathComponent("Core.swift")
        try "let covered = 1\n".write(to: core, atomically: true, encoding: .utf8)

        let policy = directory.appendingPathComponent("coverage-policy.json")
        let baselinePolicy = directory.appendingPathComponent("baseline-coverage-policy.json")
        let policyValue: [String: Any] = [
            "production_source_root": "Sources/FoldWiseVoiceKit",
            "overall_floor": 40.0,
            "included_core_floor": 50.0,
            "changed_line_floor": 90.0,
            "minimum_file_coverage": 0.0,
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
