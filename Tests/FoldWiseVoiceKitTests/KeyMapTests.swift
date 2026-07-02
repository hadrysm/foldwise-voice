// KeyMap: pynput-compatible key names ↔ macOS virtual keycodes. modes.json
// written by either app must parse identically in both.

import XCTest

@testable import FoldWiseVoiceKit

final class KeyMapTests: XCTestCase {
    func testParseKnownKeyName() throws {
        guard case .keycode(let code) = try KeyMap.parse("alt_r") else {
            return XCTFail("alt_r should parse as a keycode")
        }
        XCTAssertEqual(code, 61)
    }

    func testParseIsCaseAndWhitespaceInsensitive() throws {
        guard case .keycode(let code) = try KeyMap.parse("  ALT_R ") else {
            return XCTFail("' ALT_R ' should parse as a keycode")
        }
        XCTAssertEqual(code, 61)
    }

    func testParseSingleCharacterLowercases() throws {
        guard case .character(let ch) = try KeyMap.parse("A") else {
            return XCTFail("'A' should parse as a character key")
        }
        XCTAssertEqual(ch, "a")
    }

    func testParseUnknownNameThrows() {
        XCTAssertThrowsError(try KeyMap.parse("not_a_key"))
        XCTAssertThrowsError(try KeyMap.parse(""))
    }

    func testCodeToNamePrefersSpecificOverGenericName() {
        // "alt" and "alt_l" share keycode 58; the reverse map must pick the
        // specific left/right name so the settings recorder shows "alt_l".
        XCTAssertEqual(KeyMap.codeToName[58], "alt_l")
        XCTAssertEqual(KeyMap.codeToName[55], "cmd_l")
        XCTAssertEqual(KeyMap.codeToName[59], "ctrl_l")
        XCTAssertEqual(KeyMap.codeToName[56], "shift_l")
    }

    func testReverseMapRoundTripsToSameKeycode() {
        for (code, name) in KeyMap.codeToName {
            XCTAssertEqual(
                KeyMap.nameToCode[name], code,
                "codeToName[\(code)] = \(name) does not map back to \(code)")
        }
    }

    func testPrettyNamesForModifiersAndPassthrough() {
        XCTAssertEqual(KeyMap.pretty("alt_r"), "right ⌥")
        XCTAssertEqual(KeyMap.pretty("cmd_l"), "left ⌘")
        XCTAssertEqual(KeyMap.pretty("f19"), "f19")
    }
}
