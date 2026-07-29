import XCTest
@testable import QMDMenuBar

final class QMDRunResultTests: XCTestCase {
    func testConciseOutputAggregatesCollectionIndexCounts() {
        let result = QMDRunResult(
            actionTitle: "Update + Embed",
            command: "qmd update && qmd embed",
            exitCode: 0,
            output: """
            Indexed: 0 new, 0 updated, 1 unchanged, 0 removed
            Indexed: 2 new, 1 updated, 5 unchanged, 1 removed
            Indexed: 0 new, 3 updated, 10 unchanged, 0 removed
            Embedded 12 chunks from 6 documents
            """,
            startedAt: Date(timeIntervalSince1970: 10),
            finishedAt: Date(timeIntervalSince1970: 11)
        )

        XCTAssertEqual(
            result.conciseOutput,
            "Indexed: 2 new, 4 updated, 16 unchanged, 1 removed\nEmbedded 12 chunks from 6 documents"
        )
    }

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
