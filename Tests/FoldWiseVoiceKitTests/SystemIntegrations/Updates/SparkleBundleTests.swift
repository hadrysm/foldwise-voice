import Foundation
import XCTest

final class SparkleBundleTests: XCTestCase {
    private struct Fixture {
        let repository: URL
        let root: URL
        let production: URL
        let development: URL
    }

    private var fixture: Fixture?

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_SPARKLE_BUNDLE_TESTS"] == "1",
            "Release-bundle verification runs in its dedicated CI job"
        )

        let repository = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("foldwise-sparkle-bundle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let production = root.appendingPathComponent("FoldWise Voice.app")
        let development = root.appendingPathComponent("FoldWise Voice Native.app")
        fixture = Fixture(
            repository: repository,
            root: root,
            production: production,
            development: development
        )
        try FileManager.default.copyItem(
            at: repository.appendingPathComponent("dist/bundle/FoldWise Voice.app"),
            to: production
        )
        try FileManager.default.copyItem(
            at: repository.appendingPathComponent(
                "dist/development-bundle/FoldWise Voice Native.app"
            ),
            to: development
        )
    }

    override func tearDownWithError() throws {
        if let fixture {
            try FileManager.default.removeItem(at: fixture.root)
        }
        fixture = nil
        try super.tearDownWithError()
    }

    func testEmbeddedFrameworkContainsRequiredHelpersWithoutXPCServices() throws {
        let fixture = try XCTUnwrap(fixture)
        let framework = fixture.production.appendingPathComponent(
            "Contents/Frameworks/Sparkle.framework"
        )

        var violations: [String] = []
        require(framework.appendingPathComponent("Versions/B/Autoupdate"), in: &violations)
        require(
            framework.appendingPathComponent("Versions/B/Updater.app/Contents/MacOS/Updater"),
            in: &violations
        )
        reject(framework.appendingPathComponent("Versions/B/XPCServices"), in: &violations)
        reject(framework.appendingPathComponent("XPCServices"), in: &violations)
        requireSymlink(framework.appendingPathComponent("Versions/Current"), in: &violations)
        requireSymlink(framework.appendingPathComponent("Sparkle"), in: &violations)
        requireSymlink(framework.appendingPathComponent("Autoupdate"), in: &violations)
        requireSymlink(framework.appendingPathComponent("Updater.app"), in: &violations)

        XCTAssertEqual(violations, [])
    }

    func testProductionInfoDictionaryEnforcesUpdatePolicy() throws {
        let fixture = try XCTUnwrap(fixture)
        let productionInfo = try infoDictionary(for: fixture.production)

        var violations: [String] = []
        expect(
            productionInfo["SUFeedURL"] as? String,
            "https://updates.guarcode.com/appcast.xml",
            key: "SUFeedURL",
            violations: &violations
        )
        expect(
            productionInfo["SUPublicEDKey"] as? String,
            "SlFqUaKJUBpdIqg+oWEI7b2j1pCLSecVuwzp5O/PRWc=",
            key: "SUPublicEDKey",
            violations: &violations
        )
        expect(productionInfo["SURequireSignedFeed"] as? Bool, true,
               key: "SURequireSignedFeed", violations: &violations)
        expect(productionInfo["SUVerifyUpdateBeforeExtraction"] as? Bool, true,
               key: "SUVerifyUpdateBeforeExtraction", violations: &violations)
        expect(productionInfo["SUEnableAutomaticChecks"] as? Bool, true,
               key: "SUEnableAutomaticChecks", violations: &violations)
        expect(productionInfo["SUAutomaticallyUpdate"] as? Bool, true,
               key: "SUAutomaticallyUpdate", violations: &violations)
        expect(productionInfo["SUScheduledCheckInterval"] as? Int, 86400,
               key: "SUScheduledCheckInterval", violations: &violations)
        expect(productionInfo["LSMinimumSystemVersion"] as? String, "14.0.0",
               key: "LSMinimumSystemVersion", violations: &violations)
        expect(
            productionInfo["CFBundleShortVersionString"] as? String,
            productionInfo["CFBundleVersion"] as? String,
            key: "equal release/build versions",
            violations: &violations
        )
        rejectKey("SUEnableInstallerLauncherService", from: productionInfo, in: &violations)
        rejectKey("SUEnableDownloaderService", from: productionInfo, in: &violations)

        XCTAssertEqual(violations, [])
    }

    func testDevelopmentInfoDictionaryCannotUseProductionUpdater() throws {
        let fixture = try XCTUnwrap(fixture)
        let developmentInfo = try infoDictionary(for: fixture.development)

        var violations: [String] = []
        rejectKey("SUFeedURL", from: developmentInfo, in: &violations)
        rejectKey("SUPublicEDKey", from: developmentInfo, in: &violations)

        XCTAssertEqual(violations, [])
    }

    func testExecutableResolvesEmbeddedSparkleFramework() throws {
        let fixture = try XCTUnwrap(fixture)
        let executable = fixture.production.appendingPathComponent(
            "Contents/MacOS/FoldWiseVoice"
        )

        var violations: [String] = []
        let linkedLibraries = try output(
            "/usr/bin/otool", ["-L", executable.path], in: fixture.repository
        )
        if !linkedLibraries.contains("@rpath/Sparkle.framework/Versions/B/Sparkle") {
            violations.append("FoldWiseVoice does not link Sparkle through @rpath")
        }
        let loadCommands = try output(
            "/usr/bin/otool", ["-l", executable.path], in: fixture.repository
        )
        if !loadCommands.contains("@loader_path/../Frameworks") {
            violations.append("FoldWiseVoice is missing the packaged framework runpath")
        }

        XCTAssertEqual(violations, [])
    }

    func testProductionBundleHasStrictSignature() throws {
        let fixture = try XCTUnwrap(fixture)
        var violations: [String] = []
        try verifySignature(
            of: fixture.production,
            in: fixture.repository,
            violations: &violations
        )

        XCTAssertEqual(violations, [])
    }

    func testDevelopmentBundleHasStrictSignature() throws {
        let fixture = try XCTUnwrap(fixture)
        var violations: [String] = []
        try verifySignature(
            of: fixture.development,
            in: fixture.repository,
            violations: &violations
        )

        XCTAssertEqual(violations, [])
    }

    private func infoDictionary(for app: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        )
    }

    private func require(_ url: URL, in violations: inout [String]) {
        if !FileManager.default.fileExists(atPath: url.path) {
            violations.append("Missing \(url.path)")
        }
    }

    private func reject(_ url: URL, in violations: inout [String]) {
        if FileManager.default.fileExists(atPath: url.path)
            || (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            violations.append("Unexpected \(url.path)")
        }
    }

    private func requireSymlink(_ url: URL, in violations: inout [String]) {
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true {
            violations.append("Expected symlink at \(url.path)")
        }
    }

    private func expect<T: Equatable>(
        _ actual: T?,
        _ expected: T?,
        key: String,
        violations: inout [String]
    ) {
        if actual != expected {
            violations.append("\(key) was \(String(describing: actual))")
        }
    }

    private func rejectKey(
        _ key: String,
        from dictionary: [String: Any],
        in violations: inout [String]
    ) {
        if dictionary[key] != nil {
            violations.append("\(key) must be absent")
        }
    }

    private func verifySignature(
        of app: URL,
        in repository: URL,
        violations: inout [String]
    ) throws {
        let result = try process(
            "/usr/bin/codesign",
            ["--verify", "--deep", "--strict", "--verbose=2", app.path],
            in: repository
        )
        if result.status != 0 {
            violations.append(
                "Strict signature verification failed for \(app.lastPathComponent): "
                    + result.output
            )
        }
    }

    private func output(
        _ executable: String,
        _ arguments: [String],
        in directory: URL
    ) throws -> String {
        let result = try process(executable, arguments, in: directory)
        guard result.status == 0 else {
            throw NSError(
                domain: "SparkleBundleTests",
                code: Int(result.status),
                userInfo: [NSLocalizedDescriptionKey: result.output]
            )
        }
        return result.output
    }

    private func process(
        _ executable: String,
        _ arguments: [String],
        in directory: URL
    ) throws -> (status: Int32, output: String) {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("foldwise-bundle-test-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        defer {
            try? log.close()
            try? FileManager.default.removeItem(at: logURL)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = log
        process.standardError = log
        try process.run()
        process.waitUntilExit()
        try log.synchronize()
        let data = try Data(contentsOf: logURL)
        return (
            process.terminationStatus,
            String(bytes: data, encoding: .utf8) ?? ""
        )
    }
}
