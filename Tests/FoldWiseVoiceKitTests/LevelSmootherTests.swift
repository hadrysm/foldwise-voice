// The ribbon amplitude mapping (PRD #103): RMS samples smoothed over ~100ms
// and always landing inside the spec's [0.10, 0.45] window.

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

    func testStepInputReachesRoughlyTwoThirdsAfterOneTimeConstant() {
        var smoother = LevelSmoother(timeConstant: 0.1)
        smoother.add(rms: 0.1, dt: 0.1)
        XCTAssertEqual(smoother.smoothed, 0.1 * (1 - exp(-1)), accuracy: 0.0001)
    }

    func testSmoothingAccumulatesTowardTheInputAcrossSamples() {
        var smoother = LevelSmoother(timeConstant: 0.1)
        for _ in 0 ..< 30 {
            smoother.add(rms: 0.2, dt: 0.033)
        }
        XCTAssertEqual(smoother.smoothed, 0.2, accuracy: 0.005)
    }

    func testNegativeRMSClampsToSilence() {
        var smoother = LevelSmoother()
        smoother.add(rms: -1, dt: 0.033)
        XCTAssertEqual(smoother.amplitude, 0.10, accuracy: 0.0001)
    }

    func testNonPositiveDTAdoptsTheSampleOutright() {
        var smoother = LevelSmoother()
        smoother.add(rms: 0.05, dt: 0)
        XCTAssertEqual(smoother.smoothed, 0.05, accuracy: 0.0001)
    }

    func testResetReturnsToTheFloor() {
        var smoother = LevelSmoother()
        smoother.add(rms: 1, dt: 1)
        smoother.reset()
        XCTAssertEqual(smoother.amplitude, 0.10, accuracy: 0.0001)
    }
}
