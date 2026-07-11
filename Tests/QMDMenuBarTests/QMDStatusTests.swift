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
    }
}
