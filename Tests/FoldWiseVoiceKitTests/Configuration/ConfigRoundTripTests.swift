import XCTest
@testable import FoldWiseVoiceKit

final class ConfigRoundTripTests: XCTestCase {
    private struct EncodingState: Equatable {
        let bytesMatch: Bool
        let hasOneTrailingNewline: Bool
        let keysAreSorted: Bool
    }

    private struct FallbackState: Equatable {
        let icon: String?
        let model: String?
        let asrModel: String
    }

    private struct ShortcutState: Equatable {
        let pushToTalk: String
        let toggle: String?
        let cycle: String?
    }

    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("foldwise-config-roundtrip-tests-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private var path: URL {
        directory.appendingPathComponent("config.json")
    }

    func testSaveIsDeterministicSortedJSONWithOneTrailingNewline() throws {
        let config = Config.defaultConfig(path: path)

        try config.save()
        let first = try Data(contentsOf: path)
        try Config.load(from: path).save()
        let second = try Data(contentsOf: path)

        let text = try XCTUnwrap(String(data: first, encoding: .utf8))
        let activeSelectionIndex = try XCTUnwrap(text.range(of: #""active_selection""#)?.lowerBound)
        let appearanceIndex = try XCTUnwrap(text.range(of: #""appearance""#)?.lowerBound)
        XCTAssertEqual(
            EncodingState(
                bytesMatch: first == second,
                hasOneTrailingNewline: first.suffix(1) == Data([0x0A])
                    && first.suffix(2) != Data([0x0A, 0x0A]),
                keysAreSorted: activeSelectionIndex < appearanceIndex
            ),
            EncodingState(bytesMatch: true, hasOneTrailingNewline: true, keysAreSorted: true)
        )
    }

    func testUnknownRuntimeFallbackValuesRoundTripUnchanged() throws {
        let json = ConfigSchemaFixture.valid
            .replacingOccurrences(of: "wand.and.sparkles", with: "unknown.symbol")
            .replacingOccurrences(of: "qwen2.5:3b", with: "unknown-ollama")
            .replacingOccurrences(of: "unknown-asr", with: "future-asr")
        try Data(json.utf8).write(to: path)

        let config = try Config.load(from: path)
        try config.save()
        let reloaded = try Config.load(from: path)

        XCTAssertEqual(
            FallbackState(
                icon: reloaded.orderedModes.first?.icon,
                model: reloaded.orderedModes.first?.llmModel,
                asrModel: reloaded.asrModel
            ),
            FallbackState(icon: "unknown.symbol", model: "unknown-ollama", asrModel: "future-asr")
        )
    }

    func testShortcutCollisionRemainsLoadable() throws {
        let json = ConfigSchemaFixture.valid
            .replacingOccurrences(of: #""toggle_hotkey": null"#, with: #""toggle_hotkey": "alt_r""#)
            .replacingOccurrences(of: #""mode_cycle_hotkey": null"#, with: #""mode_cycle_hotkey": "alt_r""#)
        try Data(json.utf8).write(to: path)

        let config = try Config.load(from: path)

        XCTAssertEqual(
            ShortcutState(
                pushToTalk: config.hotkey,
                toggle: config.toggleHotkey,
                cycle: config.modeCycleHotkey
            ),
            ShortcutState(pushToTalk: "alt_r", toggle: "alt_r", cycle: "alt_r")
        )
    }

    func testStrictSchemaRejectsUnknownMissingAndInvalidValues() throws {
        let invalidFixtures = [
            ConfigSchemaFixture.valid.replacingOccurrences(
                of: #""schema_version": 1,"#,
                with: #""schema_version": 1, "unknown": true,"#
            ),
            ConfigSchemaFixture.valid.replacingOccurrences(of: #""icon": "wand.and.sparkles","#, with: ""),
            ConfigSchemaFixture.valid.replacingOccurrences(
                of: #""transformation": "in_place""#,
                with: #""transformation": "other""#
            ),
            ConfigSchemaFixture.valid.replacingOccurrences(
                of: #""id": "11111111-1111-4111-8111-111111111111""#,
                with: #""id": "not-a-uuid""#
            ),
            ConfigSchemaFixture.valid.replacingOccurrences(
                of: #""mode_id": "11111111-1111-4111-8111-111111111111""#,
                with: #""mode_id": "22222222-2222-4222-8222-222222222222""#
            ),
            ConfigSchemaFixture.valid.replacingOccurrences(of: #""name": "Casual""#, with: #""name": "  Casual  ""#),
            ConfigSchemaFixture.valid.replacingOccurrences(
                of: #""retention_days": 30"#,
                with: #""retention_days": 12"#
            ),
            ConfigSchemaFixture.valid.replacingOccurrences(
                of: #""appearance": "dark""#,
                with: #""appearance": "sepia""#
            ),
            ConfigSchemaFixture.valid.replacingOccurrences(of: #""schema_version": 1,"#, with: ""),
            ConfigSchemaFixture.valid.replacingOccurrences(
                of: #""id": "11111111-1111-4111-8111-111111111111""#,
                with: #""id": "11111111-1111-4111-8111-111111111111", "extra": true"#
            ),
            ConfigSchemaFixture.valid.replacingOccurrences(
                of: #""asr_model": "unknown-asr""#,
                with: #""asr_model": " unknown-asr ""#
            ),
        ]

        var rejected: [Bool] = []
        for json in invalidFixtures {
            try Data(json.utf8).write(to: path)
            rejected.append(didThrow { _ = try Config.load(from: path) })
        }
        XCTAssertEqual(rejected, Array(repeating: true, count: invalidFixtures.count))
    }

    func testDuplicateIDsAndNormalizedNamesRejectWholeFile() throws {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(ConfigSchemaFixture.valid.utf8))
                as? [String: Any]
        )
        var modes = try XCTUnwrap(object["modes"] as? [[String: Any]])
        var second = try XCTUnwrap(modes.first)
        modes.append(second)
        object["modes"] = modes
        try JSONSerialization.data(withJSONObject: object).write(to: path)
        let duplicateIDRejected = didThrow { _ = try Config.load(from: path) }

        second["id"] = "22222222-2222-4222-8222-222222222222"
        second["name"] = "casual"
        modes[1] = second
        object["modes"] = modes
        try JSONSerialization.data(withJSONObject: object).write(to: path)
        let duplicateNameRejected = didThrow { _ = try Config.load(from: path) }

        XCTAssertEqual([duplicateIDRejected, duplicateNameRejected], [true, true])
    }

    private func didThrow(_ operation: () throws -> Void) -> Bool {
        do {
            try operation()
            return false
        } catch {
            return true
        }
    }
}

enum ConfigSchemaFixture {
    static let valid = """
    {
      "active_selection": {"mode_id": "11111111-1111-4111-8111-111111111111", "type": "mode"},
      "appearance": "dark",
      "asr_model": "unknown-asr",
      "badge_position": [123.5, 456.0],
      "hotkey": "alt_r",
      "input_device": null,
      "mode_cycle_hotkey": null,
      "modes": [
        {
          "icon": "wand.and.sparkles",
          "id": "11111111-1111-4111-8111-111111111111",
          "llm_model": "qwen2.5:3b",
          "name": "Casual",
          "system_prompt": "Keep my wording.",
          "transformation": "in_place",
          "vocabulary": ["FoldWise"]
        }
      ],
      "pause_audio": true,
      "retention_days": 30,
      "save_history": true,
      "schema_version": 1,
      "sidebar_collapsed": false,
      "toggle_hotkey": null
    }
    """
}
