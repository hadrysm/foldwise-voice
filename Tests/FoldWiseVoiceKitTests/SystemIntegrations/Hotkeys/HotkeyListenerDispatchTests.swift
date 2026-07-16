// The press/release/toggle state machine behind the hotkey. Event is the seam
// where both event sources (CGEventTap and NSEvent monitors) converge, so the
// edge-triggering, repeat, and modifier logic is testable without an event tap
// or Input Monitoring grant.

import CoreGraphics
import XCTest
@testable import FoldWiseVoiceKit

final class HotkeyDispatcherTests: XCTestCase {
    private enum Callback: Equatable { case press, release, toggle, cycle }

    private var fired: [Callback] = []

    private func makeDispatcher(
        ptt: String,
        toggle: String? = nil,
        cycle: String? = nil,
        isSuspended: @escaping () -> Bool = { false }
    ) throws -> HotkeyDispatcher {
        try HotkeyDispatcher(
            pttKey: ptt, toggleKey: toggle, cycleKey: cycle,
            isSuspended: isSuspended,
            onPress: { self.fired.append(.press) },
            onRelease: { self.fired.append(.release) },
            onToggle: { self.fired.append(.toggle) },
            onCycle: { self.fired.append(.cycle) }
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

    func testToggleAndCycleIgnoreDuplicateDownAndRearmOnKeyUp() throws {
        let dispatcher = try makeDispatcher(ptt: "f19", toggle: "f13", cycle: "f14")
        dispatcher.process(key(105, down: true))
        dispatcher.process(key(105, down: true))
        dispatcher.process(key(105, down: false))
        dispatcher.process(key(105, down: true))
        dispatcher.process(key(107, down: true))
        dispatcher.process(key(107, down: true, isRepeat: true))
        dispatcher.process(key(107, down: false))
        dispatcher.process(key(107, down: true))

        XCTAssertEqual(fired, [.toggle, .toggle, .cycle, .cycle])
    }

    func testCaptureSuspendsEveryCommandWithoutExecutingCapturedEvent() throws {
        var suspended = true
        let dispatcher = try makeDispatcher(
            ptt: "f19", toggle: "f13", cycle: "f14",
            isSuspended: { suspended }
        )
        dispatcher.process(key(80, down: true))
        dispatcher.process(key(105, down: true))
        dispatcher.process(key(107, down: true))
        suspended = false
        dispatcher.process(key(80, down: false))
        dispatcher.process(key(105, down: false))
        dispatcher.process(key(107, down: false))
        dispatcher.process(key(107, down: true))

        XCTAssertEqual(fired, [.cycle])
    }

    func testCaptureSuspensionReleasesAnActivePushToTalkHold() throws {
        var suspended = false
        let dispatcher = try makeDispatcher(
            ptt: "f19",
            isSuspended: { suspended }
        )

        dispatcher.process(key(80, down: true))
        suspended = true
        dispatcher.process(key(80, down: false))
        suspended = false
        dispatcher.process(key(80, down: true))
        dispatcher.process(key(80, down: false))

        XCTAssertEqual(fired, [.press, .release, .press, .release])
    }

    func testRuntimeCollisionDispatchesOnlyHighestPriorityCommand() throws {
        let dispatcher = try makeDispatcher(ptt: "f13", toggle: "F13", cycle: " f13 ")
        dispatcher.process(key(105, down: true))
        dispatcher.process(key(105, down: false))

        XCTAssertEqual(fired, [.press, .release])
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

    func testModifierOnlyCycleIgnoresDuplicateDownAndRearmsOnRelease() throws {
        let dispatcher = try makeDispatcher(ptt: "alt_r", cycle: "shift_r")
        let shiftRDown = CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | 0x0004)

        dispatcher.process(.flagsChanged(keycode: 60, flags: shiftRDown))
        dispatcher.process(.flagsChanged(keycode: 60, flags: shiftRDown))
        dispatcher.process(.flagsChanged(keycode: 60, flags: []))
        dispatcher.process(.flagsChanged(keycode: 60, flags: shiftRDown))

        XCTAssertEqual(fired, [.cycle, .cycle])
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

@MainActor
final class HotkeyListenerConfigurationTests: XCTestCase {
    func testValidKeysAreAcceptedWithoutStartingTheListener() throws {
        _ = try HotkeyListener(
            pttKey: "alt_r",
            toggleKey: "f19",
            cycleKey: "esc",
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

    func testUnknownModeCycleKeyIsRejectedBeforeStartingTheListener() {
        XCTAssertThrowsError(try HotkeyListener(
            pttKey: "alt_r",
            toggleKey: nil,
            cycleKey: "unknown",
            onPress: {},
            onRelease: {},
            onToggle: {}
        ))
    }
}

@MainActor
final class HotkeyListenerHealthCoordinatorTests: XCTestCase {
    func testPermissionGrantAndRevocationTransitionWithoutRestartingCoordinator() {
        var permissionGranted = false
        var globalHealthy = false
        var events: [String] = []
        let coordinator = HotkeyListenerHealthCoordinator(
            acquireGlobal: {
                events.append("acquire global")
                globalHealthy = permissionGranted
                return permissionGranted
            },
            isGlobalHealthy: { globalHealthy },
            releaseGlobal: {
                events.append("release global")
                globalHealthy = false
            },
            installFocusedAppOnly: { events.append("install focused") },
            removeFocusedAppOnly: { events.append("remove focused") },
            onHealthChange: { events.append("health \($0)") }
        )

        XCTAssertEqual(coordinator.start(), .becameFocusedAppOnly)
        permissionGranted = true
        XCTAssertEqual(coordinator.check(), .becameGlobal)
        globalHealthy = false
        XCTAssertEqual(coordinator.check(), .becameFocusedAppOnly)
        XCTAssertEqual(coordinator.check(), .becameGlobal)

        XCTAssertEqual(
            events,
            [
                "acquire global", "install focused", "health focusedAppOnly",
                "acquire global", "remove focused", "health global",
                "release global", "install focused", "health focusedAppOnly",
                "acquire global", "remove focused", "health global",
            ]
        )
    }

    func testHealthyGlobalListenerNeedsNoTransition() {
        var healthChanges: [ShortcutListenerHealth] = []
        let coordinator = HotkeyListenerHealthCoordinator(
            acquireGlobal: { true },
            isGlobalHealthy: { true },
            releaseGlobal: {},
            installFocusedAppOnly: {},
            removeFocusedAppOnly: {},
            onHealthChange: { healthChanges.append($0) }
        )

        XCTAssertEqual(coordinator.start(), .becameGlobal)
        XCTAssertEqual(coordinator.check(), .unchanged)
        coordinator.stop()

        XCTAssertEqual(healthChanges, [.global])
    }
}
