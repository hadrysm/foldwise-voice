// Passive update check against GitHub Releases: on launch and once a day,
// compare the bundle version with the latest release tag and surface a
// menu-bar item when a newer version exists. Never downloads anything —
// the user opens the release page and grabs the .dmg themselves.

import Foundation

@MainActor
final class UpdateChecker {
    static let latestReleaseAPI =
        URL(string: "https://api.github.com/repos/hadrysm/foldwise-voice/releases/latest")!
    static let releasesPage =
        URL(string: "https://github.com/hadrysm/foldwise-voice/releases/latest")!

    private let onUpdateAvailable: (String) -> Void
    private var timer: Timer?

    init(onUpdateAvailable: @escaping (String) -> Void) {
        self.onUpdateAvailable = onUpdateAvailable
    }

    /// Check now, then every 24 h for as long as the app runs.
    func start() {
        // Dev builds (`swift run`) have no Info.plist version — nothing to compare.
        guard Self.currentVersion() != nil else { return }
        check()
        let timer = Timer(timeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        timer.tolerance = 60 * 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func check() {
        guard let current = Self.currentVersion() else { return }
        Task {
            guard let latest = await Self.fetchLatestVersion() else { return }
            if Self.isNewer(latest, than: current) {
                onUpdateAvailable(latest)
            }
        }
    }

    static func currentVersion() -> String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// Latest release version ("0.4.0"), or nil if offline / rate-limited /
    /// the tag doesn't look like a version. Failures are silent by design.
    static func fetchLatestVersion() async -> String? {
        var request = URLRequest(url: latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tag = json["tag_name"] as? String
        else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return version.isEmpty || parse(version) == nil ? nil : version
    }

    /// Numeric component-wise comparison, so "0.10.0" > "0.9.0".
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = parse(candidate), let b = parse(current) else { return false }
        let count = max(a.count, b.count)
        for i in 0..<count {
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
