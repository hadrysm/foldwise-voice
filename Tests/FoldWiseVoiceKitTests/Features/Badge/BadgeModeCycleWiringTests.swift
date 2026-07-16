import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class BadgeModeCycleWiringTests: XCTestCase {
    private struct BadgeSnapshot: Equatable {
        let selection: DictationSelection
        let state: BadgeState
        let display: BadgeModeCycleDisplay?
    }

    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("foldwise-badge-mode-cycle-tests-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testDirectSelectionDoesNotPrepareModeReel() throws {
        let config = Config.defaultConfig(path: directory.appendingPathComponent("config.json"))
        let second = try XCTUnwrap(config.orderedModes.last)
        let secondID = try XCTUnwrap(second.id)
        let badge = BadgeController(config: config, onOpenApp: {})

        try config.select(.mode(secondID))

        XCTAssertNil(badge.model.modeCycleDisplay)
    }

    func testCommittedCyclePreparesCurrentModeReel() throws {
        let config = Config.defaultConfig(path: directory.appendingPathComponent("config.json"))
        let first = try XCTUnwrap(config.orderedModes.first)
        let firstID = try XCTUnwrap(first.id)
        let second = try XCTUnwrap(config.orderedModes.last)
        let secondID = try XCTUnwrap(second.id)
        try config.select(.mode(secondID))
        let badge = BadgeController(config: config, onOpenApp: {})
        let command = ModeCycleCommand(
            config: config,
            onCommitted: { badge.confirmModeCycle($0) }
        )
        command.perform()

        XCTAssertEqual(
            badge.model.modeCycleDisplay,
            .prepared(
                from: BadgeModeCycleItem(
                    selection: .mode(secondID), name: second.name, icon: second.icon
                ),
                to: BadgeModeCycleItem(
                    selection: .mode(firstID), name: first.name, icon: first.icon
                ),
                motion: .standard
            )
        )
    }

    func testFailedCycleKeepsSelectionAndShowsSwitchError() {
        let path = directory.appendingPathComponent("missing/config.json")
        let config = Config.defaultConfig(path: path)
        let original = config.selection
        let badge = BadgeController(config: config, onOpenApp: {})
        let command = ModeCycleCommand(
            config: config,
            onCommitted: { badge.confirmModeCycle($0) },
            onFailure: { _ in badge.showModeCycleError() }
        )

        command.perform()

        XCTAssertEqual(
            BadgeSnapshot(
                selection: config.selection,
                state: badge.model.state,
                display: badge.model.modeCycleDisplay
            ),
            BadgeSnapshot(
                selection: original,
                state: .error(message: "couldn’t switch Mode"),
                display: nil
            )
        )
    }

    func testUnknownModeIconUsesFallbackInCommittedReel() throws {
        let config = Config.defaultConfig(path: directory.appendingPathComponent("config.json"))
        var modes = config.orderedModes
        modes[1].icon = "not.a.real.symbol"
        try config.replaceModes(modes, selection: config.selection)
        let badge = BadgeController(config: config, onOpenApp: {})
        let command = ModeCycleCommand(
            config: config,
            onCommitted: { badge.confirmModeCycle($0) }
        )

        command.perform()

        XCTAssertEqual(badge.model.modeCycleDisplay?.destination.icon, "text.bubble")
    }

    func testModeRenameRefreshesPreparedReelWithoutNewTransition() throws {
        let config = Config.defaultConfig(path: directory.appendingPathComponent("config.json"))
        let from = try XCTUnwrap(config.orderedModes.first)
        let fromID = try XCTUnwrap(from.id)
        var renamed = try XCTUnwrap(config.orderedModes.last)
        let renamedID = try XCTUnwrap(renamed.id)
        let badge = BadgeController(config: config, onOpenApp: {})
        let command = ModeCycleCommand(
            config: config,
            onCommitted: { badge.confirmModeCycle($0) }
        )
        command.perform()
        renamed.name = "Correspondence with a complete accessible name"
        renamed.icon = "paperclip"

        try config.saveMode(renamed)

        XCTAssertEqual(
            badge.model.modeCycleDisplay,
            .prepared(
                from: BadgeModeCycleItem(
                    selection: .mode(fromID), name: from.name, icon: from.icon
                ),
                to: BadgeModeCycleItem(
                    selection: .mode(renamedID), name: renamed.name, icon: renamed.icon
                ),
                motion: .standard
            )
        )
    }

    func testPipelineFeedbackCancelsAndThenResumesFromLastVisibleMode() throws {
        let config = Config.defaultConfig(path: directory.appendingPathComponent("config.json"))
        let from = try XCTUnwrap(config.orderedModes.first)
        let fromID = try XCTUnwrap(from.id)
        let to = try XCTUnwrap(config.orderedModes.last)
        let toID = try XCTUnwrap(to.id)
        let badge = BadgeController(config: config, onOpenApp: {})
        let command = ModeCycleCommand(
            config: config,
            onCommitted: { badge.confirmModeCycle($0) }
        )
        command.perform()

        badge.apply(.listening(mode: from.name))
        let interrupted = badge.model.modeCycleDisplay
        badge.apply(.idle)

        XCTAssertEqual(
            [interrupted, badge.model.modeCycleDisplay],
            [
                nil,
                .prepared(
                    from: BadgeModeCycleItem(
                        selection: .mode(fromID), name: from.name, icon: from.icon
                    ),
                    to: BadgeModeCycleItem(
                        selection: .mode(toID), name: to.name, icon: to.icon
                    ),
                    motion: .standard
                ),
            ]
        )
    }

    func testExistingBadgeErrorCancelsActiveModeReel() {
        let config = Config.defaultConfig(path: directory.appendingPathComponent("config.json"))
        let badge = BadgeController(config: config, onOpenApp: {})
        let command = ModeCycleCommand(
            config: config,
            onCommitted: { badge.confirmModeCycle($0) }
        )
        command.perform()

        badge.showModeSelectionError()

        XCTAssertEqual(
            BadgeSnapshot(
                selection: config.selection,
                state: badge.model.state,
                display: badge.model.modeCycleDisplay
            ),
            BadgeSnapshot(
                selection: config.selection,
                state: .error(message: "couldn’t select Mode"),
                display: nil
            )
        )
    }

    func testBadgePanelCannotBecomeKeyOrMain() {
        let panel = BadgePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        XCTAssertEqual([panel.canBecomeKey, panel.canBecomeMain], [false, false])
    }
}
