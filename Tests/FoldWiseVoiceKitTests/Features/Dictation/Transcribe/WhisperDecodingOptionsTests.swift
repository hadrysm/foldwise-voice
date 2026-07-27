import XCTest
@testable import FoldWiseVoiceKit

final class WhisperDecodingOptionsTests: XCTestCase {
    func testDecodingOptionsTranscribeInTheDetectedSourceLanguage() {
        let options = WhisperTranscriber.decodingOptions

        XCTAssertEqual(options.task, .transcribe)
        XCTAssertNil(options.language)
        XCTAssertTrue(options.usePrefillPrompt)
        XCTAssertTrue(options.detectLanguage)
    }
}
