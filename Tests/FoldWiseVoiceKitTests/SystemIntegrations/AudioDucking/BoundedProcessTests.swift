import Foundation
import XCTest
@testable import FoldWiseVoiceKit

final class BoundedProcessTests: XCTestCase {
    func testDrainsOutputWhileProcessRuns() throws {
        let result = try BoundedProcess.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/head"),
            arguments: ["-c", "131072", "/dev/zero"],
            timeout: 2
        )

        XCTAssertEqual(
            result,
            BoundedProcess.Outcome(
                status: 0,
                output: Data(repeating: 0, count: 131_072),
                timedOut: false
            )
        )
    }

    func testTerminatesProcessAtDeadline() throws {
        let result = try BoundedProcess.run(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["5"],
            timeout: 0.05
        )

        XCTAssertTrue(result.timedOut)
    }
}
