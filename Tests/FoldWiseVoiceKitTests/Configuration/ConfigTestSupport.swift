import XCTest
@testable import FoldWiseVoiceKit

enum ExpectedConfigError {
    case invalid
    case readOnlyRecovery
}

extension XCTestCase {
    func assertThrowsConfigError(
        _ expected: ExpectedConfigError,
        _ expression: @autoclosure () throws -> some Any,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            switch (expected, error) {
            case (.invalid, ConfigError.invalid):
                break
            case (.readOnlyRecovery, ConfigError.readOnlyRecovery):
                break
            default:
                XCTFail("Unexpected error: \(error)", file: file, line: line)
            }
        }
    }
}
