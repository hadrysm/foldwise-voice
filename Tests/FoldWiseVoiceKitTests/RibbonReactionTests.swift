// The user-visible SIZE of the ribbon's voice reaction (QA 2026-07-09: "the
// amplitude reacts but the effect is very small"). The recording canvas is
// 20pt tall and a strand's centre deflection is height × amplitude, so the
// amplitude IS the visual effect: 0.45 fills the canvas, 0.10 is the idle
// floor. These traces use the repo's mic calibration (room noise RMS ~0.003,
// close-mic syllables ~0.05) and assert real voices produce a big reaction.

import XCTest
@testable import FoldWiseVoiceKit

final class RibbonReactionTests: XCTestCase {
    /// Feed alternating 400ms talk/gap blocks at 30 Hz and report the
    /// steady-state amplitude swing (the first talk+gap cycle is warm-up).
    private func speechSwing(talk: Double, gap: Double) -> (peak: Double, trough: Double) {
        var smoother = LevelSmoother()
        var peak = 0.0
        var trough = 1.0
        for block in 0 ..< 8 {
            let rms = block.isMultiple(of: 2) ? talk : gap
            for _ in 0 ..< 12 {
                let amplitude = smoother.add(rms: rms, dt: 1.0 / 30.0)
                guard block >= 2 else { continue }
                peak = max(peak, amplitude)
                trough = min(trough, amplitude)
            }
        }
        return (peak, trough)
    }

    func testNormalSpeechFillsMostOfTheCanvas() {
        // RMS 0.03 ≈ -30 dBFS: conversational voice at arm's length, a touch
        // under the close-mic 0.05 calibration. Syllables should push the
        // strand band to at least 80% of the canvas height.
        let swing = speechSwing(talk: 0.03, gap: 0.005)
        XCTAssertGreaterThanOrEqual(
            swing.peak, 0.40,
            "normal speech should peak the ribbon near the full canvas"
        )
    }

    func testQuietSpeechIsStillClearlyVisible() {
        // RMS 0.012 ≈ -38 dBFS: a soft voice or a low input gain. The band
        // should still reach at least half the canvas — clearly more than
        // the idle floor's 20%.
        let swing = speechSwing(talk: 0.012, gap: 0.003)
        XCTAssertGreaterThanOrEqual(
            swing.peak, 0.25,
            "quiet speech should still lift the ribbon to half the canvas"
        )
    }

    func testTalkGapSwingIsObvious() {
        // The reaction people actually read is the CHANGE between syllables
        // and the gaps between words: the band should swing by at least 40%
        // of the canvas (amplitude delta 0.20 → 8pt of 20pt) each cadence.
        let swing = speechSwing(talk: 0.03, gap: 0.005)
        XCTAssertGreaterThanOrEqual(
            swing.peak - swing.trough, 0.20,
            "talk→gap should swing the band by ≥40% of the canvas"
        )
    }
}
