import AppKit
import XCTest
@testable import FoldWiseVoiceKit

final class ApplicationRunLoopTests: XCTestCase {
    @MainActor
    func testHandlerCompletesDeferredTerminationWhileModalPanelModeIsRunning() {
        var events: [String] = []
        let coordinator = DictationLifecycleCoordinator {
            events.append("tear down")
        }
        let sessionID = UUID()
        coordinator.sessionDidChange(.started(sessionID))
        _ = coordinator.applicationShouldTerminate {
            events.append("reply")
        }
        let handleSessionEvent = ApplicationRunLoop.handler {
            coordinator.sessionDidChange($0)
            CFRunLoopStop(CFRunLoopGetMain())
        }
        let didSchedule = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            handleSessionEvent(.finished(sessionID))
            didSchedule.signal()
        }
        XCTAssertEqual(didSchedule.wait(timeout: .now() + 1), .success)

        _ = RunLoop.main.run(
            mode: .modalPanel,
            before: Date(timeIntervalSinceNow: 1)
        )

        XCTAssertEqual(events, ["tear down", "reply"])
    }

    @MainActor
    func testSignalCompletesPipelineWhileDeferredTerminationModeIsRunning() throws {
        var events: [String] = []
        var didStart = false
        let coordinator = DictationLifecycleCoordinator {
            events.append("tear down")
        }
        let signalConsumed = DispatchSemaphore(value: 0)
        let gateOpened = DispatchSemaphore(value: 0)
        let insertionStarted = DispatchSemaphore(value: 0)
        let finishInsertion = UpdateRuntimeAcceptanceInsertionGate()
        let transcriber = FakeTranscriber()
        transcriber.result = .success("hello world")
        let pipeline = Pipeline(
            config: makeTestConfig(),
            recorder: FakeRecorder(),
            sessionProvider: FakeTranscriberSessionProvider(transcriber),
            insert: finishInsertion.insert,
            record: { _ in },
            frontmostApp: { nil }
        )
        pipeline.onSessionEvent = ApplicationRunLoop.handler { event in
            coordinator.sessionDidChange(event)
            if case .started = event {
                didStart = true
            }
        }

        pipeline.startRecording()
        let startDeadline = Date(timeIntervalSinceNow: 1)
        while !didStart, Date() < startDeadline {
            _ = RunLoop.main.run(mode: .default, before: startDeadline)
        }
        XCTAssertTrue(didStart)
        pipeline.stopRecording()
        let insertionObserver = Task.detached {
            while !Task.isCancelled, !(await finishInsertion.isWaiting()) {
                await Task.yield()
            }
            guard !Task.isCancelled else { return }
            insertionStarted.signal()
        }
        defer { insertionObserver.cancel() }
        let insertionDeadline = Date(timeIntervalSinceNow: 1)
        var didReachInsertion = false
        while !didReachInsertion, Date() < insertionDeadline {
            didReachInsertion = insertionStarted.wait(timeout: .now()) == .success
            _ = RunLoop.main.run(
                mode: .default,
                before: Date(timeIntervalSinceNow: 0.01)
            )
        }
        XCTAssertTrue(didReachInsertion)
        XCTAssertEqual(
            coordinator.applicationShouldTerminate {
                events.append("reply")
            },
            .terminateLater
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let monitor = UpdateRuntimeAcceptanceSignalMonitor(
            directory: directory,
            signalName: "finish-dictation"
        ) {
            signalConsumed.signal()
            Task {
                await finishInsertion.open()
                gateOpened.signal()
            }
        }
        monitor.start()
        defer {
            monitor.stop()
        }
        try Data("requested\n".utf8).write(
            to: directory.appendingPathComponent("finish-dictation")
        )

        let deadline = Date(timeIntervalSinceNow: 2)
        while events.isEmpty, Date() < deadline {
            _ = RunLoop.main.run(
                mode: .modalPanel,
                before: Date(timeIntervalSinceNow: 0.01)
            )
        }

        XCTAssertEqual(signalConsumed.wait(timeout: .now()), .success)
        XCTAssertEqual(gateOpened.wait(timeout: .now()), .success)
        XCTAssertEqual(events, ["tear down", "reply"])
    }
}
