import Foundation

struct PanePerformancePlan: Codable, Equatable {
    let profile: PanePerformanceProfile
    let outputURL: URL
    let dataDirectory: URL
    let sampleCount: Int
    let destinations: [SettingsModel.Pane]

    static func load(from url: URL) throws -> PanePerformancePlan {
        let plan = try JSONDecoder().decode(
            PanePerformancePlan.self,
            from: Data(contentsOf: url)
        )
        guard plan.sampleCount > 0 else {
            throw PanePerformancePlanError.invalidSampleCount
        }
        guard !plan.destinations.isEmpty,
              Set(plan.destinations).count == plan.destinations.count
        else {
            throw PanePerformancePlanError.invalidDestinations
        }
        guard plan.outputURL.isFileURL, plan.dataDirectory.isFileURL else {
            throw PanePerformancePlanError.nonFileURL
        }
        return plan
    }
}

enum PanePerformancePlanError: LocalizedError {
    case invalidSampleCount
    case invalidDestinations
    case nonFileURL

    var errorDescription: String? {
        switch self {
        case .invalidSampleCount:
            "Pane performance sample count must be greater than zero."
        case .invalidDestinations:
            "Pane performance destinations must be nonempty and unique."
        case .nonFileURL:
            "Pane performance output and data locations must be file URLs."
        }
    }
}

enum PanePerformanceVisit: String, Codable {
    case cold
    case warm
}

struct PanePerformanceStatistics: Codable, Equatable {
    let medianMilliseconds: Double
    let p95Milliseconds: Double
    let worstMilliseconds: Double

    init(samplesMilliseconds: [Double]) {
        precondition(!samplesMilliseconds.isEmpty)
        let sorted = samplesMilliseconds.sorted()
        if sorted.count.isMultiple(of: 2) {
            let upper = sorted.count / 2
            medianMilliseconds = (sorted[upper - 1] + sorted[upper]) / 2
        } else {
            medianMilliseconds = sorted[sorted.count / 2]
        }
        let p95Index = max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)
        p95Milliseconds = sorted[p95Index]
        worstMilliseconds = sorted[sorted.count - 1]
    }

    init(
        medianMilliseconds: Double,
        p95Milliseconds: Double,
        worstMilliseconds: Double
    ) {
        self.medianMilliseconds = medianMilliseconds
        self.p95Milliseconds = p95Milliseconds
        self.worstMilliseconds = worstMilliseconds
    }
}

struct PanePerformanceRouteResult: Codable, Equatable {
    let source: SettingsModel.Pane
    let destination: SettingsModel.Pane
    let visit: PanePerformanceVisit
    let samplesMilliseconds: [Double]
    let statistics: PanePerformanceStatistics

    init(
        source: SettingsModel.Pane,
        destination: SettingsModel.Pane,
        visit: PanePerformanceVisit,
        samplesMilliseconds: [Double]
    ) {
        self.source = source
        self.destination = destination
        self.visit = visit
        self.samplesMilliseconds = samplesMilliseconds
        statistics = PanePerformanceStatistics(samplesMilliseconds: samplesMilliseconds)
    }
}

struct PanePerformanceRunReport: Codable, Equatable {
    let schemaVersion: Int
    let fixtureIdentity: String
    let profile: PanePerformanceProfile
    let warmUpSamplesDiscarded: Int
    let recordedSamplesPerClass: Int
    let firstWindowMilliseconds: Double
    let routes: [PanePerformanceRouteResult]

    init(
        fixtureIdentity: String,
        profile: PanePerformanceProfile,
        recordedSamplesPerClass: Int,
        firstWindowMilliseconds: Double,
        routes: [PanePerformanceRouteResult]
    ) {
        schemaVersion = 1
        self.fixtureIdentity = fixtureIdentity
        self.profile = profile
        warmUpSamplesDiscarded = 1
        self.recordedSamplesPerClass = recordedSamplesPerClass
        self.firstWindowMilliseconds = firstWindowMilliseconds
        self.routes = routes
    }

    func write(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
