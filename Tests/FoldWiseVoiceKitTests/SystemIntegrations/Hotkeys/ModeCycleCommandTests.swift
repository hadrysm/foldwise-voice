import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class ModeCycleCommandTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("foldwise-mode-cycle-tests-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testEachPressReadsLatestCommittedSelectionAndModeOrder() throws {
        let config = Config.defaultConfig(path: directory.appendingPathComponent("config.json"))
        let first = try XCTUnwrap(config.orderedModes.first)
        let firstID = try XCTUnwrap(first.id)
        let second = try XCTUnwrap(config.orderedModes.last)
        let secondID = try XCTUnwrap(second.id)
        let command = ModeCycleCommand(config: config)

        command.perform()
        XCTAssertEqual(config.selection, .mode(secondID))

        try config.replaceModes([second, first], selection: config.selection)
        command.perform()

        XCTAssertEqual(config.selection, .mode(firstID))
    }

    func testEffectivePressPersistsBeforeOneCommittedCallback() throws {
        let path = directory.appendingPathComponent("config.json")
        let config = Config.defaultConfig(path: path)
        let original = config.selection
        let expected = try XCTUnwrap(config.orderedModes.last?.id)
        var callbacks: [ModeCycleTransition] = []
        var persistedAtCallback: DictationSelection?
        let command = ModeCycleCommand(
            config: config,
            onCommitted: { transition in
                callbacks.append(transition)
                persistedAtCallback = try? Config.load(from: path).selection
            }
        )

        command.perform()

        XCTAssertEqual(
            callbacks,
            [ModeCycleTransition(from: original, to: expected)]
        )
        XCTAssertEqual(persistedAtCallback, .mode(expected))
    }

    func testNoOpDoesNotPublishSuccessOrFailure() throws {
        let config = Config.defaultConfig(path: directory.appendingPathComponent("config.json"))
        let only = try XCTUnwrap(config.orderedModes.first)
        let onlyID = try XCTUnwrap(only.id)
        try config.replaceModes([only], selection: .mode(onlyID))
        var successes = 0
        var failures = 0
        let command = ModeCycleCommand(
            config: config,
            onCommitted: { _ in successes += 1 },
            onFailure: { _ in failures += 1 }
        )

        command.perform()

        XCTAssertEqual([successes, failures], [0, 0])
    }

    func testPressAfterPersistenceRecoveryResumesFromLastCommittedSelection() throws {
        let path = directory.appendingPathComponent("missing/config.json")
        let config = Config.defaultConfig(path: path)
        let original = config.selection
        let expected = try XCTUnwrap(config.orderedModes.last?.id)
        var successes: [ModeCycleTransition] = []
        var failures = 0
        let command = ModeCycleCommand(
            config: config,
            onCommitted: { successes.append($0) },
            onFailure: { _ in failures += 1 }
        )

        command.perform()

        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        command.perform()

        XCTAssertEqual(config.selection, .mode(expected))
        XCTAssertEqual(failures, 1)
        XCTAssertEqual(successes, [ModeCycleTransition(from: original, to: expected)])
        XCTAssertEqual(try Config.load(from: path).selection, .mode(expected))
    }
}
