import XCTest
@testable import FoldWiseVoiceKit

final class LiveTranscriptCaptionTests: XCTestCase {
    private let session = UUID()
    private let other = UUID()

    // MARK: - appearing

    func testCaptionStaysHiddenBeforeAnyWordsArrive() {
        let state = drive([.session(.started(session)), .pipeline(.listening(mode: "Email"))])

        XCTAssertNil(state.presentation)
    }

    func testCaptionStaysHiddenForASessionThatNeverStreams() {
        let state = drive([
            .session(.started(session)),
            .pipeline(.listening(mode: "Email")),
            .pipeline(.transcribing),
            .pipeline(.polishing(model: "qwen2.5:3b")),
            .pipeline(.inserted),
        ])

        XCTAssertNil(state.presentation)
    }

    func testFirstWordsShowTheRawLiveHeader() {
        let state = drive(recording(committed: "hey sam ", tentative: "i wanted"))

        XCTAssertEqual(state.presentation?.header, "RAW · LIVE")
    }

    func testLiveSpansKeepCommittedAndTentativeTextApart() {
        let state = drive(recording(committed: "hey sam ", tentative: "i wanted"))

        XCTAssertEqual(
            state.presentation.map { [$0.committed, $0.tentative] },
            ["hey sam ", "i wanted"]
        )
    }

    func testTentativeTailCarriesTheLiveFrontierMarker() {
        let state = drive(recording(committed: "hey sam ", tentative: "i wanted"))

        XCTAssertEqual(state.presentation?.marksLiveFrontier, true)
    }

    func testSettledTextDropsTheLiveFrontierMarker() {
        let state = drive(recording(committed: "hey sam", tentative: ""))

        XCTAssertEqual(state.presentation?.marksLiveFrontier, false)
    }

    func testListeningShowsNoStageHandoff() {
        let state = drive(recording(committed: "hey sam", tentative: ""))

        XCTAssertNil(state.presentation?.handoff)
    }

    // MARK: - locking and Polish

    func testReleaseLocksTheRawTextHeader() {
        let state = drive(recording(committed: "hey sam ", tentative: "i wanted") + [
            .transcript(locked(committed: "hey sam i wanted")),
        ])

        XCTAssertEqual(state.presentation?.header, "RAW · LOCKED")
    }

    func testFinalizationNamesTheSpeechStage() {
        let state = drive(released())

        XCTAssertEqual(state.presentation?.handoff, "finalizing speech…")
    }

    func testPolishNamesTheModeShapingTheText() {
        let state = drive(released() + [.pipeline(.polishing(model: "qwen2.5:3b"))])

        XCTAssertEqual(state.presentation?.handoff, "shaping as Email…")
    }

    func testPolishKeepsTheLockedRawTextOnScreen() {
        let state = drive(released() + [.pipeline(.polishing(model: "qwen2.5:3b"))])

        XCTAssertEqual(state.presentation?.committed, "hey sam i wanted")
    }

    func testPolishLetsTheRawTextRecede() {
        let state = drive(released() + [.pipeline(.polishing(model: "qwen2.5:3b"))])

        XCTAssertEqual(state.presentation?.recedesCommitted, true)
    }

    func testTheAuthoritativeTranscriptDoesNotRewindTheLockedHeader() {
        let state = drive(released() + [
            .transcript(locked(committed: "Hey Sam, I wanted to ask.")),
        ])

        XCTAssertEqual(
            state.presentation.map { [$0.header, $0.handoff ?? ""] },
            ["RAW · LOCKED", "finalizing speech…"]
        )
    }

    // MARK: - session identity

    func testASnapshotFromAnotherSessionCannotOverwriteTheCaption() {
        let state = drive(recording(committed: "hey sam", tentative: "") + [
            .transcript(DictationTranscript(
                dictationSessionID: other,
                snapshot: TranscriptSnapshot(committed: "someone else", tentative: ""),
                phase: .live
            )),
        ])

        XCTAssertEqual(state.presentation?.committed, "hey sam")
    }

    func testAnOverlappingSessionDoesNotInheritThePreviousSessionsText() {
        let state = drive(released() + [.session(.started(other))])

        XCTAssertNil(state.presentation)
    }

    func testAnEarlierSessionsOutcomeLeavesALiveCaptionAlone() {
        let state = drive(released() + [
            .session(.started(other)),
            .transcript(DictationTranscript(
                dictationSessionID: other,
                snapshot: TranscriptSnapshot(committed: "second take", tentative: ""),
                phase: .live
            )),
            .pipeline(.inserted),
        ])

        XCTAssertEqual(state.presentation?.committed, "second take")
    }

    func testAnEarlierSessionsFinishLeavesTheCaptionAlone() {
        let state = drive(recording(committed: "hey sam", tentative: "") + [
            .session(.finished(other)),
        ])

        XCTAssertEqual(state.presentation?.committed, "hey sam")
    }

    // MARK: - dismissal

    func testEveryDictationOutcomeDismissesTheCaption() {
        let outcomes: [PipelineState] = [.inserted, .clipboard, .idle, .error("boom")]

        let presentations = outcomes.map { outcome in
            drive(released() + [.pipeline(outcome)]).presentation
        }

        XCTAssertEqual(presentations.map { $0 == nil }, Array(repeating: true, count: 4))
    }

    func testARecorderFailureWhileSpeakingDismissesTheCaption() {
        let state = drive(recording(committed: "hey sam", tentative: "") + [
            .pipeline(.error("input device disappeared")),
            .session(.finished(session)),
        ])

        XCTAssertNil(state.presentation)
    }

    func testShutdownDismissesTheCaption() {
        let state = drive(recording(committed: "hey sam", tentative: "") + [
            .pipeline(.idle),
            .session(.finished(session)),
        ])

        XCTAssertNil(state.presentation)
    }

    func testAModelLifecycleStateLeavesTheCaptionUntouched() {
        let state = drive(released() + [.pipeline(.downloadingModel(fraction: 0.4))])

        XCTAssertEqual(state.presentation?.handoff, "finalizing speech…")
    }

    // MARK: - truncation

    func testTheCaptionKeepsTheNewestWordsWithinTwoLines() {
        XCTAssertEqual(
            [
                LiveTranscriptCaptionPresentation.lineLimit,
                LiveTranscriptCaptionPresentation.truncatesHead ? 1 : 0,
            ],
            [2, 1]
        )
    }

    // MARK: - accessibility

    func testAccessibilityValueSpeaksBothLiveSpans() {
        let state = drive(recording(committed: "hey sam ", tentative: "i wanted"))

        XCTAssertEqual(
            state.presentation?.accessibilityValue,
            "Live, hey sam, tentative i wanted"
        )
    }

    func testAccessibilityValueSpeaksTheShapingMode() {
        let state = drive(released() + [.pipeline(.polishing(model: "qwen2.5:3b"))])

        XCTAssertEqual(
            state.presentation?.accessibilityValue,
            "Locked, hey sam i wanted, shaping as Email"
        )
    }

    func testAccessibilityValueSpeaksFinalization() {
        let state = drive(released())

        XCTAssertEqual(
            state.presentation?.accessibilityValue,
            "Locked, hey sam i wanted, finalizing speech"
        )
    }

    func testAccessibilityLabelNamesTheSurfaceAsRaw() {
        let state = drive(recording(committed: "hey sam", tentative: ""))

        XCTAssertEqual(state.presentation?.accessibilityLabel, "Raw transcript")
    }

    // MARK: - motion

    func testStandardMotionFadesTheCaptionIn() {
        XCTAssertEqual(
            LiveTranscriptCaptionMotion.appearance(reduceMotion: false),
            .fade(duration: 0.16)
        )
    }

    func testReduceMotionCutsTheCaptionIn() {
        XCTAssertEqual(LiveTranscriptCaptionMotion.appearance(reduceMotion: true), .cut)
    }

    // MARK: - geometry

    private static let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testCaptionSitsCentredJustAboveTheBadge() {
        let badge = CGRect(x: 616, y: 96, width: 208, height: 38)

        let placement = LiveTranscriptCaptionFramePolicy.placement(
            badge: badge,
            screen: Self.screen
        )

        XCTAssertEqual(placement.frame, CGRect(x: 510, y: 136, width: 420, height: 82))
    }

    func testCaptionKeepsItsTetherOnACentredBadge() {
        let badge = CGRect(x: 616, y: 96, width: 208, height: 38)

        let placement = LiveTranscriptCaptionFramePolicy.placement(
            badge: badge,
            screen: Self.screen
        )

        XCTAssertEqual(placement.tetherOffset, 0)
    }

    func testCaptionClampsInsideTheLeftScreenEdge() {
        let badge = CGRect(x: 8, y: 96, width: 208, height: 38)

        let placement = LiveTranscriptCaptionFramePolicy.placement(
            badge: badge,
            screen: Self.screen
        )

        XCTAssertEqual(placement.frame.minX, 4)
    }

    func testTetherKeepsPointingAtAClampedBadge() {
        let badge = CGRect(x: 8, y: 96, width: 208, height: 38)

        let placement = LiveTranscriptCaptionFramePolicy.placement(
            badge: badge,
            screen: Self.screen
        )

        XCTAssertEqual(placement.tetherOffset, -102)
    }

    func testCaptionClampsBelowTheTopScreenEdge() {
        let badge = CGRect(x: 616, y: 850, width: 208, height: 38)

        let placement = LiveTranscriptCaptionFramePolicy.placement(
            badge: badge,
            screen: Self.screen
        )

        XCTAssertEqual(placement.frame.maxY, 896)
    }

    func testCaptionWithoutAKnownScreenTracksTheBadgeUnclamped() {
        let badge = CGRect(x: 8, y: 96, width: 208, height: 38)

        let placement = LiveTranscriptCaptionFramePolicy.placement(badge: badge, screen: nil)

        XCTAssertEqual(placement.frame.minX, -98)
    }

    // MARK: - helpers

    private func drive(_ events: [LiveTranscriptCaptionEvent]) -> LiveTranscriptCaptionState {
        events.reduce(LiveTranscriptCaptionState()) {
            LiveTranscriptCaptionReducer.reduce($0, $1)
        }
    }

    /// A streaming session that has published one live snapshot.
    private func recording(
        committed: String,
        tentative: String
    ) -> [LiveTranscriptCaptionEvent] {
        [
            .session(.started(session)),
            .pipeline(.listening(mode: "Email")),
            .transcript(DictationTranscript(
                dictationSessionID: session,
                snapshot: TranscriptSnapshot(committed: committed, tentative: tentative),
                phase: .live
            )),
        ]
    }

    /// The same session past hotkey release, finalizing its own stream.
    private func released() -> [LiveTranscriptCaptionEvent] {
        recording(committed: "hey sam ", tentative: "i wanted") + [
            .transcript(locked(committed: "hey sam i wanted")),
            .pipeline(.transcribing),
        ]
    }

    private func locked(committed: String) -> DictationTranscript {
        DictationTranscript(
            dictationSessionID: session,
            snapshot: TranscriptSnapshot(committed: committed, tentative: ""),
            phase: .locked
        )
    }
}
