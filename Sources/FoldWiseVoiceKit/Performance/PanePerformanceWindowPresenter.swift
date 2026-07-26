import AppKit

@MainActor
protocol PanePerformanceWindowPresenting {
    func orderFrontRegardless()
    func displayIfNeeded()
}

extension NSWindow: PanePerformanceWindowPresenting {}

@MainActor
enum PanePerformanceWindowPresenter {
    static func present(_ window: some PanePerformanceWindowPresenting) {
        window.orderFrontRegardless()
        window.displayIfNeeded()
    }
}
