import XCTest
@testable import FoldWiseVoiceKit

final class ModeLifecycleIntegrationTests: XCTestCase {
    private enum ActivePhase: String, CaseIterable {
        case listening
        case transcribing
        case polishing
        case inserting
    }

    private enum Mutation {
        case cycle
        case edit
        case rename
        case reorder
        case delete
    }

    private struct Attribution: Equatable {
        let id: ModeID?
        let name: String
    }

    private struct Outcome: Equatable {
        let phase: ActivePhase
        let currentSnapshot: Mode?
        let currentAttribution: Attribution?
        let nextSnapshot: Mode?
        let nextAttribution: Attribution?
        let committedSelection: DictationSelection
        let committedOrder: [ModeID]
        let nextCycleSelection: DictationSelection?
    }

    private struct Fixture {
        let config: Config
        let first: Mode
        let second: Mode
        let third: Mode
        let edited: Mode
        let renamed: Mode
        let firstID: ModeID
        let secondID: ModeID
        let thirdID: ModeID
    }

    private enum FixtureError: Error {
        case missingModeID
        case missingDeleteCandidate
    }

    func testModeCycleAcrossEveryActivePhaseFreezesCurrentAndAppliesNext() async throws {
        try await assertMutation(.cycle)
    }

    func testModeEditAcrossEveryActivePhaseFreezesCurrentAndAppliesNext() async throws {
        try await assertMutation(.edit)
    }

    func testModeRenameAcrossEveryActivePhaseFreezesCurrentAndAppliesNext() async throws {
        try await assertMutation(.rename)
    }

    func testModeReorderAcrossEveryActivePhaseFreezesCurrentAndAppliesNext() async throws {
        try await assertMutation(.reorder)
    }

    func testModeDeleteAcrossEveryActivePhaseFreezesCurrentAndAppliesNext() async throws {
        try await assertMutation(.delete)
    }

    private func assertMutation(
        _ mutation: Mutation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        var actual: [Outcome] = []
        var expected: [Outcome] = []
        for phase in ActivePhase.allCases {
            let fixture = makeFixture()
            try preparePersistence(for: fixture.config, in: self)
            try fixture.config.save()

            actual.append(try await run(mutation, during: phase, fixture: fixture))
            expected.append(expectedOutcome(for: mutation, phase: phase, fixture: fixture))
        }

        XCTAssertEqual(actual, expected, file: file, line: line)
    }

    private func run(
        _ mutation: Mutation,
        during phase: ActivePhase,
        fixture: Fixture
    ) async throws -> Outcome {
        let recorder = FakeRecorder()
        let transcriber = FakeTranscriber()
        transcriber.result = .success(transcript)
        let gate = OneShotPhaseGate(expectation: expectation(description: "entered \(phase.rawValue)"))
        if phase == .transcribing {
            transcriber.onTranscribe = { await gate.pause() }
        }
        let snapshots = ModeSnapshotLog()
        let history = RecordSpy()
        let pipeline = Pipeline(
            config: fixture.config,
            recorder: recorder,
            transcriber: transcriber,
            polish: { text, mode in
                snapshots.append(mode)
                if phase == .polishing { await gate.pause() }
                return text
            },
            insert: { _ in
                if phase == .inserting { await gate.pause() }
                return true
            },
            record: { history.record($0) },
            frontmostApp: { nil }
        )

        pipeline.startRecording()
        if phase == .listening {
            gate.expectation.fulfill()
            await fulfillment(of: [gate.expectation])
            try await apply(mutation, to: fixture)
            pipeline.stopRecording()
        } else {
            pipeline.stopRecording()
            await fulfillment(of: [gate.expectation])
            try await apply(mutation, to: fixture)
            await gate.resume()
        }
        await pipeline.awaitPendingJob()

        pipeline.startRecording()
        pipeline.stopRecording()
        await pipeline.awaitPendingJob()

        let entries = history.entries
        let capturedModes = snapshots.values
        let orderedIDs = try fixture.config.orderedModes.map { mode in
            guard let id = mode.id else { throw FixtureError.missingModeID }
            return id
        }
        return Outcome(
            phase: phase,
            currentSnapshot: capturedModes.first,
            currentAttribution: entries.first.map { Attribution(id: $0.modeID, name: $0.modeName) },
            nextSnapshot: capturedModes.dropFirst().first,
            nextAttribution: entries.dropFirst().first.map {
                Attribution(id: $0.modeID, name: $0.modeName)
            },
            committedSelection: fixture.config.selection,
            committedOrder: orderedIDs,
            nextCycleSelection: ModeCyclePolicy.nextSelection(
                after: fixture.config.selection,
                orderedModeIDs: orderedIDs
            )
        )
    }

    @MainActor
    private func apply(_ mutation: Mutation, to fixture: Fixture) throws {
        switch mutation {
        case .cycle:
            ModeCycleCommand(config: fixture.config).perform()
        case .edit:
            try fixture.config.saveMode(fixture.edited)
        case .rename:
            try fixture.config.saveMode(fixture.renamed)
        case .reorder:
            try fixture.config.replaceModes(
                [fixture.first, fixture.third, fixture.second],
                selection: fixture.config.selection
            )
        case .delete:
            guard let id = fixture.first.id,
                  let candidate = ModeLibraryPolicy.deleting(
                      id,
                      from: fixture.config.orderedModes,
                      selection: fixture.config.selection
                  )
            else { throw FixtureError.missingDeleteCandidate }
            try fixture.config.replaceModes(candidate.modes, selection: candidate.selection)
        }
    }

    private func expectedOutcome(
        for mutation: Mutation,
        phase: ActivePhase,
        fixture: Fixture
    ) -> Outcome {
        let nextMode: Mode?
        let selection: DictationSelection
        let order: [ModeID]
        let nextCycle: DictationSelection?

        switch mutation {
        case .cycle:
            nextMode = fixture.second
            selection = .mode(fixture.secondID)
            order = [fixture.firstID, fixture.secondID, fixture.thirdID]
            nextCycle = .mode(fixture.thirdID)
        case .edit:
            nextMode = fixture.edited
            selection = .mode(fixture.firstID)
            order = [fixture.firstID, fixture.secondID, fixture.thirdID]
            nextCycle = .mode(fixture.secondID)
        case .rename:
            nextMode = fixture.renamed
            selection = .mode(fixture.firstID)
            order = [fixture.firstID, fixture.secondID, fixture.thirdID]
            nextCycle = .mode(fixture.secondID)
        case .reorder:
            nextMode = fixture.first
            selection = .mode(fixture.firstID)
            order = [fixture.firstID, fixture.thirdID, fixture.secondID]
            nextCycle = .mode(fixture.thirdID)
        case .delete:
            nextMode = nil
            selection = .voiceToText
            order = [fixture.secondID, fixture.thirdID]
            nextCycle = .mode(fixture.secondID)
        }

        return Outcome(
            phase: phase,
            currentSnapshot: fixture.first,
            currentAttribution: Attribution(id: fixture.firstID, name: fixture.first.name),
            nextSnapshot: nextMode,
            nextAttribution: Attribution(
                id: nextMode?.id,
                name: nextMode?.name ?? "Voice to Text"
            ),
            committedSelection: selection,
            committedOrder: order,
            nextCycleSelection: nextCycle
        )
    }

    private func makeFixture() -> Fixture {
        let firstID = ModeID.random()
        let secondID = ModeID.random()
        let thirdID = ModeID.random()
        let first = mode(
            id: firstID, name: "First", icon: "1.circle", model: "first-model"
        )
        let second = mode(
            id: secondID, name: "Second", icon: "2.circle", model: "second-model"
        )
        let third = mode(
            id: thirdID, name: "Third", icon: "3.circle", model: "third-model"
        )
        let edited = Mode(
            id: firstID,
            name: "Edited",
            icon: "pencil.circle",
            asrModel: ASRModelCatalog.defaultID,
            llmModel: "edited-model",
            transformation: .expanding,
            systemPrompt: "Reshape the complete transcript.",
            vocabulary: ["Edited", "FoldWise"]
        )
        var renamed = first
        renamed.name = "Renamed"
        let config = Config(
            preferences: Config.Preferences(
                selection: .mode(firstID),
                hotkey: "F5",
                toggleHotkey: nil,
                pauseAudio: false,
                inputDevice: nil,
                asrModel: ASRModelCatalog.defaultID,
                appearance: .system,
                saveHistory: true,
                historyRetention: .default,
                sidebarCollapsed: false
            ),
            badgePosition: nil,
            orderedModes: [first, second, third],
            path: FileManager.default.temporaryDirectory
                .appendingPathComponent("foldwise-mode-integration-\(UUID().uuidString)")
                .appendingPathComponent("config.json")
        )
        return Fixture(
            config: config,
            first: first,
            second: second,
            third: third,
            edited: edited,
            renamed: renamed,
            firstID: firstID,
            secondID: secondID,
            thirdID: thirdID
        )
    }

    private func mode(id: ModeID, name: String, icon: String, model: String) -> Mode {
        Mode(
            id: id,
            name: name,
            icon: icon,
            asrModel: ASRModelCatalog.defaultID,
            llmModel: model,
            transformation: .inPlace,
            systemPrompt: "Keep \(name) wording.",
            vocabulary: [name]
        )
    }

    private var transcript: String {
        "this transcript is unquestionably longer than the forty character polish threshold"
    }
}

private final class OneShotPhaseGate: @unchecked Sendable {
    let expectation: XCTestExpectation
    private let lock = NSLock()
    private let latch = Latch()
    private var hasPaused = false

    init(expectation: XCTestExpectation) {
        self.expectation = expectation
    }

    func pause() async {
        let shouldPause = lock.withLock {
            guard !hasPaused else { return false }
            hasPaused = true
            return true
        }
        guard shouldPause else { return }
        expectation.fulfill()
        await latch.wait()
    }

    func resume() async {
        await latch.open()
    }
}

private final class ModeSnapshotLog: @unchecked Sendable {
    private let lock = NSLock()
    private var modes: [Mode] = []

    func append(_ mode: Mode) {
        lock.withLock { modes.append(mode) }
    }

    var values: [Mode] {
        lock.withLock { modes }
    }
}
