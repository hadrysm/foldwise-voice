import AppKit
import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class PaneNavigationPerformanceTests: XCTestCase {
    func testNavigationEndsOnlyWhenTheRequestedPaneDraws() {
        let signposts = RecordingPanePerformanceSignposts()
        var uptime = 10.0
        let performance = PaneNavigationPerformance(
            signposts: signposts,
            uptime: { uptime }
        )
        var samples: [PaneNavigationSample] = []
        performance.onNavigationSample = { samples.append($0) }

        performance.beginNavigation(to: .history)
        uptime = 10.125
        performance.firstMeaningfulFrame(for: .home)
        XCTAssertTrue(samples.isEmpty)

        uptime = 10.250
        performance.firstMeaningfulFrame(for: .history)

        XCTAssertEqual(
            samples,
            [
                PaneNavigationSample(
                    destination: .history,
                    durationMilliseconds: 250
                ),
            ]
        )
        XCTAssertEqual(
            signposts.events,
            [
                .begin(.paneNavigation, .history),
                .end(.paneNavigation, .history),
            ]
        )
    }

    func testFirstWindowUsesASeparateInterval() throws {
        let signposts = RecordingPanePerformanceSignposts()
        var uptime = 20.0
        let performance = PaneNavigationPerformance(
            signposts: signposts,
            uptime: { uptime }
        )
        var duration: Double?
        performance.onFirstWindowSample = { duration = $0 }

        performance.beginFirstWindow()
        uptime = 20.080
        performance.firstMeaningfulFrame(for: .home)

        XCTAssertEqual(try XCTUnwrap(duration), 80, accuracy: 0.000_1)
        XCTAssertEqual(
            signposts.events,
            [
                .begin(.firstWindowOpening, .home),
                .end(.firstWindowOpening, .home),
            ]
        )
    }

    func testSelectingAPaneBeginsItsNavigationInterval() {
        let signposts = RecordingPanePerformanceSignposts()
        let performance = PaneNavigationPerformance(signposts: signposts)
        let model = SettingsModel(panePerformance: performance)

        model.selectPane(.stats)

        XCTAssertEqual(model.pane, .stats)
        XCTAssertEqual(signposts.events, [.begin(.paneNavigation, .stats)])
    }

    func testSelectingTheCurrentPaneDoesNotBeginAnInterval() {
        let signposts = RecordingPanePerformanceSignposts()
        let performance = PaneNavigationPerformance(signposts: signposts)
        let model = SettingsModel(panePerformance: performance)

        model.selectPane(.home)

        XCTAssertTrue(signposts.events.isEmpty)
    }

    func testDrawMarkerCompletesThePaneIntervalAtTheAppKitBoundary() {
        let signposts = RecordingPanePerformanceSignposts()
        let performance = PaneNavigationPerformance(signposts: signposts)
        var samples: [PaneNavigationSample] = []
        performance.onNavigationSample = { samples.append($0) }
        let marker = PaneFirstMeaningfulFrameView(
            pane: .models,
            performance: performance
        )

        performance.beginNavigation(to: .models)
        marker.draw(NSRect(x: 0, y: 0, width: 1, height: 1))

        XCTAssertEqual(samples.map(\.destination), [.models])
    }
}

@MainActor
private final class RecordingPanePerformanceSignposts: PanePerformanceSignposting {
    enum Event: Equatable {
        case begin(PanePerformanceInterval, SettingsModel.Pane)
        case end(PanePerformanceInterval, SettingsModel.Pane)
    }

    private(set) var events: [Event] = []

    func begin(
        _ interval: PanePerformanceInterval,
        destination: SettingsModel.Pane
    ) -> PanePerformanceSignpostToken {
        events.append(.begin(interval, destination))
        return PanePerformanceSignpostToken()
    }

    func end(
        _ interval: PanePerformanceInterval,
        destination: SettingsModel.Pane,
        token: PanePerformanceSignpostToken
    ) {
        events.append(.end(interval, destination))
    }
}
