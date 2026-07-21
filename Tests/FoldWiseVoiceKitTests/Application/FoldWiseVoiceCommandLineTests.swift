import Foundation
import XCTest
@testable import FoldWiseVoiceKit

final class FoldWiseVoiceCommandLineTests: XCTestCase {
    private let fileManager = FileManager.default
    private var directory = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        directory = fileManager.temporaryDirectory
            .appendingPathComponent("foldwise-command-line-tests-\(UUID().uuidString)")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try fileManager.removeItem(at: directory)
    }

    func testLegacyModeOptionIsRejectedInsteadOfSilentlyIgnored() {
        let action = FoldWiseVoiceCommandLine().evaluate(arguments: [
            "FoldWiseVoice", "--mode", "Casual",
        ])

        assertFailure(
            action,
            containing: "--mode is no longer supported; select Modes by stable ID in config.json."
        )
    }

    func testUnknownAndPositionalArgumentsRemainIgnored() {
        let action = FoldWiseVoiceCommandLine(environment: [:]).evaluate(arguments: [
            "FoldWiseVoice", "--unknown", "positional",
        ])

        XCTAssertEqual(action, .launch(configPath: nil, showSettings: false))
    }

    func testShowSettingsOptionRequestsVisibleWorkspace() {
        let action = FoldWiseVoiceCommandLine(environment: [:]).evaluate(arguments: [
            "FoldWiseVoice", "--show-settings",
        ])

        XCTAssertEqual(action, .launch(configPath: nil, showSettings: true))
    }

    func testShowSettingsEnvironmentRequestsVisibleWorkspace() {
        let action = FoldWiseVoiceCommandLine(environment: [
            "FOLDWISE_SHOW_SETTINGS": "1",
        ]).evaluate(arguments: ["FoldWiseVoice"])

        XCTAssertEqual(action, .launch(configPath: nil, showSettings: true))
    }

    func testMissingConfigValueRemainsAnEmptyOverride() {
        let action = FoldWiseVoiceCommandLine(environment: [:]).evaluate(arguments: [
            "FoldWiseVoice", "--config",
        ])

        XCTAssertEqual(action, .launch(configPath: nil, showSettings: false))
    }

    func testConfigValueMayBeginWithOptionPrefix() {
        let action = FoldWiseVoiceCommandLine(environment: [:]).evaluate(arguments: [
            "FoldWiseVoice", "--config", "--mode",
        ])

        XCTAssertEqual(action, .launch(configPath: "--mode", showSettings: false))
    }

    func testPrintConfigRejectsRecoveryWithoutPrintingFallbackDefaults() throws {
        let configURL = directory.appendingPathComponent("config.json")
        try Data("{}\n".utf8).write(to: configURL)

        let action = commandLine().evaluate(arguments: printArguments(for: configURL))

        assertFailure(action, containing: "Cannot print invalid configuration")
    }

    func testPrintConfigLeavesRejectedConfigurationUntouched() throws {
        let configURL = directory.appendingPathComponent("config.json")
        let rejected = Data("{}\n".utf8)
        try rejected.write(to: configURL)

        _ = commandLine().evaluate(arguments: printArguments(for: configURL))

        XCTAssertEqual(try Data(contentsOf: configURL), rejected)
    }

    func testPrintConfigReportsSerializationFailure() throws {
        let configURL = directory.appendingPathComponent("config.json")
        try Config.defaultConfig(path: configURL).save()
        let regularFile = directory.appendingPathComponent("not-a-directory")
        try Data().write(to: regularFile)

        let action = commandLine(temporaryDirectory: regularFile)
            .evaluate(arguments: printArguments(for: configURL))

        assertFailure(action, containing: "Could not serialize configuration")
    }

    func testPrintConfigCleansUpPartialFileAfterSerializationFailure() throws {
        let configURL = directory.appendingPathComponent("config.json")
        try Config.defaultConfig(path: configURL).save()
        let commandLine = FoldWiseVoiceCommandLine(
            temporaryDirectory: directory,
            serializeConfig: { _, url in
                try Data("partial".utf8).write(to: url)
                throw SerializationError.failed
            }
        )

        _ = commandLine.evaluate(arguments: printArguments(for: configURL))

        XCTAssertEqual(
            try fileManager.contentsOfDirectory(atPath: directory.path),
            ["config.json"]
        )
    }

    func testPrintConfigPreservesSuccessfulOutput() throws {
        let configURL = directory.appendingPathComponent("config.json")
        try Config.defaultConfig(path: configURL).save()
        let expectedJSON = try String(contentsOf: configURL, encoding: .utf8)

        let action = commandLine().evaluate(arguments: printArguments(for: configURL))

        XCTAssertEqual(
            action,
            .terminate(.init(
                status: 0,
                standardOutput: "config: \(configURL.path)\n\(expectedJSON)\n",
                standardError: ""
            ))
        )
    }

    func testPrintConfigCleansUpTemporaryFile() throws {
        let configURL = directory.appendingPathComponent("config.json")
        try Config.defaultConfig(path: configURL).save()

        _ = commandLine().evaluate(arguments: printArguments(for: configURL))

        XCTAssertEqual(
            try fileManager.contentsOfDirectory(atPath: directory.path),
            ["config.json"]
        )
    }

    func testPrintConfigDoesNotReplaceLegacyTemporaryFile() throws {
        let configURL = directory.appendingPathComponent("config.json")
        try Config.defaultConfig(path: configURL).save()
        let legacyTemporaryURL = directory.appendingPathComponent("foldwise-config-check.json")
        let staleData = Data("stale".utf8)
        try staleData.write(to: legacyTemporaryURL)

        _ = commandLine().evaluate(arguments: printArguments(for: configURL))

        XCTAssertEqual(try Data(contentsOf: legacyTemporaryURL), staleData)
    }

    func testPrintConfigReportsTemporaryCleanupFailure() throws {
        let configURL = directory.appendingPathComponent("config.json")
        try Config.defaultConfig(path: configURL).save()
        var reportedMessage: String?
        let commandLine = FoldWiseVoiceCommandLine(
            temporaryDirectory: directory,
            removeTemporaryItem: { _ in throw CleanupError.failed },
            reportCleanupFailure: { reportedMessage = $0 }
        )

        let action = commandLine.evaluate(arguments: printArguments(for: configURL))

        XCTAssertEqual(
            CleanupFailureSnapshot(
                hasSuccessfulStatus: action.status == 0,
                reportedFailure: reportedMessage?
                    .contains("Could not remove temporary configuration") == true
            ),
            CleanupFailureSnapshot(hasSuccessfulStatus: true, reportedFailure: true)
        )
    }

    private func assertFailure(
        _ action: FoldWiseVoiceCommandLine.Action,
        containing expectedMessage: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .terminate(result) = action else {
            return XCTFail("Expected command-line termination, got \(action)", file: file, line: line)
        }
        XCTAssertEqual(
            FailureSnapshot(
                hasFailureStatus: result.status != 0,
                standardOutput: result.standardOutput,
                containsExpectedError: result.standardError.contains(expectedMessage)
            ),
            FailureSnapshot(
                hasFailureStatus: true,
                standardOutput: "",
                containsExpectedError: true
            ),
            file: file,
            line: line
        )
    }

    private func commandLine(
        temporaryDirectory: URL? = nil
    ) -> FoldWiseVoiceCommandLine {
        FoldWiseVoiceCommandLine(temporaryDirectory: temporaryDirectory ?? directory)
    }

    private func printArguments(for configURL: URL) -> [String] {
        ["FoldWiseVoice", "--config", configURL.path, "--print-config"]
    }

    private struct FailureSnapshot: Equatable {
        let hasFailureStatus: Bool
        let standardOutput: String
        let containsExpectedError: Bool
    }

    private struct CleanupFailureSnapshot: Equatable {
        let hasSuccessfulStatus: Bool
        let reportedFailure: Bool
    }

    private enum CleanupError: Error {
        case failed
    }

    private enum SerializationError: Error {
        case failed
    }
}

private extension FoldWiseVoiceCommandLine.Action {
    var status: Int32? {
        guard case let .terminate(result) = self else { return nil }
        return result.status
    }
}
