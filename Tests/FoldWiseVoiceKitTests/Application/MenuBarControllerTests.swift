import AppKit
import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class MenuBarControllerTests: XCTestCase {
    func testCheckForUpdatesFollowsUpdaterAvailability() throws {
        let menu = NSMenu()
        let controller = MenuBarController(
            config: Config.defaultConfig(
                path: FileManager.default.temporaryDirectory
                    .appendingPathComponent("foldwise-menu-bar-\(UUID().uuidString).json")
            ),
            onSettings: {},
            onCheckForUpdates: {},
            canCheckForUpdates: false,
            onModeSelectionError: {},
            onQuit: {},
            menu: menu,
            statusItem: NSStatusItem()
        )

        let item = try XCTUnwrap(menu.items.first { $0.title == "Check for Updates…" })

        XCTAssertFalse(item.isEnabled)
        withExtendedLifetime(controller) {}
    }

    func testCheckForUpdatesInvokesCommand() throws {
        let menu = NSMenu()
        var checkCount = 0
        let controller = MenuBarController(
            config: Config.defaultConfig(
                path: FileManager.default.temporaryDirectory
                    .appendingPathComponent("foldwise-menu-bar-\(UUID().uuidString).json")
            ),
            onSettings: {},
            onCheckForUpdates: { checkCount += 1 },
            onModeSelectionError: {},
            onQuit: {},
            menu: menu,
            statusItem: NSStatusItem()
        )
        let item = try XCTUnwrap(menu.items.first { $0.title == "Check for Updates…" })

        try XCTUnwrap(item.target as? NSObject).perform(
            try XCTUnwrap(item.action),
            with: item
        )
        XCTAssertEqual(checkCount, 1)
        withExtendedLifetime(controller) {}
    }

    func testCheckForUpdatesRefreshesWhenUpdaterAvailabilityChanges() throws {
        let menu = NSMenu()
        let controller = MenuBarController(
            config: Config.defaultConfig(
                path: FileManager.default.temporaryDirectory
                    .appendingPathComponent("foldwise-menu-bar-\(UUID().uuidString).json")
            ),
            onSettings: {},
            onCheckForUpdates: {},
            canCheckForUpdates: false,
            onModeSelectionError: {},
            onQuit: {},
            menu: menu,
            statusItem: NSStatusItem()
        )

        controller.setCanCheckForUpdates(true)

        let item = try XCTUnwrap(menu.items.first { $0.title == "Check for Updates…" })
        XCTAssertTrue(item.isEnabled)
        withExtendedLifetime(controller) {}
    }

    func testMenuDoesNotPresentParallelUpdateAvailableItem() {
        let menu = NSMenu()
        let controller = MenuBarController(
            config: Config.defaultConfig(
                path: FileManager.default.temporaryDirectory
                    .appendingPathComponent("foldwise-menu-bar-\(UUID().uuidString).json")
            ),
            onSettings: {},
            onCheckForUpdates: {},
            onModeSelectionError: {},
            onQuit: {},
            menu: menu,
            statusItem: NSStatusItem()
        )

        XCTAssertFalse(menu.items.contains { $0.title.hasPrefix("Update Available") })
        withExtendedLifetime(controller) {}
    }
}
