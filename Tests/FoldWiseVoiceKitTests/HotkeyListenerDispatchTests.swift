// The press/release/toggle state machine behind the hotkey. Event is the seam
// where both event sources (CGEventTap and NSEvent monitors) converge, so the
// edge-triggering, repeat, and modifier logic is testable without an event tap
// or Input Monitoring grant.

import CoreGraphics
import XCTest
@testable import FoldWiseVoiceKit

final class HotkeyDispatcherTests: XCTestCase {
    private enum Callback: Equatable { case press, release, toggle }

    private var fired: [Callback] = []

    private func makeDispatcher(ptt: String, toggle: String? = nil) throws -> HotkeyDispatcher {
        try HotkeyDispatcher(
            pttKey: ptt, toggleKey: toggle,
            onPress: { self.fired.append(.press) },
            onRelease: { self.fired.append(.release) },
            onToggle: { self.fired.append(.toggle) }
        )
    }

    private func key(_ keycode: CGKeyCode, down: Bool, isRepeat: Bool = false) -> HotkeyDispatcher.Event {
        .key(keycode: keycode, character: nil, down: down, isRepeat: isRepeat)
    }

    func testHoldAndReleaseFiresPressThenRelease() throws {
        let dispatcher = try makeDispatcher(ptt: "f19") // keycode 80
        dispatcher.process(key(80, down: true))
        dispatcher.process(key(80, down: false))
        XCTAssertEqual(fired, [.press, .release])
    }

    func testAutorepeatWhileHeldFiresPressOnce() throws {
        let dispatcher = try makeDispatcher(ptt: "f19")
        dispatcher.process(key(80, down: true))
        dispatcher.process(key(80, down: true, isRepeat: true))
        dispatcher.process(key(80, down: true, isRepeat: true))
        dispatcher.process(key(80, down: false))
        XCTAssertEqual(fired, [.press, .release])
    }

    func testDuplicateDownIsEdgeTriggered() throws {
        let dispatcher = try makeDispatcher(ptt: "f19")
        dispatcher.process(key(80, down: true))
        dispatcher.process(key(80, down: true))
        XCTAssertEqual(fired, [.press])
    }

    func testReleaseWithoutPriorPressFiresNothing() throws {
        let dispatcher = try makeDispatcher(ptt: "f19")
        dispatcher.process(key(80, down: false))
        XCTAssertEqual(fired, [])
    }

    func testUnrelatedKeyFiresNothing() throws {
        let dispatcher = try makeDispatcher(ptt: "f19")
        dispatcher.process(key(49, down: true)) // space
        dispatcher.process(key(49, down: false))
        XCTAssertEqual(fired, [])
    }

    func testToggleFiresOnKeyDownOnly() throws {
        let dispatcher = try makeDispatcher(ptt: "f19", toggle: "f13") // f13 = 105
        dispatcher.process(key(105, down: true))
        dispatcher.process(key(105, down: false))
        XCTAssertEqual(fired, [.toggle])
    }

    func testModifierPttHoldAndReleaseViaFlagsChanged() throws {
        // alt_r (keycode 61) — the production default. Down carries the
        // generic mask plus the key's own device bit; release clears both.
        let dispatcher = try makeDispatcher(ptt: "alt_r")
        let altRDown = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x0040)
        dispatcher.process(.flagsChanged(keycode: 61, flags: altRDown))
        dispatcher.process(.flagsChanged(keycode: 61, flags: []))
        XCTAssertEqual(fired, [.press, .release])
    }

    func testModifierPttIgnoresSiblingKeyRelease() throws {
        // Right ⌥ released while left ⌥ is still held must count as a
        // release for an alt_r hotkey (device bits disambiguate the pair).
        let dispatcher = try makeDispatcher(ptt: "alt_r")
        let bothDown = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x0040 | 0x0020)
        let leftStillHeld = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x0020)
        dispatcher.process(.flagsChanged(keycode: 61, flags: bothDown))
        dispatcher.process(.flagsChanged(keycode: 61, flags: leftStillHeld))
        XCTAssertEqual(fired, [.press, .release])
    }

    func testCharacterSpecMatchesByTypedCharacterNotKeycode() throws {
        // A single-character hotkey matches whatever key produces that
        // character, regardless of keycode.
        let dispatcher = try makeDispatcher(ptt: "j")
        dispatcher.process(.key(keycode: 38, character: "j", down: true, isRepeat: false))
        dispatcher.process(.key(keycode: 38, character: "j", down: false, isRepeat: false))
        dispatcher.process(.key(keycode: 40, character: "k", down: true, isRepeat: false))
        XCTAssertEqual(fired, [.press, .release])
    }
}

final class HotkeyListenerConfigurationTests: XCTestCase {
    func testValidKeysAreAcceptedWithoutStartingTheListener() throws {
        _ = try HotkeyListener(
            pttKey: "alt_r",
            toggleKey: "f19",
            onPress: {},
            onRelease: {},
            onToggle: {}
        )
    }

    func testUnknownPushToTalkKeyIsRejectedBeforeStartingTheListener() {
        XCTAssertThrowsError(try HotkeyListener(
            pttKey: "unknown",
            toggleKey: nil,
            onPress: {},
            onRelease: {},
            onToggle: {}
        ))
    }

    func testUnknownToggleKeyIsRejectedBeforeStartingTheListener() {
        XCTAssertThrowsError(try HotkeyListener(
            pttKey: "alt_r",
            toggleKey: "unknown",
            onPress: {},
            onRelease: {},
            onToggle: {}
        ))
    }
}
