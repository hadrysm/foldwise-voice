// Round-trip tests for the hand-rolled modes.json serializer: load → save →
// reload must preserve everything the app cares about, including the on-disk
// mode order that JSONSerialization would otherwise lose.
//
// Nothing in this test target may touch Transcriber/AsrManager: constructing
// them downloads the ~600 MB Parakeet model, which must never happen in tests.

import XCTest
@testable import FoldWiseVoiceKit

final class ConfigRoundTripTests: XCTestCase {
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

    private func write(_ json: String) throws -> URL {
        let url = dir.appendingPathComponent("modes.json")
        try Data(json.utf8).write(to: url)
        return url
    }

    private let fixture = """
    {
      "active_mode": "Middle",
      "hotkey": "cmd_r",
      "toggle_hotkey": null,
      "pause_audio": false,
      "hud_position": [100, 200],
      "hud_style": "minimal",
      "modes": {
        "Zebra": {
          "asr_model": "custom-model",
          "llm_model": "llama3.2:3b",
          "system_prompt": "Say \\"hi\\"\\nplease",
          "vocab": ["FoldWise", "Ollama"]
        },
        "Alpha": {
          "asr_model": "custom-model",
          "llm_model": null,
          "system_prompt": null,
          "vocab": []
        },
        "Middle": {
          "asr_model": "other-model",
          "llm_model": "",
          "system_prompt": null,
          "vocab": []
        }
      }
    }
    """

    private func roundTrip(_ json: String) throws -> Config {
        let url = try write(json)
        let config = try Config.load(from: url)
        try config.save()
        return try Config.load(from: url)
    }

    func testModeOrderSurvivesNonAlphabetically() throws {
        let reloaded = try roundTrip(fixture)
        XCTAssertEqual(reloaded.modeOrder, ["Zebra", "Alpha", "Middle"])
    }

    func testScalarFieldsSurvive() throws {
        let reloaded = try roundTrip(fixture)
        XCTAssertEqual(reloaded.activeMode, "Middle")
        XCTAssertEqual(reloaded.hotkey, "cmd_r")
        XCTAssertNil(reloaded.toggleHotkey)
        XCTAssertFalse(reloaded.pauseAudio)
        XCTAssertEqual(reloaded.hudStyle, "minimal")
    }

    func testIntegerHUDPositionNormalizesToDoubles() throws {
        let reloaded = try roundTrip(fixture)
        XCTAssertEqual(reloaded.hudPosition, [100.0, 200.0])
    }

    func testASRModelIsPreservedEvenThoughUnusedBySwiftApp() throws {
        let reloaded = try roundTrip(fixture)
        XCTAssertEqual(reloaded.modes["Zebra"]?.asrModel, "custom-model")
        XCTAssertEqual(reloaded.modes["Middle"]?.asrModel, "other-model")
    }

    func testEscapedStringsSurvive() throws {
        let reloaded = try roundTrip(fixture)
        XCTAssertEqual(reloaded.modes["Zebra"]?.systemPrompt, "Say \"hi\"\nplease")
        XCTAssertEqual(reloaded.modes["Zebra"]?.vocab, ["FoldWise", "Ollama"])
    }

    func testSavedFileIsValidJSONWithTrailingNewline() throws {
        let url = try write(fixture)
        let config = try Config.load(from: url)
        try config.save()
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.hasSuffix("\n"))
        let data = try XCTUnwrap(text.data(using: .utf8))
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
    }

    func testSaveHistoryDefaultsToTrueWhenAbsent() throws {
        // The fixture carries no `save_history` key: history is saved by
        // default (PRD #78), so a config predating the setting reads as on.
        let reloaded = try roundTrip(fixture)
        XCTAssertTrue(reloaded.saveHistory)
    }

    func testSaveHistoryRoundTripsWhenOff() throws {
        let json = """
        {
          "active_mode": "Only",
          "hotkey": "alt_r",
          "pause_audio": true,
          "save_history": false,
          "modes": {
            "Only": {
              "asr_model": "m",
              "llm_model": null,
              "system_prompt": null,
              "vocab": []
            }
          }
        }
        """
        let reloaded = try roundTrip(json)
        XCTAssertFalse(reloaded.saveHistory)
    }

    func testSaveIsStableAcrossRepeatedRoundTrips() throws {
        let url = try write(fixture)
        let config = try Config.load(from: url)
        try config.save()
        let first = try String(contentsOf: url, encoding: .utf8)
        let reloaded = try Config.load(from: url)
        try reloaded.save()
        let second = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(first, second)
    }
}
