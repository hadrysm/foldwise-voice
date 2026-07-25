import XCTest
@testable import FoldWiseVoiceKit

final class AcceptanceSignalMonitorTests: XCTestCase {
    @MainActor
    func testSignalIsConsumedWhileMainQueueIsBlocked() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let consumed = DispatchSemaphore(value: 0)
        let monitor = UpdateRuntimeAcceptanceSignalMonitor(
            directory: directory,
            signalName: "finish-dictation"
        ) {
            consumed.signal()
        }
        monitor.start()
        defer {
            monitor.stop()
        }

        let signal = directory.appendingPathComponent("finish-dictation")
        try Data("requested\n".utf8).write(to: signal)
        let result = consumed.wait(timeout: .now() + 1)

        XCTAssertEqual(result, .success)
    }

    func testExistingSignalIsConsumedWhenMonitoringStarts() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let signal = directory.appendingPathComponent("finish-dictation")
        try Data("requested\n".utf8).write(to: signal)
        let consumed = DispatchSemaphore(value: 0)
        let monitor = UpdateRuntimeAcceptanceSignalMonitor(
            directory: directory,
            signalName: "finish-dictation"
        ) {
            consumed.signal()
        }
        monitor.start()
        defer {
            monitor.stop()
        }

        XCTAssertEqual(consumed.wait(timeout: .now() + 1), .success)
    }
}
