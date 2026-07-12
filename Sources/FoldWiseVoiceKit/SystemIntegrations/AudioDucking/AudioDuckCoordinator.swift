import Foundation

protocol AudioDucking: AnyObject {
    func duck()
    func restore()
}

protocol AudioDuckSystemEffects: AnyObject {
    func isPlayerPlaying(_ player: String) -> Bool?
    func pausePlayer(_ player: String) -> Bool
    func playPlayer(_ player: String) -> Bool
    func isOutputMuted() -> Bool?
    func setOutputMuted(_ muted: Bool) -> Bool
}

final class AudioDuckCoordinator: AudioDucking {
    typealias Schedule = (@escaping () -> Void) -> Void

    private struct Restoration {
        let players: [String]
        let unmuteOutput: Bool

        func merging(_ other: Restoration) -> Restoration {
            let additionalPlayers = other.players.filter { !players.contains($0) }
            return Restoration(
                players: players + additionalPlayers,
                unmuteOutput: unmuteOutput || other.unmuteOutput
            )
        }
    }

    private let effects: AudioDuckSystemEffects
    private let players: [String]
    private let schedule: Schedule
    private let lock = NSLock()

    private var generation = 0
    private var wantsDucked = false
    private var workerScheduled = false
    private var hasPendingRestoration = false
    private var restoration: Restoration?

    init(
        effects: AudioDuckSystemEffects,
        players: [String] = ["Spotify", "Music"],
        schedule: @escaping Schedule
    ) {
        self.effects = effects
        self.players = players
        self.schedule = schedule
    }

    func duck() {
        request(ducked: true)
    }

    func restore() {
        request(ducked: false)
    }

    private func request(ducked: Bool) {
        lock.lock()
        let retriesFailedRestore = !ducked && hasPendingRestoration && !workerScheduled
        guard wantsDucked != ducked || retriesFailedRestore else {
            lock.unlock()
            return
        }
        wantsDucked = ducked
        generation += 1
        let shouldSchedule = !workerScheduled
        workerScheduled = true
        lock.unlock()

        if shouldSchedule {
            schedule { [self] in reconcile() }
        }
    }

    private func reconcile() {
        while true {
            let request = currentRequest()
            if request.ducked {
                let addedRestoration = performDuck()
                restoration = restoration?.merging(addedRestoration) ?? addedRestoration
            } else if let restoration {
                self.restoration = performRestore(restoration)
            }

            lock.lock()
            hasPendingRestoration = restoration != nil
            let settled = generation == request.generation
            if settled {
                workerScheduled = false
            }
            lock.unlock()
            if settled { return }
        }
    }

    private func currentRequest() -> (generation: Int, ducked: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (generation, wantsDucked)
    }

    private func performDuck() -> Restoration {
        var pausedPlayers: [String] = []
        for player in players where effects.isPlayerPlaying(player) == true {
            if effects.pausePlayer(player) {
                pausedPlayers.append(player)
            }
        }

        let shouldMute = effects.isOutputMuted() == false
        let didMute = shouldMute && effects.setOutputMuted(true)
        return Restoration(players: pausedPlayers, unmuteOutput: didMute)
    }

    private func performRestore(_ restoration: Restoration) -> Restoration? {
        let outputStillMuted = restoration.unmuteOutput && !effects.setOutputMuted(false)
        var playersStillPaused: [String] = []
        for player in restoration.players where !effects.playPlayer(player) {
            playersStillPaused.append(player)
        }
        if outputStillMuted || !playersStillPaused.isEmpty {
            return Restoration(
                players: playersStillPaused,
                unmuteOutput: outputStillMuted
            )
        }
        return nil
    }
}
