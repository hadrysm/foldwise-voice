// The ribbon amplitude mapping (PRD #103): RMS samples mapped through the
// speech dB window and an attack/release envelope, always landing inside the
// spec's [0.10, 0.45] window.

import XCTest
@testable import FoldWiseVoiceKit

final class LevelSmootherTests: XCTestCase {
    func testSilenceRestsAtTheAmplitudeFloor() {
        var smoother = LevelSmoother()
        smoother.add(rms: 0, dt: 0.033)
        XCTAssertEqual(smoother.amplitude, 0.10, accuracy: 0.0001)
    }

    func testLoudInputIsCappedAtTheCeiling() {
        var smoother = LevelSmoother()
        smoother.add(rms: 5.0, dt: 10) // huge sample, long dt — fully adopted
        XCTAssertEqual(smoother.amplitude, 0.45, accuracy: 0.001)
    }

    func testOnsetReachesRoughlyTwoThirdsAfterOneAttackConstant() {
        var smoother = LevelSmoother(attack: 0.1, release: 0.3)
        smoother.add(rms: 0.2, dt: 0.1) // 0.2 RMS is above dbLoud → loudness 1
        XCTAssertEqual(smoother.envelope, 1 - exp(-1), accuracy: 0.0001)
    }

    func testReleaseDecaysSlowerThanAttackRises() {
        var smoother = LevelSmoother(attack: 0.05, release: 0.25)
        smoother.add(rms: 0.2, dt: 0.05) // one attack constant up from 0
        let risen = smoother.envelope
        smoother.add(rms: 0, dt: 0.05) // the same dt back toward silence
        let dropped = risen - smoother.envelope
        XCTAssertGreaterThan(risen, dropped, "decay should trail the onset")
    }

    func testSmoothingAccumulatesTowardTheInputAcrossSamples() {
        var smoother = LevelSmoother()
        for _ in 0 ..< 30 {
            smoother.add(rms: 0.2, dt: 0.033)
        }
        XCTAssertEqual(smoother.envelope, 1.0, accuracy: 0.005)
    }

    func testNegativeRMSClampsToSilence() {
        var smoother = LevelSmoother()
        smoother.add(rms: -1, dt: 0.033)
        XCTAssertEqual(smoother.amplitude, 0.10, accuracy: 0.0001)
    }

    func testNonPositiveDTAdoptsTheSampleOutright() {
        var smoother = LevelSmoother()
        smoother.add(rms: 0.2, dt: 0) // loudness 1; partial smoothing would fall short
        XCTAssertEqual(smoother.envelope, 1.0, accuracy: 0.0001)
    }

    func testResetReturnsToTheFloor() {
        var smoother = LevelSmoother()
        smoother.add(rms: 1, dt: 1)
        smoother.reset()
        XCTAssertEqual(smoother.amplitude, 0.10, accuracy: 0.0001)
    }

    /// Regression for the "ribbon ignores my voice" bug: normal speech at a
    /// Mac mic is RMS ~0.05 on syllables and ~0.005 in the gaps between
    /// words. That real signal must sweep most of the amplitude window —
    /// peaks into the upper half, gaps falling back toward the floor —
    /// otherwise the ribbon looks like a canned animation.
    func testTypicalSpeechSweepsTheAmplitudeWindow() {
        var smoother = LevelSmoother()
        var peak = 0.0
        var trough = 1.0
        for block in 0 ..< 6 {
            let rms = block.isMultiple(of: 2) ? 0.05 : 0.005 // 400ms talk, 400ms gap
            for _ in 0 ..< 12 {
                let amplitude = smoother.add(rms: rms, dt: 1.0 / 30.0)
                guard block >= 2 else { continue } // skip attack warm-up
                peak = max(peak, amplitude)
                trough = min(trough, amplitude)
            }
        }
        let window = LevelSmoother.ceiling - LevelSmoother.floor
        XCTAssertGreaterThanOrEqual(
            peak, LevelSmoother.floor + 0.6 * window,
            "syllables should push the ribbon into the upper half of its window"
        )
        XCTAssertLessThanOrEqual(
            trough, LevelSmoother.floor + 0.35 * window,
            "gaps between words should let the ribbon fall back"
        )
    }
}
