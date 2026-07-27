import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class PanePerformanceWindowPresenterTests: XCTestCase {
    func testPresentOrdersWindowWithoutRequestingKeyStatus() {
        let window = RecordingPanePerformanceWindow()

        PanePerformanceWindowPresenter.present(window)

        XCTAssertEqual(window.events, [.orderFrontRegardless, .displayIfNeeded])
    }
}

@MainActor
private final class RecordingPanePerformanceWindow: PanePerformanceWindowPresenting {
    enum Event: Equatable {
        case orderFrontRegardless
        case displayIfNeeded
    }

    private(set) var events: [Event] = []

    func orderFrontRegardless() {
        events.append(.orderFrontRegardless)
    }

    func displayIfNeeded() {
        events.append(.displayIfNeeded)
    }
}
