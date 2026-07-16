import Foundation
import os

final class FoldWiseVoiceCommandLine {
    struct Termination: Equatable {
        let status: Int32
        let standardOutput: String
        let standardError: String
    }

    enum Action: Equatable {
        case launch(configPath: String?)
        case terminate(Termination)
    }

    private let temporaryDirectory: URL
    private let serializeConfig: (Config, URL) throws -> String
    private let removeTemporaryItem: (URL) throws -> Void
    private let reportCleanupFailure: (String) -> Void

    init(
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        serializeConfig: @escaping (Config, URL) throws -> String = { config, url in
            try config.save(to: url)
            return try String(contentsOf: url, encoding: .utf8)
        },
        removeTemporaryItem: @escaping (URL) throws -> Void = {
            try FileManager.default.removeItem(at: $0)
        },
        reportCleanupFailure: @escaping (String) -> Void = { message in
            Log.config.error("\(message, privacy: .public)")
        }
    ) {
        self.temporaryDirectory = temporaryDirectory
        self.serializeConfig = serializeConfig
        self.removeTemporaryItem = removeTemporaryItem
        self.reportCleanupFailure = reportCleanupFailure
    }

    func evaluate(arguments: [String]) -> Action {
        switch parse(arguments: arguments) {
        case let .launch(configPath):
            .launch(configPath: configPath)
        case let .printConfig(configPath):
            printConfig(at: Config.resolvePath(cliPath: configPath))
        case let .failure(message):
            failure(message)
        }
    }

    private func parse(arguments: [String]) -> ParsedCommand {
        var cliConfig: String?
        var printConfig = false
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--config":
                cliConfig = iterator.next()
            case "--print-config":
                printConfig = true
            case "--mode":
                return .failure(
                    "--mode is no longer supported; select Modes by stable ID in config.json."
                )
            default:
                continue
            }
        }

        return printConfig ? .printConfig(configPath: cliConfig) : .launch(configPath: cliConfig)
    }

    private func printConfig(at url: URL) -> Action {
        let config = Config.loadOrCreate(at: url)
        if let recovery = config.recovery {
            return failure(
                "Cannot print invalid configuration at \(url.path): \(recovery.message)"
            )
        }

        let temporaryURL = temporaryDirectory.appendingPathComponent(
            "foldwise-config-check-\(UUID().uuidString).json"
        )
        defer { cleanup(temporaryURL) }
        do {
            let serialized = try serializeConfig(config, temporaryURL)
            return .terminate(Termination(
                status: 0,
                standardOutput: "config: \(url.path)\n\(serialized)\n",
                standardError: ""
            ))
        } catch {
            return failure(
                "Could not serialize configuration at \(url.path): \(error.localizedDescription)"
            )
        }
    }

    private func cleanup(_ url: URL) {
        do {
            try removeTemporaryItem(url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        } catch {
            reportCleanupFailure(
                "Could not remove temporary configuration at \(url.path): "
                    + error.localizedDescription
            )
        }
    }

    private func failure(_ message: String) -> Action {
        .terminate(Termination(
            status: 1,
            standardOutput: "",
            standardError: "error: \(message)\n"
        ))
    }

    private enum ParsedCommand {
        case launch(configPath: String?)
        case printConfig(configPath: String?)
        case failure(String)
    }
}
