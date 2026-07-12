// The sidebar rule's contract (PRD #103): auto-collapse under a narrow window
// is transient and never writes the preference; an explicit toggle always
// wins and persists.

import XCTest
@testable import FoldWiseVoiceKit

final class SidebarPresentationTests: XCTestCase {
    private let wide = SidebarPresentation.autoCollapseWidth + 60
    private let narrow = SidebarPresentation.autoCollapseWidth - 60

    func testWideWindowFollowsExpandedPreference() {
        let sidebar = SidebarPresentation(prefersCollapsed: false)
        XCTAssertEqual(sidebar.mode(forWidth: wide), .expanded)
    }

    func testWideWindowFollowsCollapsedPreference() {
        let sidebar = SidebarPresentation(prefersCollapsed: true)
        XCTAssertEqual(sidebar.mode(forWidth: wide), .rail)
    }

    func testNarrowWindowAutoCollapsesWithoutTouchingPreference() {
        var sidebar = SidebarPresentation(prefersCollapsed: false)
        sidebar.widthChanged(to: narrow)
        XCTAssertEqual(sidebar.mode(forWidth: narrow), .rail)
        XCTAssertFalse(sidebar.prefersCollapsed)
    }

    func testWideningRestoresTheExpandedPreference() {
        var sidebar = SidebarPresentation(prefersCollapsed: false)
        sidebar.widthChanged(to: narrow)
        sidebar.widthChanged(to: wide)
        XCTAssertEqual(sidebar.mode(forWidth: wide), .expanded)
    }

    func testToggleWhileWideCollapsesAndPersists() {
        var sidebar = SidebarPresentation(prefersCollapsed: false)
        sidebar.toggle(width: wide)
        XCTAssertEqual(sidebar.mode(forWidth: wide), .rail)
        XCTAssertTrue(sidebar.prefersCollapsed)
    }

    func testToggleWhileWideExpandsAndPersists() {
        var sidebar = SidebarPresentation(prefersCollapsed: true)
        sidebar.toggle(width: wide)
        XCTAssertEqual(sidebar.mode(forWidth: wide), .expanded)
        XCTAssertFalse(sidebar.prefersCollapsed)
    }

    func testExplicitExpandBeatsAutoCollapseWhileNarrow() {
        var sidebar = SidebarPresentation(prefersCollapsed: false)
        sidebar.widthChanged(to: narrow) // auto-collapsed to the rail
        sidebar.toggle(width: narrow) // the user insists on the full sidebar
        XCTAssertEqual(sidebar.mode(forWidth: narrow), .expanded)
        XCTAssertFalse(sidebar.prefersCollapsed)
    }

    func testNarrowOverrideClearsOnceTheWindowIsWideAgain() {
        var sidebar = SidebarPresentation(prefersCollapsed: false)
        sidebar.toggle(width: narrow) // explicit expand while narrow
        sidebar.widthChanged(to: wide) // override disarms
        sidebar.widthChanged(to: narrow)
        XCTAssertEqual(sidebar.mode(forWidth: narrow), .rail)
    }

    func testToggleWhileNarrowAndOverriddenCollapsesAndPersists() {
        var sidebar = SidebarPresentation(prefersCollapsed: false)
        sidebar.toggle(width: narrow) // explicit expand while narrow
        sidebar.toggle(width: narrow) // and back
        XCTAssertEqual(sidebar.mode(forWidth: narrow), .rail)
        XCTAssertTrue(sidebar.prefersCollapsed)
    }
}
