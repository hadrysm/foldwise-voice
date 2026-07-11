// Thin system-command adapter for audio ducking. Coordination and restoration
// decisions live in AudioDuckCoordinator; this shell only executes AppleScript.

import Foundation
import os

final class AudioDucker: AudioDucking {
    private let queue = DispatchQueue(label: "ducker", qos: .userInitiated)
    private let coordinator: AudioDuckCoordinator

    init() {
        let queue = queue
        coordinator = AudioDuckCoordinator(
            effects: AppleScriptAudioDuckSystemEffects(),
            schedule: { work in queue.async(execute: work) }
        )
    }

    func duck() {
        coordinator.duck()
    }

    func restore() {
        coordinator.restore()
    }
}

private final class AppleScriptAudioDuckSystemEffects: AudioDuckSystemEffects {
    func isPlayerPlaying(_ player: String) -> Bool? {
        let result = run(
            "if application \"\(player)\" is running then "
                + "tell application \"\(player)\" to get player state as text",
            operation: "read \(player) playback state"
        )
        return result.succeeded ? result.output == "playing" : nil
    }

    func pausePlayer(_ player: String) -> Bool {
        run(
            "tell application \"\(player)\" to pause",
            operation: "pause \(player)"
        ).succeeded
    }

    func playPlayer(_ player: String) -> Bool {
        run(
            "tell application \"\(player)\" to play",
            operation: "resume \(player)"
        ).succeeded
    }

    func isOutputMuted() -> Bool? {
        let result = run(
            "output muted of (get volume settings)",
            operation: "read output mute state"
        )
        return result.succeeded ? result.output == "true" : nil
    }

    func setOutputMuted(_ muted: Bool) -> Bool {
        let muteModifier = muted ? "with" : "without"
        return run(
            "set volume \(muteModifier) output muted",
            operation: muted ? "mute output" : "unmute output"
        ).succeeded
    }

    private func run(
        _ script: String,
        operation: String
    ) -> (succeeded: Bool, output: String) {
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
            Log.audio.error(
                "Audio duck command could not launch; skipped \(operation, privacy: .public)"
            )
            return (false, "")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            Log.audio.error(
                "Audio duck command failed; skipped \(operation, privacy: .public)"
            )
            return (false, output)
        }
        return (true, output)
    }
}
