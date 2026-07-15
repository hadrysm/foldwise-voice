import XCTest
@testable import FoldWiseVoiceKit

final class DictationRowInteractionTests: XCTestCase {
    func testActionsRevealForPointerFocusOrCopyFeedback() {
        XCTAssertEqual(
            [
                DictationRowInteraction.actionsRevealed(
                    isHovered: false, hasFocus: false, isCopyConfirmed: false
                ),
                DictationRowInteraction.actionsRevealed(
                    isHovered: true, hasFocus: false, isCopyConfirmed: false
                ),
                DictationRowInteraction.actionsRevealed(
                    isHovered: false, hasFocus: true, isCopyConfirmed: false
                ),
                DictationRowInteraction.actionsRevealed(
                    isHovered: false, hasFocus: false, isCopyConfirmed: true
                ),
            ],
            [false, true, true, true]
        )
    }

    func testFlagActionAccessibilityReflectsCurrentState() {
        XCTAssertEqual(
            [
                DictationRowAccessibility.flagLabel(isFlagged: false),
                DictationRowAccessibility.flagHint(isFlagged: false),
                DictationRowAccessibility.flagLabel(isFlagged: true),
                DictationRowAccessibility.flagHint(isFlagged: true),
            ],
            [
                "Flag for my review",
                "Flags this dictation for later review.",
                "Remove flag",
                "Removes this dictation from your flagged items.",
            ]
        )
    }

    func testCopyAndMoreAccessibilityValuesAreSpecific() {
        XCTAssertEqual(
            [
                DictationRowAccessibility.copyLabel,
                DictationRowAccessibility.copyHint,
                DictationRowAccessibility.moreLabel,
                DictationRowAccessibility.moreHint,
                DictationRowAccessibility.copiedAnnouncement,
            ],
            [
                "Copy text",
                "Copies the displayed dictation text.",
                "More actions",
                "Shows additional actions for this dictation.",
                "Copied",
            ]
        )
    }

    func testHomeActionCompositionContainsOnlyCopyAndFlag() {
        let home = DictationRowActionComposition.make(
            presentation: presentation(),
            moreCapabilities: nil
        )

        XCTAssertEqual(
            home,
            DictationRowActionComposition(
                directActions: [.copy, .flag],
                moreActions: []
            )
        )
    }

    func testHistoryActionCompositionContainsConditionalAndDestructiveActions() {
        let history = DictationRowActionComposition.make(
            presentation: presentation(),
            moreCapabilities: .init(
                canCopyRaw: true,
                polishModeNames: ["Clean", "Email"]
            )
        )
        XCTAssertEqual(
            history,
            DictationRowActionComposition(
                directActions: [.copy, .flag, .more],
                moreActions: [
                    .command(.init(
                        label: "Copy", command: .copyDisplayed, isDestructive: false
                    )),
                    .command(.init(
                        label: "Copy raw", command: .copyRaw, isDestructive: false
                    )),
                    .command(.init(
                        label: "Remove flag", command: .toggleFlag, isDestructive: false
                    )),
                    .submenu(label: "Re-run Polish", commands: [
                        .init(
                            label: "Clean", command: .rerunPolish(modeName: "Clean"),
                            isDestructive: false
                        ),
                        .init(
                            label: "Email", command: .rerunPolish(modeName: "Email"),
                            isDestructive: false
                        ),
                    ]),
                    .separator,
                    .command(.init(
                        label: "Delete", command: .delete, isDestructive: true
                    )),
                ]
            )
        )
    }

    func testHistoryActionCompositionOmitsUnavailableRawAndPolishActions() {
        let history = DictationRowActionComposition.make(
            presentation: presentation(isFlagged: false),
            moreCapabilities: .init(canCopyRaw: false, polishModeNames: [])
        )

        XCTAssertEqual(
            history.moreActions,
            [
                .command(.init(
                    label: "Copy", command: .copyDisplayed, isDestructive: false
                )),
                .command(.init(
                    label: "Flag for my review", command: .toggleFlag,
                    isDestructive: false
                )),
                .separator,
                .command(.init(
                    label: "Delete", command: .delete, isDestructive: true
                )),
            ]
        )
    }

    @MainActor
    func testKeyboardFocusStateStopsAtSurfaceBoundaryAndTraversesBackward() {
        let interaction = DictationRowInteractionState(hasMore: true)
        interaction.setFocused(.row)
        var traversal: [DictationRowInteraction.FocusTarget?] = []

        _ = interaction.handleTab(isShiftPressed: false)
        traversal.append(interaction.focusedTarget)
        _ = interaction.handleTab(isShiftPressed: false)
        traversal.append(interaction.focusedTarget)
        _ = interaction.handleTab(isShiftPressed: false)
        traversal.append(interaction.focusedTarget)
        let exitsForward = !interaction.handleTab(isShiftPressed: false)
        _ = interaction.handleTab(isShiftPressed: true)
        traversal.append(interaction.focusedTarget)
        _ = interaction.handleTab(isShiftPressed: true)
        traversal.append(interaction.focusedTarget)
        _ = interaction.handleTab(isShiftPressed: true)
        traversal.append(interaction.focusedTarget)
        let exitsBackward = !interaction.handleTab(isShiftPressed: true)

        XCTAssertEqual(
            [
                traversal == [.copy, .flag, .more, .flag, .copy, .row],
                exitsForward,
                exitsBackward,
            ],
            [true, true, true]
        )
    }

    @MainActor
    func testCopyFeedbackConfirmsAnnouncesAndResetsThroughInjectedSchedule() {
        var scheduledReset: (@MainActor () -> Void)?
        let feedback = DictationRowCopyFeedback { reset in
            scheduledReset = reset
            return {}
        }
        var announcements = 0

        feedback.confirm { announcements += 1 }
        let confirmed = feedback.isConfirmed
        scheduledReset?()

        XCTAssertEqual([confirmed, feedback.isConfirmed, announcements == 1], [true, false, true])
    }

    @MainActor
    func testCopyFeedbackCancelsSupersededAndDisappearingReset() {
        var cancellations = 0
        let feedback = DictationRowCopyFeedback { _ in
            { cancellations += 1 }
        }

        feedback.confirm {}
        feedback.confirm {}
        feedback.cancel()

        XCTAssertEqual([cancellations == 2, feedback.isConfirmed], [true, false])
    }

    @MainActor
    func testCopyFeedbackLiveSchedulerCanBeCancelled() {
        let feedback = DictationRowCopyFeedback()

        feedback.confirm {}
        let confirmed = feedback.isConfirmed
        feedback.cancel()

        XCTAssertEqual([confirmed, feedback.isConfirmed], [true, false])
    }

    private func presentation(isFlagged: Bool = true) -> DictationRowPresentation {
        DictationRowPresentation(entry: HistoryEntry(
            id: UUID(), createdAt: Date(timeIntervalSince1970: 1_783_499_700),
            text: "Words", rawText: "raw words", isPolished: true, modeName: "Clean",
            wordCount: nil, sourceApp: nil, durationMs: nil,
            flagged: isFlagged, flagReason: nil
        ))
    }
}
