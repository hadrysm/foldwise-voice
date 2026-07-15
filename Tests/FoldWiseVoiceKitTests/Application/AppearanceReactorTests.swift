import AppKit
import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class AppearanceReactorTests: XCTestCase {
    private let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("foldwise-appearance-reactor-tests-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    func testInitialPreferenceMapsToApplicationAppearance() {
        let expected: [AppearancePreference: NSAppearance.Name?] = [
            .system: nil,
            .light: .aqua,
            .dark: .darkAqua,
        ]

        for appearance in AppearancePreference.allCases {
            let config = Config.defaultConfig(path: path(appearance.rawValue))
            config.appearance = appearance
            var applied: [NSAppearance.Name?] = []

            _ = AppearanceReactor(config: config) { applied.append($0?.name) }

            XCTAssertEqual(applied, [expected[appearance]])
        }
    }

    func testAppearanceChangeReappliesOnce() throws {
        let config = Config.defaultConfig(path: path("changed"))
        var applied: [NSAppearance.Name?] = []
        let reactor = AppearanceReactor(config: config) { applied.append($0?.name) }
        applied.removeAll()

        config.appearance = .dark
        try config.saveAndNotify()

        withExtendedLifetime(reactor) {}
        XCTAssertEqual(applied, [.darkAqua])
    }

    func testUnrelatedChangeDoesNotReapply() throws {
        let config = Config.defaultConfig(path: path("unrelated"))
        var applied: [NSAppearance.Name?] = []
        let reactor = AppearanceReactor(config: config) { applied.append($0?.name) }
        applied.removeAll()

        config.hotkey = "cmd_r"
        try config.saveAndNotify()

        withExtendedLifetime(reactor) {}
        XCTAssertEqual(applied, [])
    }

    private func path(_ name: String) -> URL {
        dir.appendingPathComponent("\(name).json")
    }
}
