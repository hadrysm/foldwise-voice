// Silence other apps while dictating: pause Spotify / Apple Music if they
// are playing (remembered), then mute system output. Restore resumes only
// the players we paused. osascript calls take ~100 ms each, so everything
// runs on a serial background queue; a generation counter makes a quick
// duck→restore→duck sequence settle on the latest call.

import Foundation

final class AudioDucker {
    private static let players = ["Spotify", "Music"]

    private let queue = DispatchQueue(label: "ducker", qos: .userInitiated)
    private let lock = NSLock()
    private var generation = 0
    private var ducked = false
    private var pausedPlayers: [String] = []
    private var wasMuted = false

    func duck() {
        schedule { self.performDuck($0) }
    }

    func restore() {
        schedule { self.performRestore($0) }
    }

    private func schedule(_ work: @escaping (Int) -> Void) {
        lock.lock()
        generation += 1
        let gen = generation
        lock.unlock()
        queue.async { work(gen) }
    }

    private func isCurrent(_ gen: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return gen == generation
    }

    private func performDuck(_ gen: Int) {
        guard isCurrent(gen), !ducked else { return }
        ducked = true
        pausedPlayers = []
        for app in Self.players {
            let state = osascript(
                "if application \"\(app)\" is running then "
                    + "tell application \"\(app)\" to get player state as text")
            if state == "playing" {
                _ = osascript("tell application \"\(app)\" to pause")
                pausedPlayers.append(app)
            }
        }
        wasMuted = osascript("output muted of (get volume settings)") == "true"
        if !wasMuted {
            _ = osascript("set volume with output muted")
        }
    }

    private func performRestore(_ gen: Int) {
        guard isCurrent(gen), ducked else { return }
        ducked = false
        if !wasMuted {
            _ = osascript("set volume without output muted")
        }
        for app in pausedPlayers {
            _ = osascript("tell application \"\(app)\" to play")
        }
        pausedPlayers = []
    }

    private func osascript(_ script: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
