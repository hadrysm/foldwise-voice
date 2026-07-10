import Foundation

typealias URLLoader = (URLRequest) async throws -> (Data, URLResponse)

protocol UpdateCheckClient {
    var currentVersion: () -> String? { get }
    var sendRequest: URLLoader { get }
}

struct LiveUpdateCheckClient: UpdateCheckClient {
    let currentVersion: () -> String? = { Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String }
    let sendRequest: URLLoader = { request in try await URLSession.shared.data(for: request) }
}

struct UpdateCheckScheduler {
    let scheduleDaily: (@escaping () -> Void) -> Void

    static let live = UpdateCheckScheduler { action in
        let timer = Timer(timeInterval: 24 * 60 * 60, repeats: true) { _ in action() }
        timer.tolerance = 60 * 60
        RunLoop.main.add(timer, forMode: .common)
    }
}
