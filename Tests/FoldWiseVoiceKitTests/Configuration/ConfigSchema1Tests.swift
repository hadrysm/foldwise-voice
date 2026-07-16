import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class ConfigSchema1Tests: XCTestCase {
    private struct LoadedState: Equatable {
        let selection: DictationSelection
        let names: [String]
        let transformation: ModeTransformation?
        let asrModel: String
        let readOnly: Bool
    }

    private struct RecoveryState: Equatable {
        let readOnly: Bool
        let selection: DictationSelection
        let usesLLM: Bool
        let originalData: Data
        let messageMatches: Bool
    }

    private struct ResetState: Equatable {
        let backupData: Data
        let readOnly: Bool
        let activeMode: String
        let relaunchedMode: String
    }

    private struct RecoveryDictationState: Equatable {
        let originalData: Data
        let modeName: String?
        let modeID: ModeID?
        let text: String?
    }

    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("foldwise-config-schema-tests-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private var path: URL {
        directory.appendingPathComponent("config.json")
    }

    func testLoadReadsExactSchemaOneFixture() throws {
        let json = """
        {
          "active_selection": {
            "mode_id": "11111111-1111-4111-8111-111111111111",
            "type": "mode"
          },
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
        try Data(json.utf8).write(to: path)

        let config = try Config.load(from: path)

        XCTAssertEqual(
            LoadedState(
                selection: config.selection,
                names: config.orderedModes.map(\.name),
                transformation: config.orderedModes.first?.transformation,
                asrModel: config.asrModel,
                readOnly: config.isReadOnly
            ),
            LoadedState(
                selection: .mode(
                    try XCTUnwrap(ModeID(rawValue: "11111111-1111-4111-8111-111111111111"))
                ),
                names: ["Casual"], transformation: .inPlace,
                asrModel: "unknown-asr", readOnly: false
            )
        )
    }

    func testMissingFileCreatesLoadableDefaults() throws {
        let config = Config.loadOrCreate(at: path)

        XCTAssertEqual(
            LoadedState(
                selection: config.selection,
                names: try Config.load(from: path).orderedModes.map(\.name),
                transformation: config.orderedModes.first?.transformation,
                asrModel: config.asrModel,
                readOnly: config.isReadOnly
            ),
            LoadedState(
                selection: config.selection, names: ["Casual", "Email"],
                transformation: .inPlace, asrModel: ASRModelCatalog.defaultID,
                readOnly: false
            )
        )
    }

    func testMalformedFileEntersReadOnlyRecoveryWithoutTouchingOriginal() throws {
        let original = Data("{ definitely not JSON".utf8)
        try original.write(to: path)

        let config = Config.loadOrCreate(at: path)

        assertThrowsConfigError(.readOnlyRecovery, try config.select(.voiceToText))
        XCTAssertEqual(
            RecoveryState(
                readOnly: config.isReadOnly, selection: config.selection,
                usesLLM: config.mode.usesLLM, originalData: try Data(contentsOf: path),
                messageMatches: true
            ),
            RecoveryState(
                readOnly: true, selection: .voiceToText, usesLLM: false,
                originalData: original, messageMatches: true
            )
        )
    }

    func testUnsupportedSchemaEntersRecoveryWithoutRewriting() throws {
        let original = Data(ConfigSchemaFixture.valid
            .replacingOccurrences(of: #""schema_version": 1"#, with: #""schema_version": 2"#)
            .utf8)
        try original.write(to: path)

        let config = Config.loadOrCreate(at: path)

        assertThrowsConfigError(.readOnlyRecovery, try config.select(.voiceToText))
        XCTAssertEqual(
            RecoveryState(
                readOnly: config.isReadOnly, selection: config.selection,
                usesLLM: config.mode.usesLLM, originalData: try Data(contentsOf: path),
                messageMatches: config.recovery?.message.contains("Unsupported schema_version 2") == true
            ),
            RecoveryState(
                readOnly: true, selection: .voiceToText, usesLLM: false,
                originalData: original, messageMatches: true
            )
        )
    }

    func testRecoveryRunsVoiceToTextWithoutTouchingRejectedFile() async throws {
        let original = Data("{ definitely not JSON".utf8)
        try original.write(to: path)
        let config = Config.loadOrCreate(at: path)
        let transcriber = FakeTranscriber()
        transcriber.result = .success("recovery dictation remains available")
        let recorded = RecordSpy()
        let pipeline = Pipeline(
            config: config,
            recorder: FakeRecorder(),
            transcriber: transcriber,
            insert: { _ in true },
            record: { recorded.record($0) },
            frontmostApp: { nil }
        )

        pipeline.startRecording()
        pipeline.stopRecording()
        await pipeline.awaitPendingJob()

        let entry = recorded.entries.first
        XCTAssertEqual(
            RecoveryDictationState(
                originalData: try Data(contentsOf: path),
                modeName: entry?.modeName,
                modeID: entry?.modeID,
                text: entry?.text
            ),
            RecoveryDictationState(
                originalData: original,
                modeName: "Voice to Text",
                modeID: nil,
                text: "recovery dictation remains available"
            )
        )
    }

    func testResetBacksUpRejectedBytesBeforeWritingFreshDefaults() throws {
        let original = Data("invalid configuration".utf8)
        try original.write(to: path)
        let config = Config.loadOrCreate(at: path)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let backup = try config.resetRecovery(now: now)

        XCTAssertEqual(
            ResetState(
                backupData: try Data(contentsOf: backup), readOnly: config.isReadOnly,
                activeMode: config.mode.name,
                relaunchedMode: try Config.load(from: path).mode.name
            ),
            ResetState(
                backupData: original, readOnly: false,
                activeMode: "Casual", relaunchedMode: "Casual"
            )
        )
    }
}
