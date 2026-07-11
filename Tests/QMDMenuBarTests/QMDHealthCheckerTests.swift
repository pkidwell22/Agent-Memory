import Foundation
import XCTest
@testable import QMDMenuBar

final class QMDHealthCheckerTests: XCTestCase {
    func testHealthyReportShowsResolvedRuntimeVersionAndAccessiblePaths() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QMDHealthTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let memoryRoot = directory.appendingPathComponent("agent-memory", isDirectory: true)
        try FileManager.default.createDirectory(at: memoryRoot, withIntermediateDirectories: true)
        let index = directory.appendingPathComponent("index.sqlite")
        try Data().write(to: index)

        let node = directory.appendingPathComponent("node")
        try writeExecutable("#!/bin/sh\necho 'v25.6.1'\n", to: node)
        let qmd = directory.appendingPathComponent("qmd")
        try writeExecutable("""
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo 'qmd 2.5.3 (fixture)'
          exit 0
        fi
        echo 'Index: \(index.path)'
        echo '  Total: 2 files indexed'
        echo '  Vectors: 4 embedded'
        """, to: qmd)

        var preferences = QMDPreferences.defaults
        preferences.qmdBinaryPath = qmd.path
        preferences.workingDirectory = directory.path
        preferences.homeDirectory = directory.path
        preferences.memoryRoot = memoryRoot.path
        preferences.pathEnvironment = directory.path
        preferences.npmCachePath = directory.appendingPathComponent("npm-cache").path

        let report = await QMDHealthChecker(preferences: preferences).check()

        XCTAssertFalse(report.hasFailures)
        XCTAssertEqual(report.qmdVersion, "qmd 2.5.3 (fixture)")
        XCTAssertEqual(report.runtimePath, node.path)
        XCTAssertEqual(report.runtimeVersion, "v25.6.1")
        XCTAssertEqual(report.indexPath, index.path)
        XCTAssertEqual(report.status?.totalDocuments, 2)
    }

    func testFailedChecksIncludeRemediation() async {
        var preferences = QMDPreferences.defaults
        preferences.qmdBinaryPath = "/missing/qmd"
        preferences.memoryRoot = "/missing/agent-memory"
        preferences.pathEnvironment = "/missing/bin"

        let report = await QMDHealthChecker(preferences: preferences).check()

        XCTAssertTrue(report.hasFailures)
        XCTAssertTrue(report.items.filter { $0.state == .failed }.allSatisfy { $0.remediation?.isEmpty == false })
    }

    private func writeExecutable(_ contents: String, to url: URL) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
