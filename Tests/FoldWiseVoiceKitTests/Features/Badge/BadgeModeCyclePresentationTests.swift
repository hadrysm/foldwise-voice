import XCTest
@testable import FoldWiseVoiceKit

final class BadgeModeCyclePresentationTests: XCTestCase {
    private let casual = BadgeModeCycleItem(
        selection: .mode(.random()), name: "Casual", icon: "wand.and.sparkles"
    )
    private let email = BadgeModeCycleItem(
        selection: .mode(.random()), name: "Email", icon: "envelope"
    )
    private let meeting = BadgeModeCycleItem(
        selection: .mode(.random()), name: "Meeting", icon: "person.2"
    )

    func testCommittedTransitionPreparesExpandedReelFromCommittedPair() {
        let transition = BadgeModeCycleReducer.reduce(
            .idle(), .committed(from: casual, to: email)
        )

        XCTAssertEqual(
            transition,
            BadgeModeCycleTransition(
                state: BadgeModeCycleState(
                    display: .prepared(from: casual, to: email, motion: .standard),
                    visiblyConfirmed: casual
                ),
                effects: [.send(.swapBegan)]
            )
        )
    }

    func testConfirmationMetricsMatchAcceptedBadgeContract() {
        XCTAssertEqual(
            [
                BadgeModeCycleReducer.expandedWidth,
                BadgeModeCycleReducer.resizeDuration,
                BadgeModeCycleReducer.swapDuration,
                BadgeModeCycleReducer.settledDwell,
            ],
            [176, 0.300, 0.260, 0.900]
        )
    }

    func testStandardSwapAndSettledDwellUseAcceptedDurations() {
        let prepared = BadgeModeCycleReducer.reduce(
            .idle(), .committed(from: casual, to: email)
        ).state
        let swapping = BadgeModeCycleReducer.reduce(prepared, .swapBegan)
        let settled = BadgeModeCycleReducer.reduce(swapping.state, .swapElapsed)

        XCTAssertEqual(
            [swapping, settled],
            [
                BadgeModeCycleTransition(
                    state: BadgeModeCycleState(
                        display: .swapping(from: casual, to: email, motion: .standard),
                        visiblyConfirmed: casual
                    ),
                    effects: [.schedule(.swapElapsed, after: 0.260)]
                ),
                BadgeModeCycleTransition(
                    state: BadgeModeCycleState(
                        display: .settled(email, motion: .standard),
                        visiblyConfirmed: email
                    ),
                    effects: [.schedule(.dwellElapsed, after: 0.900)]
                ),
            ]
        )
    }

    func testOnlySwapPhaseAnimatesBetweenPreparedQueueSteps() {
        XCTAssertEqual(
            [
                BadgeModeCycleDisplay.prepared(
                    from: casual, to: email, motion: .standard
                ).animatesSwap,
                BadgeModeCycleDisplay.swapping(
                    from: casual, to: email, motion: .standard
                ).animatesSwap,
                BadgeModeCycleDisplay.settled(
                    email, motion: .standard
                ).animatesSwap,
            ],
            [false, true, false]
        )
    }

    func testStandardReelMovesPersistentRowsThroughOppositeEdges() {
        let prepared = BadgeModeCycleDisplay.prepared(
            from: casual, to: email, motion: .standard
        )
        let swapping = BadgeModeCycleDisplay.swapping(
            from: casual, to: email, motion: .standard
        )

        XCTAssertEqual(
            [
                prepared.outgoingOpacity, prepared.outgoingOffset,
                prepared.incomingOpacity, prepared.incomingOffset,
                swapping.outgoingOpacity, swapping.outgoingOffset,
                swapping.incomingOpacity, swapping.incomingOffset,
            ],
            [1, 0, 0, 18, 0, -18, 1, 0]
        )
    }

    func testRapidCommittedTransitionsPlayFIFOWithoutSkipping() {
        var state = BadgeModeCycleReducer.reduce(
            .idle(), .committed(from: casual, to: email)
        ).state
        state = BadgeModeCycleReducer.reduce(
            state, .committed(from: email, to: meeting)
        ).state
        state = BadgeModeCycleReducer.reduce(
            state, .committed(from: meeting, to: casual)
        ).state
        state = BadgeModeCycleReducer.reduce(state, .swapBegan).state
        let firstFinished = BadgeModeCycleReducer.reduce(state, .swapElapsed)
        let secondStarted = BadgeModeCycleReducer.reduce(
            BadgeModeCycleReducer.reduce(firstFinished.state, .swapBegan).state,
            .swapElapsed
        )

        XCTAssertEqual(
            [firstFinished.state.display, secondStarted.state.display],
            [
                .prepared(from: email, to: meeting, motion: .standard),
                .prepared(from: meeting, to: casual, motion: .standard),
            ]
        )
    }

    func testPipelineInterruptionCoalescesFromLastVisiblyConfirmedToFinalCommit() {
        var state = BadgeModeCycleReducer.reduce(
            .idle(), .committed(from: casual, to: email)
        ).state
        state = BadgeModeCycleReducer.reduce(state, .swapBegan).state
        state = BadgeModeCycleReducer.reduce(
            state, .committed(from: email, to: meeting)
        ).state

        let interrupted = BadgeModeCycleReducer.reduce(state, .badgeBecameBusy)
        let resumed = BadgeModeCycleReducer.reduce(
            interrupted.state, .badgeBecameAvailable
        )

        XCTAssertEqual(
            [interrupted, resumed],
            [
                BadgeModeCycleTransition(
                    state: BadgeModeCycleState(
                        badgeIsAvailable: false,
                        deferredFrom: casual,
                        deferredTo: meeting,
                        reducedMotion: false
                    ),
                    effects: [.cancelScheduled]
                ),
                BadgeModeCycleTransition(
                    state: BadgeModeCycleState(
                        display: .prepared(from: casual, to: meeting, motion: .standard),
                        visiblyConfirmed: casual
                    ),
                    effects: [.send(.swapBegan)]
                ),
            ]
        )
    }

    func testCommitsDuringPipelineOwnershipCoalesceWithoutIntermediateReel() {
        var state = BadgeModeCycleReducer.reduce(.idle(), .badgeBecameBusy).state
        state = BadgeModeCycleReducer.reduce(
            state, .committed(from: casual, to: email)
        ).state
        state = BadgeModeCycleReducer.reduce(
            state, .committed(from: email, to: meeting)
        ).state

        let resumed = BadgeModeCycleReducer.reduce(state, .badgeBecameAvailable)

        XCTAssertEqual(
            resumed.state.display,
            .prepared(from: casual, to: meeting, motion: .standard)
        )
    }

    func testDeferredWrapBackToVisibleModeIsSilent() {
        var state = BadgeModeCycleReducer.reduce(.idle(), .badgeBecameBusy).state
        state = BadgeModeCycleReducer.reduce(
            state, .committed(from: casual, to: email)
        ).state
        state = BadgeModeCycleReducer.reduce(
            state, .committed(from: email, to: casual)
        ).state

        let resumed = BadgeModeCycleReducer.reduce(state, .badgeBecameAvailable)

        XCTAssertEqual(
            resumed,
            BadgeModeCycleTransition(state: .idle(), effects: [])
        )
    }

    func testFailureDuringPipelineOwnershipAppearsBeforeDeferredSuccess() {
        var state = BadgeModeCycleReducer.reduce(.idle(), .badgeBecameBusy).state
        state = BadgeModeCycleReducer.reduce(
            state, .committed(from: casual, to: email)
        ).state
        state = BadgeModeCycleReducer.reduce(state, .failed).state

        let error = BadgeModeCycleReducer.reduce(state, .badgeBecameAvailable)
        let success = BadgeModeCycleReducer.reduce(error.state, .badgeBecameAvailable)

        XCTAssertEqual(
            [error, success],
            [
                BadgeModeCycleTransition(
                    state: BadgeModeCycleState(
                        badgeIsAvailable: false,
                        deferredFrom: casual,
                        deferredTo: email
                    ),
                    effects: [.showError("couldn’t switch Mode")]
                ),
                BadgeModeCycleTransition(
                    state: BadgeModeCycleState(
                        display: .prepared(from: casual, to: email, motion: .standard),
                        visiblyConfirmed: casual
                    ),
                    effects: [.send(.swapBegan)]
                ),
            ]
        )
    }

    func testRepeatedPipelineFailuresCoalesceIntoOneDeferredError() {
        var state = BadgeModeCycleReducer.reduce(.idle(), .badgeBecameBusy).state
        state = BadgeModeCycleReducer.reduce(state, .failed).state
        state = BadgeModeCycleReducer.reduce(state, .failed).state

        let firstAvailable = BadgeModeCycleReducer.reduce(state, .badgeBecameAvailable)
        let secondAvailable = BadgeModeCycleReducer.reduce(
            firstAvailable.state, .badgeBecameAvailable
        )

        XCTAssertEqual(
            [firstAvailable.effects, secondAvailable.effects],
            [[.showError("couldn’t switch Mode")], []]
        )
    }

    func testIdleFailureCancelsPresentationAndRequestsNormalError() {
        let presenting = BadgeModeCycleReducer.reduce(
            .idle(), .committed(from: casual, to: email)
        ).state

        let failed = BadgeModeCycleReducer.reduce(presenting, .failed)

        XCTAssertEqual(
            failed,
            BadgeModeCycleTransition(
                state: BadgeModeCycleState(
                    badgeIsAvailable: false,
                    deferredFrom: casual,
                    deferredTo: email,
                    reducedMotion: false
                ),
                effects: [.cancelScheduled, .showError("couldn’t switch Mode")]
            )
        )
    }

    func testReduceMotionUsesCrossfadeWithoutTravelAndKeepsSettledDwell() {
        var state = BadgeModeCycleState.idle(reducedMotion: true)
        state = BadgeModeCycleReducer.reduce(
            state, .committed(from: casual, to: email)
        ).state
        let swapping = BadgeModeCycleReducer.reduce(state, .swapBegan)
        let settled = BadgeModeCycleReducer.reduce(swapping.state, .swapElapsed)

        XCTAssertEqual(
            [swapping, settled],
            [
                BadgeModeCycleTransition(
                    state: BadgeModeCycleState(
                        display: .swapping(from: casual, to: email, motion: .reduced),
                        visiblyConfirmed: casual,
                        reducedMotion: true
                    ),
                    effects: [.schedule(.swapElapsed, after: 0.180)]
                ),
                BadgeModeCycleTransition(
                    state: BadgeModeCycleState(
                        display: .settled(email, motion: .reduced),
                        visiblyConfirmed: email,
                        reducedMotion: true
                    ),
                    effects: [.schedule(.dwellElapsed, after: 0.900)]
                ),
            ]
        )
    }

    func testDwellCompletionReturnsToIdleAndForgetsPriorDirectSelection() {
        let state = BadgeModeCycleState(
            display: .settled(email, motion: .standard),
            visiblyConfirmed: email
        )

        let completed = BadgeModeCycleReducer.reduce(state, .dwellElapsed)

        XCTAssertEqual(
            completed,
            BadgeModeCycleTransition(
                state: .idle(), effects: [.cancelScheduled]
            )
        )
    }

    func testPressDuringSettledDwellStartsNextSwapImmediately() {
        let state = BadgeModeCycleState(
            display: .settled(email, motion: .standard),
            visiblyConfirmed: email
        )

        let transition = BadgeModeCycleReducer.reduce(
            state, .committed(from: email, to: meeting)
        )

        XCTAssertEqual(
            transition,
            BadgeModeCycleTransition(
                state: BadgeModeCycleState(
                    display: .prepared(from: email, to: meeting, motion: .standard),
                    visiblyConfirmed: email
                ),
                effects: [.cancelScheduled, .send(.swapBegan)]
            )
        )
    }

    func testLiveReduceMotionChangeUpdatesActivePresentation() {
        let state = BadgeModeCycleState(
            display: .prepared(from: casual, to: email, motion: .standard),
            visiblyConfirmed: casual
        )

        let transition = BadgeModeCycleReducer.reduce(
            state, .reduceMotionChanged(true)
        )

        XCTAssertEqual(
            transition.state.display,
            .prepared(from: casual, to: email, motion: .reduced)
        )
    }

    func testModeCyclePresentationSuppressesHoverUntilDwellCompletes() {
        XCTAssertEqual(
            [
                BadgeModeCycleState.idle().allowsHover,
                BadgeModeCycleState(
                    display: .prepared(from: casual, to: email, motion: .standard)
                ).allowsHover,
                BadgeModeCycleState(
                    display: .settled(email, motion: .standard)
                ).allowsHover,
            ],
            [true, false, false]
        )
    }

    func testPresentationChangesRefreshVisibleAndQueuedModesWithoutEffects() {
        let renamedCasual = BadgeModeCycleItem(
            selection: casual.selection, name: "Everyday", icon: "sun.max"
        )
        let renamedEmail = BadgeModeCycleItem(
            selection: email.selection, name: "Correspondence", icon: "paperclip"
        )
        let renamedMeeting = BadgeModeCycleItem(
            selection: meeting.selection, name: "Stand-up", icon: "person.3"
        )
        let state = BadgeModeCycleState(
            display: .prepared(from: casual, to: email, motion: .standard),
            queued: [meeting],
            visiblyConfirmed: casual
        )

        let transition = BadgeModeCycleReducer.reduce(
            state,
            .presentationsChanged([renamedCasual, renamedEmail, renamedMeeting])
        )

        XCTAssertEqual(
            transition,
            BadgeModeCycleTransition(
                state: BadgeModeCycleState(
                    display: .prepared(
                        from: renamedCasual, to: renamedEmail, motion: .standard
                    ),
                    queued: [renamedMeeting],
                    visiblyConfirmed: renamedCasual
                ),
                effects: []
            )
        )
    }

    func testStaleSwapTimerAfterPipelineCancellationCannotRestoreReel() {
        var state = BadgeModeCycleReducer.reduce(
            .idle(), .committed(from: casual, to: email)
        ).state
        state = BadgeModeCycleReducer.reduce(state, .swapBegan).state
        state = BadgeModeCycleReducer.reduce(state, .badgeBecameBusy).state

        let staleTimer = BadgeModeCycleReducer.reduce(state, .swapElapsed)

        XCTAssertEqual(
            staleTimer,
            BadgeModeCycleTransition(
                state: BadgeModeCycleState(
                    badgeIsAvailable: false,
                    deferredFrom: casual,
                    deferredTo: email
                ),
                effects: []
            )
        )
    }

    func testLongModeNameRemainsCompleteForAccessibility() {
        let longName = "Quarterly planning notes with every stakeholder and follow-up detail"
        let longMode = BadgeModeCycleItem(
            selection: .mode(.random()), name: longName, icon: "text.bubble"
        )
        let display = BadgeModeCycleDisplay.settled(longMode, motion: .standard)

        XCTAssertEqual(display.accessibilityLabel, longName)
    }

    func testCenteredFramePreservesAnchorAcrossConfirmationResize() {
        let anchor = CGPoint(x: 300, y: 120)
        let screen = CGRect(x: 0, y: 0, width: 900, height: 600)
        let idle = BadgeFramePolicy.frame(
            size: CGSize(width: 88, height: 38), anchor: anchor, screen: screen
        )
        let confirmation = BadgeFramePolicy.frame(
            size: CGSize(width: 176, height: 38), anchor: anchor, screen: screen
        )

        XCTAssertEqual(
            [idle.midX, idle.minY, confirmation.midX, confirmation.minY],
            [300, 120, 300, 120]
        )
    }

    func testCenteredFrameClampsToVisibleScreenMargins() {
        let frame = BadgeFramePolicy.frame(
            size: CGSize(width: 176, height: 38),
            anchor: CGPoint(x: 10, y: -20),
            screen: CGRect(x: 0, y: 0, width: 900, height: 600)
        )

        XCTAssertEqual(frame.origin, CGPoint(x: 4, y: 4))
    }
}
