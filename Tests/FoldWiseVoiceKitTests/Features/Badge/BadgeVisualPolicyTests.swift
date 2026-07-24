import XCTest
@testable import FoldWiseVoiceKit

final class BadgeVisualPolicyTests: XCTestCase {
    func testPrimaryStatesKeepTheirSemanticRoleAndPersistentCue() {
        XCTAssertEqual(
            [
                BadgeVisualPolicy.presentation(for: .idle, presentsModeCycle: false),
                BadgeVisualPolicy.presentation(for: .hover, presentsModeCycle: false),
                BadgeVisualPolicy.presentation(for: .recording, presentsModeCycle: false),
                BadgeVisualPolicy.presentation(
                    for: .working(status: nil),
                    presentsModeCycle: false
                ),
                BadgeVisualPolicy.presentation(for: .done, presentsModeCycle: false),
                BadgeVisualPolicy.presentation(
                    for: .error(message: "something went wrong"),
                    presentsModeCycle: false
                ),
            ],
            [
                BadgeVisualPresentation(role: .neutral, cue: .idleGlyph),
                BadgeVisualPresentation(role: .neutral, cue: .hoverActions),
                BadgeVisualPresentation(role: .active, cue: .ribbonsAndTimer),
                BadgeVisualPresentation(role: .active, cue: .ribbonsAndSpinner),
                BadgeVisualPresentation(role: .success, cue: .checkmarkAndText),
                BadgeVisualPresentation(role: .error, cue: .warningAndText),
            ]
        )
    }

    func testWorkingStatusKeepsWaveformAndTextCue() {
        XCTAssertEqual(
            BadgeVisualPolicy.presentation(
                for: .working(status: "downloading 45%"),
                presentsModeCycle: false
            ),
            BadgeVisualPresentation(role: .active, cue: .ribbonsAndStatus)
        )
    }

    func testModeCycleUsesActiveRoleAndSelectionCue() {
        XCTAssertEqual(
            BadgeVisualPolicy.presentation(for: .idle, presentsModeCycle: true),
            BadgeVisualPresentation(role: .active, cue: .modeSelection)
        )
    }

    func testStandardMotionAnimatesOrdinaryPresentation() {
        let motion = BadgeMotionPolicy.presentation(reduceMotion: false)

        XCTAssertEqual(
            motion,
            BadgeMotionPresentation(
                ordinaryTransitionDuration: 0.16,
                emphasizedHoverScale: 1.06,
                pausesDecorativeTimelines: false,
                representativeTimelineTime: nil,
                representativeRecordingAmplitude: nil
            )
        )
    }

    func testStandardMotionSamplesLiveAndCalmRibbonAmplitude() {
        let motion = BadgeMotionPolicy.presentation(reduceMotion: false)

        XCTAssertEqual(
            [
                motion.ribbonAmplitude(live: true, sampledAmplitude: 0.41),
                motion.ribbonAmplitude(live: false, sampledAmplitude: 0.41),
            ],
            [0.41, 0.18]
        )
    }

    func testReduceMotionFreezesDecorativePresentation() {
        let motion = BadgeMotionPolicy.presentation(reduceMotion: true)

        XCTAssertEqual(
            motion,
            BadgeMotionPresentation(
                ordinaryTransitionDuration: nil,
                emphasizedHoverScale: 1,
                pausesDecorativeTimelines: true,
                representativeTimelineTime: 730,
                representativeRecordingAmplitude: 0.28
            )
        )
    }

    func testReduceMotionUsesRepresentativeLiveAndCalmRibbonAmplitude() {
        let motion = BadgeMotionPolicy.presentation(reduceMotion: true)

        XCTAssertEqual(
            [
                motion.ribbonAmplitude(live: true, sampledAmplitude: 0.41),
                motion.ribbonAmplitude(live: false, sampledAmplitude: 0.41),
            ],
            [0.28, 0.18]
        )
    }
}
