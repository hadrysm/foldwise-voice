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
        XCTAssertNil(config.inputDevice)
        XCTAssertEqual(config.appearance, .system)
        XCTAssertEqual(Set(config.modes.keys), Set(config.modeOrder))
    }

    func testAppearanceMissingAndInvalidValuesLoadAsSystem() throws {
        let values = ["", #", "appearance": "sepia""#, #", "appearance": 42"#]

        for value in values {
            let json = """
            {
              "active_mode": "Only"\(value),
              "modes": {
                "Only": {"asr_model": "m", "llm_model": null, "system_prompt": null, "vocab": []}
              }
            }
            """
            try Data(json.utf8).write(to: path)
            XCTAssertEqual(try Config.load(from: path).appearance, .system)
        }
    }

    func testInputDeviceMissingNullAndInvalidValuesLoadAsSystemDefault() throws {
        let values = ["", #", "input_device": null"#, #", "input_device": 42"#]

        for value in values {
            let json = """
            {
              "active_mode": "Only"\(value),
              "modes": {
                "Only": {"asr_model": "m", "llm_model": null, "system_prompt": null, "vocab": []}
              }
            }
            """
            try Data(json.utf8).write(to: path)
            XCTAssertNil(try Config.load(from: path).inputDevice)
        }
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

    func testModeFallsBackToFirstOrderedModeAfterLiveMutation() {
        let config = Config.defaultConfig(path: path)
        config.modes.removeValue(forKey: config.activeMode)

        XCTAssertEqual(config.mode.name, "Voice to Text")
    }

    func testModeFallsBackToRawDictationWhenLiveModesBecomeEmpty() {
        let config = Config.defaultConfig(path: path)
        config.modes.removeAll()

        let mode = config.mode

        XCTAssertEqual(mode.name, "Voice to Text")
        XCTAssertFalse(mode.usesLLM)
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

    func testLLMModelIsNilWhenNoModeUsesLLM() {
        let config = Config.defaultConfig(path: path)
        config.modes = config.modes.mapValues { mode in
            var mode = mode
            mode.llmModel = nil
            return mode
        }

        XCTAssertNil(config.llmModel)
    }

    func testDefaultConfigUsesParakeetV3ForASRModel() {
        // Fresh install defaults to our own id, not the old MLX fossil (ADR-0006).
        let config = Config.defaultConfig(path: path)
        XCTAssertEqual(config.asrModel, "parakeet-v3")
        for name in config.modeOrder {
            XCTAssertEqual(config.modes[name]?.asrModel, "parakeet-v3")
        }
    }

    func testASRModelReadsTheFirstModeInOrder() throws {
        let json = """
        {
          "active_mode": "Second",
          "modes": {
            "First": {"asr_model": "id-first", "llm_model": null, "system_prompt": null, "vocab": []},
            "Second": {"asr_model": "id-second", "llm_model": null, "system_prompt": null, "vocab": []}
          }
        }
        """
        try Data(json.utf8).write(to: path)
        let config = try Config.load(from: path)
        XCTAssertEqual(config.asrModel, "id-first")
    }

    func testASRModelFallsBackToDefaultWhenLiveModesBecomeEmpty() {
        let config = Config.defaultConfig(path: path)
        config.modes.removeAll()

        XCTAssertEqual(config.asrModel, ASRModelCatalog.defaultID)
    }

    func testSetASRModelWritesEveryMode() {
        let config = Config.defaultConfig(path: path)
        config.setASRModel("whisper-large-v3-turbo")
        for name in config.modeOrder {
            XCTAssertEqual(config.modes[name]?.asrModel, "whisper-large-v3-turbo")
        }
        XCTAssertEqual(config.asrModel, "whisper-large-v3-turbo")
    }

    func testPickingAModelOverwritesAPreservedFossilAcrossModes() throws {
        let json = """
        {
          "active_mode": "Only",
          "modes": {
            "Only": {
              "asr_model": "mlx-community/whisper-large-v3-turbo",
              "llm_model": null, "system_prompt": null, "vocab": []
            }
          }
        }
        """
        try Data(json.utf8).write(to: path)
        let config = try Config.load(from: path)
        XCTAssertEqual(config.asrModel, "mlx-community/whisper-large-v3-turbo")
        config.setASRModel("parakeet-v3")
        XCTAssertEqual(config.asrModel, "parakeet-v3")
    }

    func testUsesLLMIsFalseForNilAndEmptyModel() {
        var mode = Mode(name: "M", asrModel: "m", llmModel: nil, systemPrompt: nil, vocab: [])
        XCTAssertFalse(mode.usesLLM)
        mode.llmModel = ""
        XCTAssertFalse(mode.usesLLM)
        mode.llmModel = "llama3.2:3b"
        XCTAssertTrue(mode.usesLLM)
    }

    func testBuiltInInPlaceModesDoNotExpand() {
        let config = Config.defaultConfig(path: path)
        XCTAssertEqual(config.modes["Clean"]?.expands, false)
        XCTAssertEqual(config.modes["Voice to Text"]?.expands, false)
    }

    func testBuiltInExpandingModesExpand() {
        let config = Config.defaultConfig(path: path)
        XCTAssertEqual(config.modes["Email"]?.expands, true)
        XCTAssertEqual(config.modes["Bullets"]?.expands, true)
    }

    func testLoadedUserDefinedModeDefaultsToExpanding() throws {
        let json = """
        {
          "active_mode": "Custom",
          "modes": {
            "Custom": {"asr_model": "m", "llm_model": "qwen2.5:3b", "system_prompt": "do a thing", "vocab": []}
          }
        }
        """
        try Data(json.utf8).write(to: path)
        let config = try Config.load(from: path)
        XCTAssertEqual(config.modes["Custom"]?.expands, true)
    }

    func testReloadedBuiltInKeepsInPlaceCalibration() throws {
        // `expands` is never persisted, so a reloaded Clean must re-derive its
        // In-place calibration from the name — not silently become loose.
        try Config.defaultConfig(path: path).save()
        let reloaded = try Config.load(from: path)
        XCTAssertEqual(reloaded.modes["Clean"]?.expands, false)
    }

    func testExpandsIsNotPersisted() throws {
        try Config.defaultConfig(path: path).save()
        let written = try String(contentsOf: path, encoding: .utf8)
        XCTAssertFalse(written.contains("expands"))
    }

    func testResolvePathPrefersExplicitCLIPath() {
        XCTAssertEqual(Config.resolvePath(cliPath: path.path), path)
    }
}
