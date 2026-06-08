import XCTest
@testable import QMDMenuBar

final class QMDRunResultTests: XCTestCase {
    func testDecodesLegacyRunHistoryWithoutTrigger() throws {
        let data = """
        {
          "id": "6D38E4EC-CC73-4947-8D8C-7064FC5243E7",
          "actionTitle": "Update + Embed",
          "command": "/Users/patkidwell/qmd/bin/qmd --index obsidian-agent-memory update",
          "exitCode": 0,
          "output": "Indexed: 0 new, 0 updated, 153 unchanged, 0 removed",
          "startedAt": 0,
          "finishedAt": 1
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(QMDRunResult.self, from: data)

        XCTAssertEqual(result.trigger, .manual)
        XCTAssertEqual(result.displayTitle, "Update + Embed")
    }

    func testAutomaticDisplayTitleIsLabeled() {
        let result = QMDRunResult(
            actionTitle: "Update + Embed",
            command: "qmd update",
            exitCode: 0,
            output: "",
            startedAt: Date(),
            finishedAt: Date(),
            trigger: .automatic
        )

        XCTAssertEqual(result.displayTitle, "Update + Embed (Automatic)")
    }
}
