// Thin system-command adapter for audio ducking. Coordination and restoration
// decisions live in AudioDuckCoordinator; this shell only executes AppleScript.

import Darwin
import Foundation
import os

enum BoundedProcess {
    struct Outcome: Equatable {
        let status: Int32
        let output: Data
        let timedOut: Bool
    }

    private final class TimeoutState: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        func mark() {
            lock.withLock { value = true }
        }

        var occurred: Bool {
            lock.withLock { value }
        }
    }

    static func run(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> Outcome {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()

        let timeoutState = TimeoutState()
        let forceKill = DispatchWorkItem {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        let terminate = DispatchWorkItem {
            guard process.isRunning else { return }
            timeoutState.mark()
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1, execute: forceKill)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: terminate)

        // Drain while the child is running so a full pipe cannot block its exit.
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        terminate.cancel()
        forceKill.cancel()
        return Outcome(
            status: process.terminationStatus,
            output: output,
            timedOut: timeoutState.occurred
        )
    }
}

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
        let result: BoundedProcess.Outcome
        do {
            result = try BoundedProcess.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
                arguments: ["-e", script],
                timeout: 5
            )
        } catch {
            Log.audio.error(
                "Audio duck command could not launch; skipped \(operation, privacy: .public)"
            )
            return (false, "")
        }
        let output = String(data: result.output, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !result.timedOut else {
            Log.audio.error(
                "Audio duck command timed out; skipped \(operation, privacy: .public)"
            )
            return (false, output)
        }
        guard result.status == 0 else {
            Log.audio.error(
                "Audio duck command failed; skipped \(operation, privacy: .public)"
            )
            return (false, output)
        }
        return (true, output)
    }
}
