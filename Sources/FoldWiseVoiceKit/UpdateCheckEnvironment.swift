import Foundation

struct UpdateCheckClient {
    let currentVersion: () -> String?
    let sendRequest: UpdateChecker.URLLoader

    static let live = UpdateCheckClient(
        currentVersion: {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        },
        sendRequest: { request in try await URLSession.shared.data(for: request) }
    )
}

struct UpdateCheckScheduler {
    let scheduleDaily: (@escaping () -> Void) -> Void

    static let live = UpdateCheckScheduler { action in
        let timer = Timer(timeInterval: 24 * 60 * 60, repeats: true) { _ in action() }
        timer.tolerance = 60 * 60
        RunLoop.main.add(timer, forMode: .common)
    }
}
