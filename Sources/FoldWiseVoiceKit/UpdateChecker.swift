// Update check against GitHub Releases: passively on launch and once a day
// (surfacing a menu-bar item when a newer version exists), plus on demand via
// checkNow() for the "Check for Updates" button in Settings and the menu bar.
// Never installs anything — the update button hands the .dmg download (or the
// release page) to the browser and the user drags the app in themselves.

import Foundation

@MainActor
final class UpdateChecker {
    static let latestReleaseAPI =
        URL(string: "https://api.github.com/repos/hadrysm/foldwise-voice/releases/latest")!
    static let releasesPage =
        URL(string: "https://github.com/hadrysm/foldwise-voice/releases/latest")!

    struct Release {
        let version: String
        /// Direct .dmg asset download, when the release has one.
        let dmgURL: URL?
    }

    enum CheckResult {
        case upToDate(current: String)
        case updateAvailable(version: String, downloadURL: URL?)
        /// Offline, rate-limited, or a dev build with no bundle version.
        case failed
    }

    private let client: any UpdateCheckClient
    private let scheduler: UpdateCheckScheduler
    private let onUpdateAvailable: (String) -> Void

    init(
        client: any UpdateCheckClient = LiveUpdateCheckClient(),
        scheduler: UpdateCheckScheduler = .live,
        onUpdateAvailable: @escaping (String) -> Void
    ) {
        self.client = client
        self.scheduler = scheduler
        self.onUpdateAvailable = onUpdateAvailable
    }

    /// Check now, then every 24 h for as long as the app runs.
    func start() {
        // Dev builds (`swift run`) have no Info.plist version — nothing to compare.
        guard client.currentVersion() != nil else { return }
        check()
        scheduler.scheduleDaily { [weak self] in
            Task { @MainActor in self?.check() }
        }
    }

    private func check() {
        Task { @MainActor in
            if case let .updateAvailable(version, _) = await Self.checkNow(
                client: client
            ) {
                onUpdateAvailable(version)
            }
        }
    }

    /// One immediate check with an explicit outcome, for user-initiated
    /// "Check for Updates" (the passive path reuses it and only acts on
    /// `.updateAvailable`).
    static func checkNow(
        client: any UpdateCheckClient = LiveUpdateCheckClient()
    ) async -> CheckResult {
        guard let current = client.currentVersion() else { return .failed }
        guard let release = await fetchLatestRelease(sendRequest: client.sendRequest) else {
            return .failed
        }
        return isNewer(release.version, than: current)
            ? .updateAvailable(version: release.version, downloadURL: release.dmgURL)
            : .upToDate(current: current)
    }

    static func currentVersion() -> String? {
        LiveUpdateCheckClient().currentVersion()
    }

    /// Latest release ("0.4.0" plus its .dmg asset URL), or nil if offline /
    /// rate-limited / the tag doesn't look like a version.
    static func fetchLatestRelease(sendRequest: URLLoader) async -> Release? {
        var request = URLRequest(url: latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        guard let (data, response) = try? await sendRequest(request),
              let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String
        else {
            Log.app.warning("Update check skipped an unavailable or invalid GitHub release response")
            return nil
        }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard !version.isEmpty, parse(version) != nil else {
            Log.app.warning("Update check skipped a GitHub release with a malformed version tag")
            return nil
        }
        let dmgURL = ((json["assets"] as? [[String: Any]]) ?? [])
            .compactMap { $0["browser_download_url"] as? String }
            .first { $0.hasSuffix(".dmg") }
            .flatMap(URL.init(string:))
        return Release(version: version, dmgURL: dmgURL)
    }

    /// Numeric component-wise comparison, so "0.10.0" > "0.9.0".
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = parse(candidate), let b = parse(current) else { return false }
        let count = max(a.count, b.count)
        for i in 0 ..< count {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// "1.2.3" → [1, 2, 3]; nil if any dot-component isn't a plain integer
    /// (pre-release tags like "1.2.3-rc1" are ignored rather than compared).
    private static func parse(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        var numbers: [Int] = []
        for part in parts {
            guard let n = Int(part), n >= 0 else { return nil }
            numbers.append(n)
        }
        return numbers.isEmpty ? nil : numbers
    }
}
