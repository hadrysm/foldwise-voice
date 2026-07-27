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
    let startedAtSystemUptime: TimeInterval
    let endedAtSystemUptime: TimeInterval
    let startedAtEpoch: TimeInterval
    let endedAtEpoch: TimeInterval
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
        let startedAtEpoch: TimeInterval
        let token: PanePerformanceSignpostToken
    }

    private let signposts: any PanePerformanceSignposting
    private let uptime: () -> TimeInterval
    private let wallClock: () -> TimeInterval
    private var pendingNavigation: Pending?
    private var pendingFirstWindow: Pending?

    init(
        signposts: (any PanePerformanceSignposting)? = nil,
        uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        wallClock: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }
    ) {
        self.signposts = signposts ?? OSSPanePerformanceSignposts()
        self.uptime = uptime
        self.wallClock = wallClock
    }

    func beginNavigation(to destination: SettingsModel.Pane) {
        let startedAtEpoch = wallClock()
        pendingNavigation = Pending(
            destination: destination,
            startedAt: uptime(),
            startedAtEpoch: startedAtEpoch,
            token: signposts.begin(.paneNavigation, destination: destination)
        )
    }

    func beginFirstWindow() {
        guard pendingFirstWindow == nil else { return }
        pendingFirstWindow = Pending(
            destination: .home,
            startedAt: uptime(),
            startedAtEpoch: wallClock(),
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
            let endedAt = uptime()
            let endedAtEpoch = wallClock()
            onNavigationSample?(PaneNavigationSample(
                destination: destination,
                durationMilliseconds: elapsedMilliseconds(
                    from: pendingNavigation.startedAt,
                    to: endedAt
                ),
                startedAtSystemUptime: pendingNavigation.startedAt,
                endedAtSystemUptime: endedAt,
                startedAtEpoch: pendingNavigation.startedAtEpoch,
                endedAtEpoch: endedAtEpoch
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
        elapsedMilliseconds(from: start, to: uptime())
    }

    private func elapsedMilliseconds(
        from start: TimeInterval,
        to end: TimeInterval
    ) -> Double {
        max(0, end - start) * 1000
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
