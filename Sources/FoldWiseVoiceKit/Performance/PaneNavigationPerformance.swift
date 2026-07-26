import Foundation
import os

enum PanePerformanceInterval: Equatable {
    case paneNavigation
    case firstWindowOpening
}

struct PanePerformanceSignpostToken: Hashable {
    fileprivate let value: UUID

    init() {
        value = UUID()
    }
}

@MainActor
protocol PanePerformanceSignposting: AnyObject {
    func begin(
        _ interval: PanePerformanceInterval,
        destination: SettingsModel.Pane
    ) -> PanePerformanceSignpostToken

    func end(
        _ interval: PanePerformanceInterval,
        destination: SettingsModel.Pane,
        token: PanePerformanceSignpostToken
    )
}

struct PaneNavigationSample: Equatable {
    let destination: SettingsModel.Pane
    let durationMilliseconds: Double
}

@MainActor
final class PaneNavigationPerformance {
    static let subsystem = "com.foldwise.voice"
    static let category = "PanePerformance"
    static let paneNavigationIntervalName = "PaneNavigation"
    static let firstWindowIntervalName = "FirstWindowOpening"

    var onNavigationSample: ((PaneNavigationSample) -> Void)?
    var onFirstWindowSample: ((Double) -> Void)?
    var onFirstMeaningfulFrame: ((SettingsModel.Pane) -> Void)?

    private struct Pending {
        let destination: SettingsModel.Pane
        let startedAt: TimeInterval
        let token: PanePerformanceSignpostToken
    }

    private let signposts: any PanePerformanceSignposting
    private let uptime: () -> TimeInterval
    private var pendingNavigation: Pending?
    private var pendingFirstWindow: Pending?

    init(
        signposts: (any PanePerformanceSignposting)? = nil,
        uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.signposts = signposts ?? OSSPanePerformanceSignposts()
        self.uptime = uptime
    }

    func beginNavigation(to destination: SettingsModel.Pane) {
        pendingNavigation = Pending(
            destination: destination,
            startedAt: uptime(),
            token: signposts.begin(.paneNavigation, destination: destination)
        )
    }

    func beginFirstWindow() {
        guard pendingFirstWindow == nil else { return }
        pendingFirstWindow = Pending(
            destination: .home,
            startedAt: uptime(),
            token: signposts.begin(.firstWindowOpening, destination: .home)
        )
    }

    func firstMeaningfulFrame(for destination: SettingsModel.Pane) {
        onFirstMeaningfulFrame?(destination)
        if let pendingNavigation, pendingNavigation.destination == destination {
            self.pendingNavigation = nil
            signposts.end(
                .paneNavigation,
                destination: destination,
                token: pendingNavigation.token
            )
            onNavigationSample?(PaneNavigationSample(
                destination: destination,
                durationMilliseconds: elapsedMilliseconds(since: pendingNavigation.startedAt)
            ))
        }
        if let pendingFirstWindow, pendingFirstWindow.destination == destination {
            self.pendingFirstWindow = nil
            signposts.end(
                .firstWindowOpening,
                destination: destination,
                token: pendingFirstWindow.token
            )
            onFirstWindowSample?(elapsedMilliseconds(since: pendingFirstWindow.startedAt))
        }
    }

    private func elapsedMilliseconds(since start: TimeInterval) -> Double {
        max(0, uptime() - start) * 1000
    }
}

@MainActor
private final class OSSPanePerformanceSignposts: PanePerformanceSignposting {
    private let signposter = OSSignposter(
        subsystem: PaneNavigationPerformance.subsystem,
        category: PaneNavigationPerformance.category
    )
    private var states: [PanePerformanceSignpostToken: OSSignpostIntervalState] = [:]

    func begin(
        _ interval: PanePerformanceInterval,
        destination: SettingsModel.Pane
    ) -> PanePerformanceSignpostToken {
        let token = PanePerformanceSignpostToken()
        let id = signposter.makeSignpostID()
        let state = switch interval {
        case .paneNavigation:
            signposter.beginInterval("PaneNavigation", id: id)
        case .firstWindowOpening:
            signposter.beginInterval("FirstWindowOpening", id: id)
        }
        states[token] = state
        return token
    }

    func end(
        _ interval: PanePerformanceInterval,
        destination: SettingsModel.Pane,
        token: PanePerformanceSignpostToken
    ) {
        guard let state = states.removeValue(forKey: token) else { return }
        switch interval {
        case .paneNavigation:
            signposter.endInterval("PaneNavigation", state)
        case .firstWindowOpening:
            signposter.endInterval("FirstWindowOpening", state)
        }
    }
}
