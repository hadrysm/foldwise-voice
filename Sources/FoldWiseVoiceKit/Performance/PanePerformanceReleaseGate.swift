import Foundation

enum PanePerformanceReleaseGate {
    struct Result: Equatable {
        let relativeViolations: [String]
        let absoluteViolations: [String]
        let missingBaselines: [String]
        let duplicateRoutes: [String]

        static let passed = Result(
            relativeViolations: [],
            absoluteViolations: [],
            missingBaselines: [],
            duplicateRoutes: []
        )
    }

    static func evaluate(
        reportData: Data,
        baselineData: Data
    ) throws -> Result {
        let report = try JSONDecoder().decode(Report.self, from: reportData)
        let baselines = try JSONDecoder().decode(Baselines.self, from: baselineData)
        guard baselines.maximumRegressionPercent <= 20 else {
            throw ValidationError.excessiveRegressionAllowance
        }

        var routes: [String: Route] = [:]
        var duplicateRoutes: Set<String> = []
        for run in report.runs {
            for route in run.routes {
                let key = [run.profile, route.destination, route.visit]
                    .joined(separator: "/")
                if routes.updateValue(route, forKey: key) != nil {
                    duplicateRoutes.insert(key)
                }
            }
        }
        let relativeViolations = baselines.routes.compactMap { key, baseline in
            guard let route = routes[key] else { return key }
            let limit = baseline.medianMilliseconds
                * (1 + baselines.maximumRegressionPercent / 100)
            return route.statistics.medianMilliseconds > limit ? key : nil
        }
        let absoluteViolations = routes.compactMap { key, route in
            route.samplesMilliseconds.contains(where: { $0 > 100 }) ? key : nil
        }
        let missingBaselines = routes.keys.filter { baselines.routes[$0] == nil }
        return Result(
            relativeViolations: relativeViolations.sorted(),
            absoluteViolations: absoluteViolations.sorted(),
            missingBaselines: missingBaselines.sorted(),
            duplicateRoutes: duplicateRoutes.sorted()
        )
    }

    private struct Report: Decodable {
        let runs: [Run]
    }

    private struct Run: Decodable {
        let profile: String
        let routes: [Route]
    }

    private struct Route: Decodable {
        let destination: String
        let visit: String
        let samplesMilliseconds: [Double]
        let statistics: Statistics
    }

    private struct Statistics: Decodable {
        let medianMilliseconds: Double
    }

    private struct Baselines: Decodable {
        let maximumRegressionPercent: Double
        let routes: [String: Baseline]
    }

    private struct Baseline: Decodable {
        let medianMilliseconds: Double
    }

    private enum ValidationError: Error {
        case excessiveRegressionAllowance
    }
}
