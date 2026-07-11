import XCTest
@testable import FoldWiseVoiceKit

final class AudioDuckCoordinatorTests: XCTestCase {
    func testDuckPausesPlayingPlayersAndMutesOutputUntilRestore() {
        let scheduler = ManualAudioDuckScheduler()
        let effects = FakeAudioDuckSystemEffects(
            playing: ["Spotify": true, "Music": false], outputMuted: false
        )
        let coordinator = makeCoordinator(effects: effects, scheduler: scheduler)

        coordinator.duck()
        scheduler.runNext()
        coordinator.restore()
        scheduler.runNext()

        XCTAssertEqual(
            effects.events,
            [
                .checkedPlayer("Spotify"), .pausedPlayer("Spotify"),
                .checkedPlayer("Music"), .checkedOutputMute, .setOutputMuted(true),
                .setOutputMuted(false), .playedPlayer("Spotify"),
            ]
        )
    }

    func testDuplicateRequestsDoNotRepeatEffects() {
        let scheduler = ManualAudioDuckScheduler()
        let effects = FakeAudioDuckSystemEffects(playing: [:], outputMuted: false)
        let coordinator = makeCoordinator(effects: effects, scheduler: scheduler)

        coordinator.duck()
        coordinator.duck()
        scheduler.runNext()
        coordinator.duck()
        coordinator.restore()
        coordinator.restore()
        scheduler.runNext()

        XCTAssertEqual(
            effects.events,
            [.checkedOutputMute, .setOutputMuted(true), .setOutputMuted(false)]
        )
    }

    func testRestoreCancelsDuckBeforeEffectsBegin() {
        let scheduler = ManualAudioDuckScheduler()
        let effects = FakeAudioDuckSystemEffects(playing: ["Spotify": true], outputMuted: false)
        let coordinator = makeCoordinator(effects: effects, scheduler: scheduler)

        coordinator.duck()
        coordinator.restore()
        scheduler.runNext()

        XCTAssertTrue(effects.events.isEmpty)
    }

    func testLatestDuckSupersedesAnOlderRestore() {
        let scheduler = ManualAudioDuckScheduler()
        let effects = FakeAudioDuckSystemEffects(playing: [:], outputMuted: false)
        let coordinator = makeCoordinator(effects: effects, scheduler: scheduler)

        coordinator.duck()
        coordinator.restore()
        coordinator.duck()
        scheduler.runNext()

        XCTAssertEqual(effects.events, [.checkedOutputMute, .setOutputMuted(true)])
    }

    func testOutOfOrderRestoreRequestedDuringDuckRunsAfterDuckCompletes() {
        let scheduler = ManualAudioDuckScheduler()
        let effects = FakeAudioDuckSystemEffects(
            playing: ["Spotify": true], outputMuted: false
        )
        let coordinator = makeCoordinator(effects: effects, scheduler: scheduler)
        effects.onPause = { coordinator.restore() }

        coordinator.duck()
        scheduler.runNext()

        XCTAssertEqual(
            effects.events,
            [
                .checkedPlayer("Spotify"), .pausedPlayer("Spotify"),
                .checkedOutputMute, .setOutputMuted(true), .setOutputMuted(false),
                .playedPlayer("Spotify"),
            ]
        )
    }

    func testFailedEffectsAreNotUndoneButSuccessfulEffectsStillRestore() {
        let scheduler = ManualAudioDuckScheduler()
        let effects = FakeAudioDuckSystemEffects(
            playing: ["Spotify": true, "Music": true], outputMuted: false
        )
        effects.pauseResults = ["Spotify": false, "Music": true]
        effects.setMuteResults = [true: false]
        let coordinator = makeCoordinator(effects: effects, scheduler: scheduler)

        coordinator.duck()
        scheduler.runNext()
        coordinator.restore()
        scheduler.runNext()

        XCTAssertEqual(
            effects.events,
            [
                .checkedPlayer("Spotify"), .pausedPlayer("Spotify"),
                .checkedPlayer("Music"), .pausedPlayer("Music"),
                .checkedOutputMute, .setOutputMuted(true), .playedPlayer("Music"),
            ]
        )
    }

    func testFailedRestoreIsRetriedWithoutRepeatingSuccessfulRestoration() {
        let scheduler = ManualAudioDuckScheduler()
        let effects = FakeAudioDuckSystemEffects(
            playing: ["Spotify": true, "Music": true], outputMuted: false
        )
        let coordinator = makeCoordinator(effects: effects, scheduler: scheduler)

        coordinator.duck()
        scheduler.runNext()
        effects.playResults["Spotify"] = false
        effects.setMuteResults[false] = false
        coordinator.restore()
        scheduler.runNext()
        effects.playResults["Spotify"] = true
        effects.setMuteResults[false] = true
        coordinator.restore()
        scheduler.runNext()

        XCTAssertEqual(
            effects.events.suffix(5),
            [
                .setOutputMuted(false), .playedPlayer("Spotify"), .playedPlayer("Music"),
                .setOutputMuted(false), .playedPlayer("Spotify"),
            ]
        )
    }

    func testDuckSupersedingFailedRestorePreservesPendingUnmute() {
        let scheduler = ManualAudioDuckScheduler()
        let effects = FakeAudioDuckSystemEffects(playing: [:], outputMuted: false)
        let coordinator = makeCoordinator(effects: effects, scheduler: scheduler)

        coordinator.duck()
        scheduler.runNext()
        effects.setMuteResults[false] = false
        coordinator.restore()
        scheduler.runNext()
        effects.outputMuted = true
        coordinator.duck()
        scheduler.runNext()
        effects.setMuteResults[false] = true
        coordinator.restore()
        scheduler.runNext()

        XCTAssertEqual(
            effects.events,
            [
                .checkedOutputMute, .setOutputMuted(true), .setOutputMuted(false),
                .checkedOutputMute, .setOutputMuted(false),
            ]
        )
    }

    func testRestoreKeepsOutputMutedWhenItWasAlreadyMuted() {
        let scheduler = ManualAudioDuckScheduler()
        let effects = FakeAudioDuckSystemEffects(playing: [:], outputMuted: true)
        let coordinator = makeCoordinator(effects: effects, scheduler: scheduler)

        coordinator.duck()
        scheduler.runNext()
        coordinator.restore()
        scheduler.runNext()

        XCTAssertEqual(effects.events, [.checkedOutputMute])
    }

    private func makeCoordinator(
        effects: FakeAudioDuckSystemEffects,
        scheduler: ManualAudioDuckScheduler
    ) -> AudioDuckCoordinator {
        AudioDuckCoordinator(
            effects: effects,
            players: Array(effects.playing.keys).sorted(by: >),
            schedule: { scheduler.schedule($0) }
        )
    }
}

private final class ManualAudioDuckScheduler {
    private var jobs: [() -> Void] = []

    func schedule(_ job: @escaping () -> Void) {
        jobs.append(job)
    }

    func runNext() {
        jobs.removeFirst()()
    }
}

private final class FakeAudioDuckSystemEffects: AudioDuckSystemEffects {
    enum Event: Equatable {
        case checkedPlayer(String)
        case pausedPlayer(String)
        case playedPlayer(String)
        case checkedOutputMute
        case setOutputMuted(Bool)
    }

    let playing: [String: Bool]
    var outputMuted: Bool?
    var pauseResults: [String: Bool] = [:]
    var playResults: [String: Bool] = [:]
    var setMuteResults: [Bool: Bool] = [:]
    var onPause: (() -> Void)?
    private(set) var events: [Event] = []

    init(playing: [String: Bool], outputMuted: Bool?) {
        self.playing = playing
        self.outputMuted = outputMuted
    }

    func isPlayerPlaying(_ player: String) -> Bool? {
        events.append(.checkedPlayer(player))
        return playing[player]
    }

    func pausePlayer(_ player: String) -> Bool {
        events.append(.pausedPlayer(player))
        onPause?()
        return pauseResults[player, default: true]
    }

    func playPlayer(_ player: String) -> Bool {
        events.append(.playedPlayer(player))
        return playResults[player, default: true]
    }

    func isOutputMuted() -> Bool? {
        events.append(.checkedOutputMute)
        return outputMuted
    }

    func setOutputMuted(_ muted: Bool) -> Bool {
        events.append(.setOutputMuted(muted))
        return setMuteResults[muted, default: true]
    }
}
