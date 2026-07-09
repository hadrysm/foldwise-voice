// The propagation contract of Config.saveAndNotify(): which mutations
// deliver which ChangeSet to observers, and which persist silently. Driven
// entirely through Config's public interface with a spy observer — no AppKit.

import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class ConfigChangePropagationTests: XCTestCase {
    /// XCTest instantiates the case once per test method, so each test gets
    /// its own scratch directory.
    private let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("foldwise-tests-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    private var path: URL {
        dir.appendingPathComponent("modes.json")
    }

    func testActiveModeChangeNotifiesWithActiveMode() throws {
        let config = Config.defaultConfig(path: path)
        var received: [Config.ChangeSet] = []
        config.onChange { received.append($0) }

        config.setActiveMode("Email")
        try config.saveAndNotify()

        XCTAssertEqual(received, [.activeMode])
    }

    func testHotkeyChangeNotifiesWithHotkeys() throws {
        let config = Config.defaultConfig(path: path)
        var received: [Config.ChangeSet] = []
        config.onChange { received.append($0) }

        config.hotkey = "cmd_r"
        try config.saveAndNotify()

        XCTAssertEqual(received, [.hotkeys])
    }

    func testToggleHotkeyChangeNotifiesWithHotkeys() throws {
        let config = Config.defaultConfig(path: path)
        var received: [Config.ChangeSet] = []
        config.onChange { received.append($0) }

        config.toggleHotkey = "f13"
        try config.saveAndNotify()

        XCTAssertEqual(received, [.hotkeys])
    }

    /// The sidebar preference is only read when the settings window opens, so
    /// like the Badge position it persists without notifying anyone.
    func testSidebarCollapsedChangePersistsWithoutNotifying() throws {
        let config = Config.defaultConfig(path: path)
        var received: [Config.ChangeSet] = []
        config.onChange { received.append($0) }

        config.sidebarCollapsed = true
        try config.saveAndNotify()

        XCTAssertEqual(received, [])
        XCTAssertTrue(try Config.load(from: path).sidebarCollapsed)
    }

    func testASRModelChangeNotifiesWithASRModel() throws {
        let config = Config.defaultConfig(path: path)
        var received: [Config.ChangeSet] = []
        config.onChange { received.append($0) }

        config.setASRModel("whisper-large-v3-turbo")
        try config.saveAndNotify()

        XCTAssertEqual(received, [.asrModel])
    }

    func testReselectingTheSameASRModelNotifiesNothing() throws {
        let config = Config.defaultConfig(path: path)
        var received: [Config.ChangeSet] = []
        config.onChange { received.append($0) }

        config.setASRModel(config.asrModel)
        try config.saveAndNotify()

        XCTAssertEqual(received, [])
    }

    /// The guard that keeps the TCC-sensitive hotkey event tap alive across
    /// Badge drags: repositioning the pill persists but must notify no one.
    func testBadgePositionChangePersistsWithoutNotifying() throws {
        let config = Config.defaultConfig(path: path)
        var received: [Config.ChangeSet] = []
        config.onChange { received.append($0) }

        config.badgePosition = [123.4, 56.7]
        try config.saveAndNotify()

        XCTAssertEqual(received, [])
        XCTAssertEqual(try Config.load(from: path).badgePosition, [123.4, 56.7])
    }

    func testNoOpReassignmentNotifiesNothing() throws {
        let config = Config.defaultConfig(path: path)
        var received: [Config.ChangeSet] = []
        config.onChange { received.append($0) }

        // Re-assign every tracked property its defaultConfig value.
        config.setActiveMode("Clean")
        config.hotkey = "alt_r"
        config.toggleHotkey = nil
        config.setASRModel("parakeet-v3")
        try config.saveAndNotify()

        XCTAssertEqual(received, [])
    }

    func testMutationsAccumulateIntoOneDeliveryThenClear() throws {
        let config = Config.defaultConfig(path: path)
        var received: [Config.ChangeSet] = []
        config.onChange { received.append($0) }

        config.setActiveMode("Email")
        config.hotkey = "cmd_r"
        try config.saveAndNotify()
        try config.saveAndNotify()

        XCTAssertEqual(received, [[.activeMode, .hotkeys]])
    }

    /// A failed persist must not propagate a half-applied change — and must
    /// keep it pending so a later successful save still delivers it.
    func testFailedSaveNotifiesNoOneAndKeepsChangePendingForRetry() throws {
        let missingDir = dir.appendingPathComponent("missing")
        let config = Config.defaultConfig(path: missingDir.appendingPathComponent("modes.json"))
        var received: [Config.ChangeSet] = []
        config.onChange { received.append($0) }

        config.hotkey = "cmd_r"
        XCTAssertThrowsError(try config.saveAndNotify())
        XCTAssertEqual(received, [])

        try FileManager.default.createDirectory(at: missingDir, withIntermediateDirectories: true)
        try config.saveAndNotify()
        XCTAssertEqual(received, [.hotkeys])
    }

    func testSaveAndNotifyRoundTripsToDisk() throws {
        let config = Config.defaultConfig(path: path)
        config.setActiveMode("Email")
        config.hotkey = "cmd_r"
        config.toggleHotkey = "f13"
        try config.saveAndNotify()

        let reloaded = try Config.load(from: path)
        XCTAssertEqual(reloaded.activeMode, "Email")
        XCTAssertEqual(reloaded.hotkey, "cmd_r")
        XCTAssertEqual(reloaded.toggleHotkey, "f13")
    }

    /// Loading records nothing: property observers don't fire during init,
    /// so the first save after launch can't replay the whole config.
    func testFreshlyLoadedConfigHasNothingPending() throws {
        let defaults = Config.defaultConfig(path: path)
        try defaults.save()
        let config = try Config.load(from: path)
        var received: [Config.ChangeSet] = []
        config.onChange { received.append($0) }

        try config.saveAndNotify()

        XCTAssertEqual(received, [])
    }
}
