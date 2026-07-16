import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class ConfigBehaviorTests: XCTestCase {
    private struct DefaultState: Equatable {
        let names: [String]
        let activeName: String
        let icons: [String]
        let transformations: [ModeTransformation]
        let vocabulary: [[String]]
        let models: [String?]
        let uniqueIDCount: Int
    }

    private struct SelectedState: Equatable {
        let selection: DictationSelection
        let name: String
        let icon: String
        let transformation: ModeTransformation
        let usesLLM: Bool
    }

    private struct NormalizedState: Equatable {
        let name: String
        let model: String?
        let prompt: String?
        let vocabulary: [String]
        let persisted: Mode?
    }

    private struct CommitState: Equatable {
        let modes: [Mode]
        let selection: DictationSelection?
        let data: Data?
        let notifications: [Config.ChangeSet]
        let rejected: Bool
    }

    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("foldwise-config-behavior-tests-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private var path: URL {
        directory.appendingPathComponent("config.json")
    }

    func testDefaultConfigContainsCasualThenEmailWithStableSelection() {
        let config = Config.defaultConfig(path: path)

        XCTAssertEqual(
            DefaultState(
                names: config.orderedModes.map(\.name),
                activeName: config.activeMode,
                icons: config.orderedModes.map(\.icon),
                transformations: config.orderedModes.map(\.transformation),
                vocabulary: config.orderedModes.map(\.vocab),
                models: config.orderedModes.map(\.llmModel),
                uniqueIDCount: Set(config.orderedModes.compactMap(\.id)).count
            ),
            DefaultState(
                names: ["Casual", "Email"], activeName: "Casual",
                icons: ["wand.and.sparkles", "envelope"],
                transformations: [.inPlace, .expanding], vocabulary: [[], []],
                models: ["qwen2.5:3b", "qwen2.5:3b"], uniqueIDCount: 2
            )
        )
    }

    func testVoiceToTextSelectionBypassesPolish() throws {
        let config = Config.defaultConfig(path: path)

        try config.select(.voiceToText)

        XCTAssertEqual(
            selectedState(config),
            SelectedState(
                selection: .voiceToText, name: "Voice to Text", icon: "waveform",
                transformation: .inPlace, usesLLM: false
            )
        )
    }

    func testRenamePreservesStableSelectionAndExplicitTransformation() throws {
        let config = Config.defaultConfig(path: path)
        let selectedID = try XCTUnwrap(config.orderedModes.first?.id)

        var mode = try XCTUnwrap(config.orderedModes.first)
        mode.name = "Conversation"
        mode.transformation = .expanding
        try config.saveMode(mode)

        XCTAssertEqual(
            selectedState(config),
            SelectedState(
                selection: .mode(selectedID), name: "Conversation",
                icon: "wand.and.sparkles", transformation: .expanding, usesLLM: true
            )
        )
    }

    func testUpdateNormalizesModeAndVocabularyBeforePersisting() throws {
        let config = Config.defaultConfig(path: path)

        var candidate = try XCTUnwrap(config.orderedModes.first)
        candidate.name = "  Café\n  Notes  "
        candidate.llmModel = " qwen2.5:3b "
        candidate.systemPrompt = "  Keep this wording.  "
        candidate.vocab = [" FoldWise ", "foldwise", "", " Résumé "]
        try config.saveMode(candidate)

        let mode = try XCTUnwrap(config.orderedModes.first)
        XCTAssertEqual(
            NormalizedState(
                name: mode.name, model: mode.llmModel, prompt: mode.systemPrompt,
                vocabulary: mode.vocab,
                persisted: try Config.load(from: path).orderedModes.first
            ),
            NormalizedState(
                name: "Café Notes", model: "qwen2.5:3b", prompt: "Keep this wording.",
                vocabulary: ["FoldWise", "Résumé"], persisted: mode
            )
        )
    }

    func testZeroModesIsValidOnlyForVoiceToText() throws {
        let config = Config.defaultConfig(path: path)

        try config.replaceModes([], selection: .voiceToText)

        XCTAssertEqual(
            CommitState(
                modes: config.orderedModes,
                selection: try Config.load(from: path).selection,
                data: nil, notifications: [], rejected: false
            ),
            CommitState(
                modes: [], selection: .voiceToText,
                data: nil, notifications: [], rejected: false
            )
        )
    }

    func testZeroModesRejectsModeSelectionWithoutChangingCommittedState() {
        let config = Config.defaultConfig(path: path)
        let original = config.orderedModes

        let rejected = didThrow { try config.replaceModes([], selection: config.selection) }

        XCTAssertEqual(
            CommitState(
                modes: config.orderedModes, selection: nil,
                data: nil, notifications: [], rejected: rejected
            ),
            CommitState(
                modes: original, selection: nil,
                data: nil, notifications: [], rejected: true
            )
        )
    }

    func testValidationFailureLeavesDiskLiveStateAndObserversAtCommit() throws {
        let config = Config.defaultConfig(path: path)
        try config.save()
        let originalData = try Data(contentsOf: path)
        let originalModes = config.orderedModes
        var received: [Config.ChangeSet] = []
        config.onChange { received.append($0) }

        var duplicate = try XCTUnwrap(config.orderedModes.last)
        duplicate.name = "casual"
        let rejected = didThrow { try config.saveMode(duplicate) }

        XCTAssertEqual(
            CommitState(
                modes: config.orderedModes, selection: nil,
                data: try Data(contentsOf: path), notifications: received,
                rejected: rejected
            ),
            CommitState(
                modes: originalModes, selection: nil,
                data: originalData, notifications: [], rejected: true
            )
        )
    }

    func testResolvePathPrefersExplicitConfigPath() {
        XCTAssertEqual(Config.resolvePath(cliPath: path.path), path)
    }

    private func selectedState(_ config: Config) -> SelectedState {
        SelectedState(
            selection: config.selection, name: config.activeMode, icon: config.mode.icon,
            transformation: config.mode.transformation, usesLLM: config.mode.usesLLM
        )
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
