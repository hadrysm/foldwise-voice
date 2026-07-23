import XCTest
@testable import FoldWiseVoiceKit

final class DictationCommandQueueTests: XCTestCase {
    func testSubmittingStartReturnsWhileCaptureStartupIsBlocked() {
        let captureStartupEntered = expectation(description: "capture startup entered")
        let submissionReturned = expectation(description: "submission returned")
        let releaseCaptureStartup = DispatchSemaphore(value: 0)
        let commands = DictationCommandQueue(
            start: {
                captureStartupEntered.fulfill()
                releaseCaptureStartup.wait()
            },
            stop: {},
            toggle: {}
        )

        DispatchQueue.global().async {
            commands.start()
            submissionReturned.fulfill()
        }

        wait(for: [captureStartupEntered, submissionReturned], timeout: 0.2)
        releaseCaptureStartup.signal()
    }

    func testCommandsRunInSubmissionOrder() {
        let completed = expectation(description: "commands completed")
        let lock = NSLock()
        var events: [String] = []
        let append: (String) -> Void = { event in
            lock.lock()
            events.append(event)
            lock.unlock()
        }
        let commands = DictationCommandQueue(
            start: { append("start") },
            stop: { append("stop") },
            toggle: {
                append("toggle")
                completed.fulfill()
            }
        )

        commands.start()
        commands.stop()
        commands.toggle()
        wait(for: [completed], timeout: 0.2)

        XCTAssertEqual(events, ["start", "stop", "toggle"])
    }
}
