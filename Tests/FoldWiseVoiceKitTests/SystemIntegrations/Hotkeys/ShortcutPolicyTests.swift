import XCTest
@testable import FoldWiseVoiceKit

final class ShortcutPolicyTests: XCTestCase {
    func testEffectiveIdentityCanonicalizesAliasesCaseAndWhitespace() throws {
        XCTAssertEqual(
            try KeyMap.effectiveIdentity("  ALT  "),
            try KeyMap.effectiveIdentity("alt_l")
        )
        XCTAssertEqual(
            try KeyMap.effectiveIdentity(" A "),
            try KeyMap.effectiveIdentity("a")
        )
    }

    func testCollisionIdentifiesHigherPriorityOwningCommand() throws {
        let bindings = ShortcutBindings(
            pushToTalk: "alt",
            toggleRecording: "F8",
            modeCycle: "  ALT_L "
        )

        XCTAssertThrowsError(try bindings.validatingAssignment(for: .modeCycle)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "That key is already assigned to Push to Talk."
            )
        }
    }

    func testEveryPairwiseCollisionIsRejected() throws {
        let pttAndToggle = ShortcutBindings(
            pushToTalk: "F7", toggleRecording: "f7", modeCycle: nil
        )
        let toggleAndCycle = ShortcutBindings(
            pushToTalk: "F6", toggleRecording: "x", modeCycle: " X "
        )

        XCTAssertThrowsError(try pttAndToggle.validatingAssignment(for: .toggleRecording))
        XCTAssertThrowsError(try toggleAndCycle.validatingAssignment(for: .modeCycle))
    }

    func testExternalCollisionRuntimePrecedenceDisablesLowerPriorityCommands() throws {
        let bindings = ShortcutBindings(
            pushToTalk: "F7", toggleRecording: "f7", modeCycle: " F7 "
        )

        XCTAssertEqual(
            try bindings.effectiveCommands,
            [.pushToTalk: try KeyMap.effectiveIdentity("f7")]
        )
    }
}

final class ModeCyclePolicyTests: XCTestCase {
    private let first = ModeID.random()
    private let second = ModeID.random()

    func testVoiceToTextEntersFirstModeAndModesWrapInVisibleOrder() {
        XCTAssertEqual(
            ModeCyclePolicy.nextSelection(
                after: .voiceToText,
                orderedModeIDs: [first, second]
            ),
            .mode(first)
        )
        XCTAssertEqual(
            ModeCyclePolicy.nextSelection(
                after: .mode(first),
                orderedModeIDs: [first, second]
            ),
            .mode(second)
        )
        XCTAssertEqual(
            ModeCyclePolicy.nextSelection(
                after: .mode(second),
                orderedModeIDs: [first, second]
            ),
            .mode(first)
        )
    }

    func testZeroModesAndOneSelectedModeAreNoOps() {
        XCTAssertNil(
            ModeCyclePolicy.nextSelection(after: .voiceToText, orderedModeIDs: [])
        )
        XCTAssertNil(
            ModeCyclePolicy.nextSelection(after: .mode(first), orderedModeIDs: [first])
        )
    }
}
