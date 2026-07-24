import XCTest
@testable import FoldWiseVoiceKit

final class ThemeEnvironmentTests: XCTestCase {
    func testCanonicalGeometryMatchesEmberEdgeRhythm() {
        XCTAssertEqual(
            [
                Theme.spacingUnit,
                Theme.surfaceRadius,
                Theme.controlRadius,
                Theme.standardBorderWidth,
                Theme.increasedContrastBorderWidth,
                Theme.selectionIngressWidth,
                Theme.noticeIngressWidth,
                Theme.focusRingWidth,
                Theme.focusGap,
            ],
            [4, 8, 6, 1, 2, 2, 3, 2, 2]
        )
        XCTAssertEqual(Theme.spacingRhythm, [4, 8, 12, 16, 20, 24, 28, 32, 36])
    }

    func testCanonicalTypographyTrackingMatchesEmberEdgeRoles() {
        XCTAssertEqual(
            [Theme.displayTracking, Theme.sectionTracking],
            [-0.5, 0.7]
        )
        XCTAssertEqual(
            [
                ThemeTypographyPolicy.display,
                ThemeTypographyPolicy.section,
                ThemeTypographyPolicy.body,
                ThemeTypographyPolicy.data,
                ThemeTypographyPolicy.compactData,
            ],
            [
                ThemeTypographyRole(
                    size: 30, weight: .semibold, isMonospaced: false, tracking: -0.5
                ),
                ThemeTypographyRole(
                    size: 11, weight: .bold, isMonospaced: false, tracking: 0.7
                ),
                ThemeTypographyRole(
                    size: 13.5, weight: .regular, isMonospaced: false, tracking: 0
                ),
                ThemeTypographyRole(
                    size: 11, weight: .medium, isMonospaced: true, tracking: 0
                ),
                ThemeTypographyRole(
                    size: 10.5, weight: .medium, isMonospaced: true, tracking: 0
                ),
            ]
        )
    }

    func testIncreaseContrastSelectsStrongBoundaryWithoutChangingGeometry() {
        XCTAssertEqual(
            [
                ThemeEnvironmentPolicy.boundary(increaseContrast: false).width,
                ThemeEnvironmentPolicy.boundary(increaseContrast: true).width,
                ThemeEnvironmentPolicy.boundary(increaseContrast: false).layoutWidth,
                ThemeEnvironmentPolicy.boundary(increaseContrast: true).layoutWidth,
                Theme.surfaceRadius,
                Theme.surfaceRadius,
            ],
            [1, 2, 1, 1, 8, 8]
        )
        XCTAssertEqual(
            [
                ThemeEnvironmentPolicy.boundary(increaseContrast: false),
                ThemeEnvironmentPolicy.boundary(increaseContrast: true),
            ],
            [.standard, .strong]
        )
    }

    func testReduceMotionMakesOrdinaryTransitionsImmediate() {
        XCTAssertEqual(ThemeEnvironmentPolicy.ordinaryMotionDuration(reduceMotion: false), 0.16)
        XCTAssertNil(ThemeEnvironmentPolicy.ordinaryMotionDuration(reduceMotion: true))
    }

    func testWideDestinationsUseCanonicalWidePadding() {
        XCTAssertEqual(
            ThemeLayoutPolicy.destinationPadding(windowWidth: Theme.homeCompactBreakpoint),
            Theme.contentPaddingWide
        )
    }

    func testCompactDestinationsUseCanonicalCompactPadding() {
        XCTAssertEqual(
            ThemeLayoutPolicy.destinationPadding(windowWidth: Theme.homeCompactBreakpoint - 1),
            Theme.contentPaddingCompact
        )
    }
}
