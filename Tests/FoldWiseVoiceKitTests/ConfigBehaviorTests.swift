// Behavior of Config beyond serialization: defaults, fallbacks on bad input,
// and the mode-mutation helpers used by the settings UI.

import XCTest
@testable import FoldWiseVoiceKit

final class ConfigBehaviorTests: XCTestCase {
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

    func testDefaultConfigShape() {
        let config = Config.defaultConfig(path: path)
        XCTAssertEqual(config.modeOrder, ["Voice to Text", "Clean", "Email", "Bullets"])
        XCTAssertEqual(config.activeMode, "Clean")
        XCTAssertEqual(config.hotkey, "alt_r")
        XCTAssertNil(config.toggleHotkey)
        XCTAssertTrue(config.pauseAudio)
        XCTAssertEqual(Set(config.modes.keys), Set(config.modeOrder))
    }

    func testLoadOrCreateWritesDefaultsWhenFileMissing() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
        let config = Config.loadOrCreate(at: path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        XCTAssertEqual(config.activeMode, "Clean")
        // The written file must itself load cleanly.
        XCTAssertNoThrow(try Config.load(from: path))
    }

    func testLoadOrCreateFallsBackToDefaultsOnCorruptJSON() throws {
        try Data("{ this is not json".utf8).write(to: path)
        let config = Config.loadOrCreate(at: path)
        XCTAssertEqual(config.modeOrder, ["Voice to Text", "Clean", "Email", "Bullets"])
    }

    func testLoadThrowsWhenModesMissingOrEmpty() throws {
        try Data(#"{"active_mode": "Clean"}"#.utf8).write(to: path)
        XCTAssertThrowsError(try Config.load(from: path))
        try Data(#"{"modes": {}}"#.utf8).write(to: path)
        XCTAssertThrowsError(try Config.load(from: path))
    }

    func testUnknownActiveModeFallsBackToFirstModeInFileOrder() throws {
        let json = """
        {
          "active_mode": "Nope",
          "modes": {
            "Second": {"asr_model": "m", "llm_model": null, "system_prompt": null, "vocab": []},
            "First": {"asr_model": "m", "llm_model": null, "system_prompt": null, "vocab": []}
          }
        }
        """
        try Data(json.utf8).write(to: path)
        let config = try Config.load(from: path)
        XCTAssertEqual(config.activeMode, "Second")
        XCTAssertEqual(config.mode.name, "Second")
    }

    func testSetActiveModeIgnoresUnknownNames() {
        let config = Config.defaultConfig(path: path)
        config.setActiveMode("Does Not Exist")
        XCTAssertEqual(config.activeMode, "Clean")
        config.setActiveMode("Email")
        XCTAssertEqual(config.activeMode, "Email")
    }

    func testSetLLMModelOnlyTouchesLLMEnabledModes() {
        let config = Config.defaultConfig(path: path)
        config.setLLMModel("gemma3:1b")
        XCTAssertNil(config.modes["Voice to Text"]?.llmModel)
        XCTAssertEqual(config.modes["Clean"]?.llmModel, "gemma3:1b")
        XCTAssertEqual(config.modes["Email"]?.llmModel, "gemma3:1b")
        XCTAssertEqual(config.modes["Bullets"]?.llmModel, "gemma3:1b")
        XCTAssertEqual(config.llmModel, "gemma3:1b")
    }

    func testUsesLLMIsFalseForNilAndEmptyModel() {
        var mode = Mode(name: "M", asrModel: "m", llmModel: nil, systemPrompt: nil, vocab: [])
        XCTAssertFalse(mode.usesLLM)
        mode.llmModel = ""
        XCTAssertFalse(mode.usesLLM)
        mode.llmModel = "llama3.2:3b"
        XCTAssertTrue(mode.usesLLM)
    }
}
