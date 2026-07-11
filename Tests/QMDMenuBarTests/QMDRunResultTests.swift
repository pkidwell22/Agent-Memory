import XCTest
@testable import QMDMenuBar

final class QMDRunResultTests: XCTestCase {
    func testPersistedSummaryExcludesUnboundedOutput() throws {
        let result = QMDRunResult(
            actionTitle: "Test",
            command: "qmd test",
            exitCode: 1,
            output: String(repeating: "x", count: 100_000),
            startedAt: Date(timeIntervalSince1970: 10),
            finishedAt: Date(timeIntervalSince1970: 11)
        )

        let persisted = result.persistedSummary
        XCTAssertLessThan(persisted.output.count, 4_100)

        let roundTrip = try JSONDecoder().decode(
            QMDRunResult.self,
            from: JSONEncoder().encode(persisted)
        )
        XCTAssertEqual(roundTrip.id, result.id)
        XCTAssertEqual(roundTrip.command, result.command)
        XCTAssertEqual(roundTrip.output, persisted.output)
    }
}
