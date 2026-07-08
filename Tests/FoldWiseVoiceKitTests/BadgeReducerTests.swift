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

    func testTranscribingEntersWorking() {
        XCTAssertEqual(
            reduce(.recording, .pipeline(.transcribing)).state,
            .working(status: "transcribing…")
        )
    }

    func testPolishingKeepsWorkingWithAStatusWord() {
        XCTAssertEqual(
            reduce(.working(status: "transcribing…"), .pipeline(.polishing(model: "qwen2.5:3b"))).state,
            .working(status: "polishing…")
        )
    }

    func testInsertedEntersTheDoneBeat() {
        XCTAssertEqual(reduce(.working(status: "polishing…"), .pipeline(.inserted)).state, .done)
    }

    func testClipboardFallbackIsAVisibleErrorState() {
        let state = reduce(.working(status: "transcribing…"), .pipeline(.clipboard)).state
        XCTAssertEqual(state, .error(message: "copied — press ⌘V"))
    }

    func testPipelineErrorShowsTheErrorState() {
        let state = reduce(.working(status: "transcribing…"), .pipeline(.error("boom"))).state
        XCTAssertEqual(state, .error(message: "something went wrong"))
    }

    func testPipelineIdleCollapsesRecordingToIdle() {
        // A session that captured nothing emits .idle straight from the stop.
        XCTAssertEqual(reduce(.working(status: "transcribing…"), .pipeline(.idle)).state, .idle)
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
        let transition = reduce(.working(status: "polishing…"), .clicked)
        XCTAssertEqual(transition, BadgeTransition(state: .working(status: "polishing…"), command: nil))
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
        XCTAssertEqual(BadgeState.idle.width, 104)
        XCTAssertEqual(BadgeState.hover.width, 158)
        XCTAssertEqual(BadgeState.recording.width, 248)
        XCTAssertEqual(BadgeState.working(status: "polishing…").width, 248)
    }

    func testRibbonsFollowTheMicOnlyWhileRecording() {
        XCTAssertTrue(BadgeState.recording.ribbonsFollowMic)
        XCTAssertTrue(BadgeState.working(status: "polishing…").showsRibbons)
        XCTAssertFalse(BadgeState.working(status: "polishing…").ribbonsFollowMic)
        XCTAssertFalse(BadgeState.idle.showsRibbons)
    }
}
