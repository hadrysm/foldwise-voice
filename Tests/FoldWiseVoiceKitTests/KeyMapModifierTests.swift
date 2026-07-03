// isModifierDown decodes flagsChanged events using device-specific flag bits,
// so releasing one key of a left/right pair isn't masked by the sibling still
// being held. These bit patterns are the whole reason the code exists.

import CoreGraphics
import XCTest
@testable import FoldWiseVoiceKit

final class KeyMapModifierTests: XCTestCase {
    private let altR: CGKeyCode = 61
    private let altLBit: UInt64 = 0x0020
    private let altRBit: UInt64 = 0x0040

    func testNonModifierKeycodeReturnsNil() {
        XCTAssertNil(KeyMap.isModifierDown(keycode: 49, flags: [])) // space
    }

    func testGenericMaskAbsentMeansUp() {
        XCTAssertEqual(KeyMap.isModifierDown(keycode: altR, flags: []), false)
    }

    func testOwnDeviceBitSetMeansDown() {
        let flags = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | altRBit)
        XCTAssertEqual(KeyMap.isModifierDown(keycode: altR, flags: flags), true)
    }

    func testSiblingOnlyMeansUp() {
        // Right ⌥ released while left ⌥ is still held: the generic mask is
        // still set (left key), but the right key's own device bit is not.
        let flags = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | altLBit)
        XCTAssertEqual(KeyMap.isModifierDown(keycode: altR, flags: flags), false)
    }

    func testSynthesizedEventWithoutDeviceBitsFallsBackToGenericMask() {
        // Synthesized events may omit device bits entirely; the generic mask
        // alone must then count as down.
        XCTAssertEqual(
            KeyMap.isModifierDown(keycode: altR, flags: .maskAlternate), true
        )
    }

    func testCapsLockHasNoDeviceBitsAndUsesGenericMask() {
        XCTAssertEqual(KeyMap.isModifierDown(keycode: 57, flags: .maskAlphaShift), true)
        XCTAssertEqual(KeyMap.isModifierDown(keycode: 57, flags: []), false)
    }
}
