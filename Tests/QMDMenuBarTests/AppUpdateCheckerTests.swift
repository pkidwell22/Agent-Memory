import Foundation
import XCTest
@testable import QMDMenuBar

final class AppUpdateCheckerTests: XCTestCase {
    private let currentSHA = "1111111111111111111111111111111111111111"
    private let latestSHA = "2222222222222222222222222222222222222222"

    func testMatchingCommitIsCurrent() async throws {
        let checker = makeChecker(sha: currentSHA)

        let state = try await checker.check(currentCommit: currentSHA.uppercased())

        guard case let .current(latestBuild) = state else {
            return XCTFail("Expected the current state")
        }
        XCTAssertEqual(latestBuild, "1111111")
    }

    func testNewCommitProducesUpdatePromptDetails() async throws {
        let checker = makeChecker(sha: latestSHA, message: "Improve update prompts\n\nMore detail")

        let state = try await checker.check(currentCommit: currentSHA)

        guard case let .available(update) = state else {
            return XCTFail("Expected an available update")
        }
        XCTAssertEqual(update.identifier, latestSHA)
        XCTAssertEqual(update.displayBuild, "2222222")
        XCTAssertEqual(update.summary, "Improve update prompts")
        XCTAssertEqual(update.pageURL.absoluteString, "https://github.com/pkidwell22/Agent-Memory/commit/\(latestSHA)")
        XCTAssertEqual(
            update.publishedAt,
            ISO8601DateFormatter().date(from: "2026-07-29T23:00:00Z")
        )
    }

    func testNonSuccessResponseThrows() async {
        let checker = AppUpdateChecker { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)
            )
            return (Data(), response)
        }

        do {
            _ = try await checker.check(currentCommit: currentSHA)
            XCTFail("Expected an HTTP error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("403"))
        }
    }

    private func makeChecker(
        sha: String,
        message: String = "Latest change"
    ) -> AppUpdateChecker {
        AppUpdateChecker { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)
            )
            let json = """
            {
              "sha": "\(sha)",
              "html_url": "https://github.com/pkidwell22/Agent-Memory/commit/\(sha)",
              "commit": {
                "message": "\(message.replacingOccurrences(of: "\n", with: "\\n"))",
                "committer": {
                  "date": "2026-07-29T23:00:00Z"
                }
              }
            }
            """
            return (Data(json.utf8), response)
        }
    }
}
