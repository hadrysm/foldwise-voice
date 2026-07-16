import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class ConfigChangePropagationTests: XCTestCase {
    private struct NotificationState: Equatable {
        let changes: [Config.ChangeSet]
        let selections: [DictationSelection]
        let loadFailed: Bool
    }

    private struct FailedState: Equatable {
        let selection: DictationSelection
        let notifications: [Config.ChangeSet]
        let data: Data?
    }

    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("foldwise-config-transaction-tests-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private var path: URL {
        directory.appendingPathComponent("config.json")
    }

    func testSelectionPersistsBeforeOneTypedNotification() throws {
        let config = Config.defaultConfig(path: path)
        try config.save()
        let emailID = try XCTUnwrap(config.orderedModes.last?.id)
        var observedSelections: [DictationSelection] = []
        var observedChanges: [Config.ChangeSet] = []
        var loadFailed = false
        config.onChange { changes in
            observedChanges.append(changes)
            do {
                observedSelections.append(try Config.load(from: self.path).selection)
            } catch {
                loadFailed = true
            }
        }

        try config.select(.mode(emailID))

        XCTAssertEqual(
            NotificationState(
                changes: observedChanges,
                selections: observedSelections,
                loadFailed: loadFailed
            ),
            NotificationState(
                changes: [.selection],
                selections: [.mode(emailID)],
                loadFailed: false
            )
        )
    }

    func testModePresentationChangePublishesLibraryWithoutSelection() throws {
        let config = Config.defaultConfig(path: path)
        var received: [Config.ChangeSet] = []
        config.onChange { received.append($0) }

        var mode = try XCTUnwrap(config.orderedModes.first)
        mode.icon = "quote.bubble"
        try config.saveMode(mode)

        XCTAssertEqual(received, [.modeLibrary])
    }

    func testCombinedPreferenceChangePublishesOneNetChange() throws {
        let config = Config.defaultConfig(path: path)
        var received: [Config.ChangeSet] = []
        config.onChange { received.append($0) }

        var preferences = config.preferences
        preferences.hotkey = "cmd_r"
        preferences.asrModel = "future-asr"
        preferences.appearance = .dark
        preferences.inputDevice = "USB-opaque-uid"
        try config.apply(preferences)

        XCTAssertEqual(received, [[.hotkeys, .asrModel, .appearance, .inputDevice]])
    }

    func testPersistenceFailureLeavesLiveStateAndObserversUnchanged() throws {
        let missingDirectory = directory.appendingPathComponent("missing")
        let config = Config.defaultConfig(path: missingDirectory.appendingPathComponent("config.json"))
        let original = config.selection
        let emailID = try XCTUnwrap(config.orderedModes.last?.id)
        var received: [Config.ChangeSet] = []
        config.onChange { received.append($0) }

        XCTAssertThrowsError(try config.select(.mode(emailID)))

        XCTAssertEqual(
            FailedState(
                selection: config.selection, notifications: received,
                data: nil
            ),
            FailedState(selection: original, notifications: [], data: nil)
        )
    }

    func testReadOnlyDirectoryFailurePreservesPriorFileAndCommittedSelection() throws {
        let config = Config.defaultConfig(path: path)
        try config.save()
        let originalData = try Data(contentsOf: path)
        let originalSelection = config.selection
        let emailID = try XCTUnwrap(config.orderedModes.last?.id)
        var received: [Config.ChangeSet] = []
        config.onChange { received.append($0) }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: directory.path
        )
        addTeardownBlock {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: self.directory.path
            )
        }

        XCTAssertThrowsError(try config.select(.mode(emailID)))

        XCTAssertEqual(
            FailedState(
                selection: config.selection,
                notifications: received,
                data: try Data(contentsOf: path)
            ),
            FailedState(
                selection: originalSelection, notifications: [],
                data: originalData
            )
        )
    }

    func testNoOpCandidatePublishesNothing() throws {
        let config = Config.defaultConfig(path: path)
        var received: [Config.ChangeSet] = []
        config.onChange { received.append($0) }

        try config.select(config.selection)

        XCTAssertTrue(received.isEmpty)
    }
}
