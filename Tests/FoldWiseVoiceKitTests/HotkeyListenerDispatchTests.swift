// The press/release/toggle state machine behind the hotkey. RawKeyEvent is
// the seam where both event sources (CGEventTap and NSEvent monitors)
// converge, so the edge-triggering, repeat, and modifier logic is testable
// without an event tap or Input Monitoring grant.

import CoreGraphics
import XCTest
@testable import FoldWiseVoiceKit

final class HotkeyListenerDispatchTests: XCTestCase {
    private enum Callback: Equatable { case press, release, toggle }

    private var fired: [Callback] = []

    private func makeListener(ptt: String, toggle: String? = nil) throws -> HotkeyListener {
        try HotkeyListener(
            pttKey: ptt, toggleKey: toggle,
            onPress: { self.fired.append(.press) },
            onRelease: { self.fired.append(.release) },
            onToggle: { self.fired.append(.toggle) }
        )
    }

    private func key(_ keycode: CGKeyCode, down: Bool, isRepeat: Bool = false) -> HotkeyListener.RawKeyEvent {
        .key(keycode: keycode, character: nil, down: down, isRepeat: isRepeat)
    }

    func testHoldAndReleaseFiresPressThenRelease() throws {
        let listener = try makeListener(ptt: "f19") // keycode 80
        listener.process(key(80, down: true))
        listener.process(key(80, down: false))
        XCTAssertEqual(fired, [.press, .release])
    }

    func testAutorepeatWhileHeldFiresPressOnce() throws {
        let listener = try makeListener(ptt: "f19")
        listener.process(key(80, down: true))
        listener.process(key(80, down: true, isRepeat: true))
        listener.process(key(80, down: true, isRepeat: true))
        listener.process(key(80, down: false))
        XCTAssertEqual(fired, [.press, .release])
    }

    func testDuplicateDownIsEdgeTriggered() throws {
        let listener = try makeListener(ptt: "f19")
        listener.process(key(80, down: true))
        listener.process(key(80, down: true))
        XCTAssertEqual(fired, [.press])
    }

    func testReleaseWithoutPriorPressFiresNothing() throws {
        let listener = try makeListener(ptt: "f19")
        listener.process(key(80, down: false))
        XCTAssertEqual(fired, [])
    }

    func testUnrelatedKeyFiresNothing() throws {
        let listener = try makeListener(ptt: "f19")
        listener.process(key(49, down: true)) // space
        listener.process(key(49, down: false))
        XCTAssertEqual(fired, [])
    }

    func testToggleFiresOnKeyDownOnly() throws {
        let listener = try makeListener(ptt: "f19", toggle: "f13") // f13 = 105
        listener.process(key(105, down: true))
        listener.process(key(105, down: false))
        XCTAssertEqual(fired, [.toggle])
    }

    func testModifierPttHoldAndReleaseViaFlagsChanged() throws {
        // alt_r (keycode 61) — the production default. Down carries the
        // generic mask plus the key's own device bit; release clears both.
        let listener = try makeListener(ptt: "alt_r")
        let altRDown = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x0040)
        listener.process(.flagsChanged(keycode: 61, flags: altRDown))
        listener.process(.flagsChanged(keycode: 61, flags: []))
        XCTAssertEqual(fired, [.press, .release])
    }

    func testModifierPttIgnoresSiblingKeyRelease() throws {
        // Right ⌥ released while left ⌥ is still held must count as a
        // release for an alt_r hotkey (device bits disambiguate the pair).
        let listener = try makeListener(ptt: "alt_r")
        let bothDown = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x0040 | 0x0020)
        let leftStillHeld = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x0020)
        listener.process(.flagsChanged(keycode: 61, flags: bothDown))
        listener.process(.flagsChanged(keycode: 61, flags: leftStillHeld))
        XCTAssertEqual(fired, [.press, .release])
    }

    func testCharacterSpecMatchesByTypedCharacterNotKeycode() throws {
        // A single-character hotkey matches whatever key produces that
        // character, regardless of keycode.
        let listener = try makeListener(ptt: "j")
        listener.process(.key(keycode: 38, character: "j", down: true, isRepeat: false))
        listener.process(.key(keycode: 38, character: "j", down: false, isRepeat: false))
        listener.process(.key(keycode: 40, character: "k", down: true, isRepeat: false))
        XCTAssertEqual(fired, [.press, .release])
    }
}
