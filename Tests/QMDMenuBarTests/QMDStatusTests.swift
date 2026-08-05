import XCTest
@testable import QMDMenuBar

final class QMDStatusTests: XCTestCase {
    func testParsesQMD25StatusAndPreferredCollection() {
        let output = """
        QMD Status

        Index: /tmp/index.sqlite

        Documents
          Total:    1,234 files indexed
          Vectors:  2,345 embedded
          Updated:  22h ago

        Collections
          other (qmd://other/)
            Files:    99 (updated 1d ago)
          agent-memory-root (qmd://agent-memory-root/)
            Files:    3 (updated 2h ago)
        """

        let status = QMDStatus.parse(output, collectionName: "agent-memory-root")

        XCTAssertEqual(status.indexPath, "/tmp/index.sqlite")
        XCTAssertEqual(status.totalDocuments, 1_234)
        XCTAssertEqual(status.vectors, 2_345)
        XCTAssertEqual(status.updated, "22h ago")
        XCTAssertEqual(status.collectionName, "agent-memory-root")
        XCTAssertEqual(status.collectionFiles, 3)
        XCTAssertEqual(
            status.collections,
            [
                QMDCollectionStatus(name: "other", files: 99),
                QMDCollectionStatus(name: "agent-memory-root", files: 3),
            ]
        )
    }

    func testParsesLargeStatusIncludingEmptyCollections() {
        let collectionBlock = (0..<200).map { index in
            """
              collection-\(index) (qmd://collection-\(index)/)
                Pattern: **/*.md
                Files:    \(index)
                Updated:  1m ago
            """
        }.joined(separator: "\n")
        let output = """
        QMD Status
        Index: /tmp/index.sqlite
        Documents
          Total: 19,900 files indexed
          Vectors: 20,000 embedded
        Collections
        \(collectionBlock)
        """

        let status = QMDStatus.parse(output, collectionName: "collection-199")

        XCTAssertEqual(status.collections.count, 200)
        XCTAssertEqual(status.collections.first, QMDCollectionStatus(name: "collection-0", files: 0))
        XCTAssertEqual(status.collections.last, QMDCollectionStatus(name: "collection-199", files: 199))
        XCTAssertEqual(status.collectionFiles, 199)
    }
}
