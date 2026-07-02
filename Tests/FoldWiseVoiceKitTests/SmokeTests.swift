import XCTest
@testable import FoldWiseVoiceKit

final class SmokeTests: XCTestCase {
    func testDefaultConfigHasModes() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("foldwise-smoke-modes.json")
        let config = Config.defaultConfig(path: tmp)
        XCTAssertFalse(config.modeOrder.isEmpty)
    }
}
