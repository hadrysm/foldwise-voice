// The Badge state machine's contract (PRD #103): the idle ⇄ hover pointer
// dance, the pipeline-driven recording → working → done/error flow, the
// dwell-based returns to idle, and recording's exit-only-via-stop rule —
// all through the one pure reducer.

import XCTest
@testable import FoldWiseVoiceKit

final class BadgeReducerTests: XCTestCase {
    private func reduce(_ state: BadgeState, _ event: BadgeEvent) -> BadgeTransition {
        BadgeReducer.reduce(state, event)
    }

    // MARK: - idle ⇄ hover

    func testHoverEnterExpandsIdleToHover() {
        XCTAssertEqual(reduce(.idle, .hoverChanged(true)).state, .hover)
    }

    func testHoverExitReturnsToIdle() {
        XCTAssertEqual(reduce(.hover, .hoverChanged(false)).state, .idle)
    }

    func testHoverChangesAreIgnoredWhileRecording() {
        XCTAssertEqual(reduce(.recording, .hoverChanged(true)).state, .recording)
        XCTAssertEqual(reduce(.recording, .hoverChanged(false)).state, .recording)
    }

    // MARK: - pipeline-driven flow

    func testListeningEntersRecordingFromIdleAndHover() {
        XCTAssertEqual(reduce(.idle, .pipeline(.listening(mode: "Clean"))).state, .recording)
        XCTAssertEqual(reduce(.hover, .pipeline(.listening(mode: "Clean"))).state, .recording)
    }

    func testTranscribingEntersWorkingWithTheSpinner() {
        XCTAssertEqual(
            reduce(.recording, .pipeline(.transcribing)).state,
            .working(status: nil)
        )
    }

    func testPolishingKeepsTheSpinnerWorkingState() {
        XCTAssertEqual(
            reduce(.working(status: nil), .pipeline(.polishing(model: "qwen2.5:3b"))).state,
            .working(status: nil)
        )
    }

    func testModelDownloadKeepsAProgressWordInsteadOfTheSpinner() {
        XCTAssertEqual(
            reduce(.working(status: nil), .pipeline(.downloadingModel(fraction: 0.45))).state,
            .working(status: "downloading 45%")
        )
    }

    func testBlockedRecognitionExplainsWhyDictationCannotStart() {
        XCTAssertEqual(
            reduce(.idle, .pipeline(.recognitionUnavailable)).state,
            .working(status: "speech model unavailable")
        )
    }

    func testASRSelectionSwitchExplainsWhyDictationIsPaused() {
        XCTAssertEqual(
            reduce(.idle, .pipeline(.switchingASRModel)).state,
            .working(status: "switching speech model…")
        )
    }

    func testASRSwitchKeepsBadgeBlockingThenRestoresPipelineWork() {
        let presentation = ASRBadgePresentation()

        let states = [
            presentation.lifecycleDidChange(
                operation: .switching(modelID: "whisper-small"),
                isDictationBlocked: true
            ),
            presentation.pipelineDidChange(.polishing(model: "qwen2.5:3b")),
            presentation.lifecycleDidChange(operation: nil, isDictationBlocked: false),
        ]

        XCTAssertEqual(states, [.switchingASRModel, nil, .polishing(model: "qwen2.5:3b")])
    }

    func testInsertedEntersTheDoneBeat() {
        XCTAssertEqual(reduce(.working(status: nil), .pipeline(.inserted)).state, .done)
    }

    func testClipboardFallbackIsAVisibleErrorState() {
        let state = reduce(.working(status: nil), .pipeline(.clipboard)).state
        XCTAssertEqual(state, .error(message: "copied — press ⌘V"))
    }

    func testPipelineErrorShowsTheErrorState() {
        let state = reduce(.working(status: nil), .pipeline(.error("boom"))).state
        XCTAssertEqual(state, .error(message: "something went wrong"))
    }

    func testPipelineIdleCollapsesRecordingToIdle() {
        // A session that captured nothing emits .idle straight from the stop.
        XCTAssertEqual(reduce(.working(status: nil), .pipeline(.idle)).state, .idle)
    }

    func testModeSelectionFailureDefersToPipelineOwnedFeedback() {
        XCTAssertEqual(
            [
                reduce(.idle, .modeSelectionFailed),
                reduce(.recording, .modeSelectionFailed),
                reduce(.working(status: nil), .modeSelectionFailed),
            ],
            [
                BadgeTransition(
                    state: .error(message: "couldn’t select Mode"), command: nil
                ),
                BadgeTransition(
                    state: .recording,
                    command: nil,
                    deferredModeSelectionError: true
                ),
                BadgeTransition(
                    state: .working(status: nil),
                    command: nil,
                    deferredModeSelectionError: true
                ),
            ]
        )
    }

    func testDeferredModeSelectionFailureAppearsAfterPipelineReturnsToIdle() {
        let deferred = reduce(.recording, .modeSelectionFailed)

        XCTAssertEqual(
            BadgeReducer.reduce(
                deferred.state,
                .pipeline(.idle),
                deferredModeSelectionError: deferred.deferredModeSelectionError
            ),
            BadgeTransition(
                state: .error(message: "couldn’t select Mode"),
                command: nil
            )
        )
    }

    // MARK: - clicks

    func testClickWhileRecordingRequestsStopAndStaysRecording() {
        let transition = reduce(.recording, .clicked)
        XCTAssertEqual(transition, BadgeTransition(state: .recording, command: .stopRecording))
    }

    func testClickDismissesTheErrorStateEarly() {
        XCTAssertEqual(reduce(.error(message: "copied — press ⌘V"), .clicked).state, .idle)
    }

    func testClickWhileWorkingDoesNothing() {
        let transition = reduce(.working(status: nil), .clicked)
        XCTAssertEqual(transition, BadgeTransition(state: .working(status: nil), command: nil))
    }

    // MARK: - dwells

    func testDoneBeatDwellsBrieflyThenReturnsToIdle() {
        XCTAssertNotNil(BadgeState.done.dwell)
        XCTAssertEqual(reduce(.done, .dwellElapsed).state, .idle)
    }

    func testErrorAutoDismissesAfterItsDwell() {
        XCTAssertNotNil(BadgeState.error(message: "x").dwell)
        XCTAssertEqual(reduce(.error(message: "x"), .dwellElapsed).state, .idle)
    }

    func testRecordingHasNoDwellAndIgnoresDwellElapsed() {
        XCTAssertNil(BadgeState.recording.dwell)
        XCTAssertEqual(reduce(.recording, .dwellElapsed).state, .recording)
    }

    // MARK: - content descriptor

    func testWidthsMatchTheSpec() {
        XCTAssertEqual(BadgeState.idle.width, 88)
        XCTAssertEqual(BadgeState.hover.width, 132)
        XCTAssertEqual(BadgeState.recording.width, 208)
        XCTAssertEqual(BadgeState.working(status: nil).width, 208)
    }

    func testRibbonsFollowTheMicOnlyWhileRecording() {
        XCTAssertTrue(BadgeState.recording.ribbonsFollowMic)
        XCTAssertTrue(BadgeState.working(status: nil).showsRibbons)
        XCTAssertFalse(BadgeState.working(status: nil).ribbonsFollowMic)
        XCTAssertFalse(BadgeState.idle.showsRibbons)
    }

    func testPipelineAndErrorFeedbackOwnModeCyclePresentation() {
        XCTAssertEqual(
            [
                BadgeState.idle.ownsModeCyclePresentation,
                BadgeState.hover.ownsModeCyclePresentation,
                BadgeState.recording.ownsModeCyclePresentation,
                BadgeState.working(status: nil).ownsModeCyclePresentation,
                BadgeState.done.ownsModeCyclePresentation,
                BadgeState.error(message: "x").ownsModeCyclePresentation,
            ],
            [false, false, true, true, true, true]
        )
    }
}
