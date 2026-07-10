import Foundation
import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class UpdateCheckerFlowTests: XCTestCase {
    func testStartReportsAvailableUpdate() async throws {
        let response = try httpResponse(statusCode: 200)
        let reported = expectation(description: "available version reported")
        var reportedVersion: String?
        let checker = UpdateChecker(
            client: UpdateCheckClient(
                currentVersion: { "1.2.3" },
                sendRequest: { _ in (Data(#"{"tag_name":"v1.3.0"}"#.utf8), response) }
            ),
            scheduler: UpdateCheckScheduler { _ in }
        ) { version in
            reportedVersion = version
            reported.fulfill()
        }

        checker.start()
        await fulfillment(of: [reported], timeout: 1)

        XCTAssertEqual(reportedVersion, "1.3.0")
    }

    func testScheduledCheckRepeatsUpdateReporting() async throws {
        let response = try httpResponse(statusCode: 200)
        let reported = expectation(description: "available version reported twice")
        reported.expectedFulfillmentCount = 2
        var scheduledCheck: (() -> Void)?
        let checker = UpdateChecker(
            client: UpdateCheckClient(
                currentVersion: { "1.2.3" },
                sendRequest: { _ in (Data(#"{"tag_name":"v1.3.0"}"#.utf8), response) }
            ),
            scheduler: UpdateCheckScheduler { scheduledCheck = $0 }
        ) { _ in reported.fulfill() }

        checker.start()
        scheduledCheck?()
        await fulfillment(of: [reported], timeout: 1)
    }

    func testStartDoesNothingWithoutCurrentVersion() {
        var effects: [String] = []
        let checker = UpdateChecker(
            client: UpdateCheckClient(
                currentVersion: { nil },
                sendRequest: { _ in
                    effects.append("request")
                    throw URLError(.unknown)
                }
            ),
            scheduler: UpdateCheckScheduler { _ in effects.append("schedule") }
        ) { _ in effects.append("report") }

        checker.start()

        XCTAssertEqual(effects, [])
    }

    func testCheckNowReportsCurrentVersionWhenLatestReleaseMatches() async throws {
        let response = try httpResponse(statusCode: 200)

        let result = await checkNow(currentVersion: "1.2.3") { _ in
            (Data(#"{"tag_name":"v1.2.3"}"#.utf8), response)
        }

        guard case let .upToDate(current) = result else {
            return XCTFail("Expected up-to-date result, got \(result)")
        }
        XCTAssertEqual(current, "1.2.3")
    }

    func testCheckNowReportsNewReleaseAndDMGDownload() async throws {
        let response = try httpResponse(statusCode: 200)
        let payload = Data(
            #"{"tag_name":"v1.3.0","assets":[{"browser_download_url":"https://example.com/readme.txt"},{"browser_download_url":"https://example.com/FoldWise.dmg"}]}"#
                .utf8
        )

        let result = await checkNow(currentVersion: "1.2.3") { _ in
            (payload, response)
        }

        guard case let .updateAvailable(version, downloadURL) = result else {
            return XCTFail("Expected available update, got \(result)")
        }
        XCTAssertEqual(
            [version, downloadURL?.absoluteString],
            ["1.3.0", "https://example.com/FoldWise.dmg"]
        )
    }

    func testCheckNowFailsWithoutCurrentVersion() async throws {
        let response = try httpResponse(statusCode: 200)

        let result = await checkNow(currentVersion: nil) { _ in
            (Data(#"{"tag_name":"v1.3.0"}"#.utf8), response)
        }

        guard case .failed = result else {
            return XCTFail("Expected missing version to fail, got \(result)")
        }
    }

    func testCheckNowFailsForUnsuccessfulStatus() async throws {
        let response = try httpResponse(statusCode: 403)

        let result = await checkNow(currentVersion: "1.2.3") { _ in
            (Data(#"{"tag_name":"v1.3.0"}"#.utf8), response)
        }

        guard case .failed = result else {
            return XCTFail("Expected unsuccessful status to fail, got \(result)")
        }
    }

    func testCheckNowFailsForInvalidPayload() async throws {
        let response = try httpResponse(statusCode: 200)

        let result = await checkNow(currentVersion: "1.2.3") { _ in
            (Data("not-json".utf8), response)
        }

        guard case .failed = result else {
            return XCTFail("Expected invalid payload to fail, got \(result)")
        }
    }

    func testCheckNowFailsWhenTagNameIsMissing() async throws {
        let response = try httpResponse(statusCode: 200)

        let result = await checkNow(currentVersion: "1.2.3") { _ in
            (Data(#"{"name":"FoldWise 1.3.0"}"#.utf8), response)
        }

        guard case .failed = result else {
            return XCTFail("Expected missing tag to fail, got \(result)")
        }
    }

    func testCheckNowFailsWhenTagIsMalformed() async throws {
        let response = try httpResponse(statusCode: 200)

        let result = await checkNow(currentVersion: "1.2.3") { _ in
            (Data(#"{"tag_name":"release-next"}"#.utf8), response)
        }

        guard case .failed = result else {
            return XCTFail("Expected malformed tag to fail, got \(result)")
        }
    }

    func testCheckNowFailsWhenTransportThrows() async {
        let result = await checkNow(currentVersion: "1.2.3") { _ in
            throw URLError(.notConnectedToInternet)
        }

        guard case .failed = result else {
            return XCTFail("Expected transport failure, got \(result)")
        }
    }

    func testCheckNowSendsTheGitHubReleaseRequestContract() async throws {
        let response = try httpResponse(statusCode: 200)
        var capturedRequest: URLRequest?

        _ = await checkNow(currentVersion: "1.2.3") { request in
            capturedRequest = request
            return (Data(#"{"tag_name":"v1.2.3"}"#.utf8), response)
        }

        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(
            [
                request.url?.absoluteString,
                request.value(forHTTPHeaderField: "Accept"),
                String(request.timeoutInterval),
            ],
            [
                "https://api.github.com/repos/hadrysm/foldwise-voice/releases/latest",
                "application/vnd.github+json",
                "10.0",
            ]
        )
    }

    private func httpResponse(statusCode: Int) throws -> HTTPURLResponse {
        try XCTUnwrap(
            HTTPURLResponse(
                url: UpdateChecker.latestReleaseAPI,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )
        )
    }

    private func checkNow(
        currentVersion: String?,
        sendRequest: @escaping UpdateChecker.URLLoader
    ) async -> UpdateChecker.CheckResult {
        await UpdateChecker.checkNow(
            client: UpdateCheckClient(
                currentVersion: { currentVersion },
                sendRequest: sendRequest
            )
        )
    }
}
