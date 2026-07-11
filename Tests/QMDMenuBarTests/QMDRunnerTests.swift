import Foundation
import XCTest
@testable import QMDMenuBar

final class QMDRunnerTests: XCTestCase {
    func testStatusThrowsTypedErrorForNonzeroExit() async throws {
        let fixture = try ShellFixture(script: """
        #!/bin/sh
        echo 'fatal: broken index' >&2
        exit 42
        """)

        do {
            _ = try await QMDRunner(preferences: fixture.preferences, lockRetryDelays: []).status()
            XCTFail("Expected commandFailed")
        } catch let error as QMDRunnerError {
            guard case let .commandFailed(_, exitCode, output) = error else {
                return XCTFail("Unexpected QMDRunnerError: \(error)")
            }
            XCTAssertEqual(exitCode, 42)
            XCTAssertTrue(output.contains("fatal: broken index"))
        }
    }

    func testDatabaseLockIsRetried() async throws {
        let fixture = try ShellFixture(script: """
        #!/bin/sh
        count_file="$(dirname "$0")/count"
        count=0
        if [ -f "$count_file" ]; then count=$(cat "$count_file"); fi
        count=$((count + 1))
        echo "$count" > "$count_file"
        if [ "$count" -lt 3 ]; then
          echo 'SQLiteError: database is locked' >&2
          exit 1
        fi
        echo 'Index: /tmp/index.sqlite'
        echo '  Total: 2 files indexed'
        echo '  Vectors: 4 embedded'
        """)

        let runner = QMDRunner(
            preferences: fixture.preferences,
            lockRetryDelays: [.milliseconds(1), .milliseconds(1)]
        )
        let status = try await runner.status()

        XCTAssertEqual(status.totalDocuments, 2)
        XCTAssertEqual(status.vectors, 4)
        let count = try String(contentsOf: fixture.directory.appendingPathComponent("count"), encoding: .utf8)
        XCTAssertEqual(count.trimmingCharacters(in: .whitespacesAndNewlines), "3")
    }

    func testCapturedOutputKeepsABoundedTail() async throws {
        let fixture = try ShellFixture(script: """
        #!/bin/sh
        yes x | head -c 700000
        """)

        let result = try await QMDRunner(
            preferences: fixture.preferences,
            lockRetryDelays: []
        ).run(command: .updateIndex)

        XCTAssertTrue(result.output.hasPrefix("[Earlier output truncated]"))
        XCTAssertLessThanOrEqual(
            result.output.utf8.count,
            QMDRunner.maximumCapturedOutputBytes + 64
        )
    }

    func testSearchDecodesQMDJSONAndResolvesSourcePath() async throws {
        let fixture = try ShellFixture(script: """
        #!/bin/sh
        if [ "$1" = "search" ]; then
          cat <<'JSON'
        [{"docid":"#abc123","score":0.9,"file":"qmd://notes/example.md","line":7,"title":"Example","context":"Notes","snippet":"@@ -7,2 @@\\nUseful result"}]
        JSON
          exit 0
        fi
        if [ "$1" = "get" ]; then
          echo '/tmp/example.md'
          echo '7: Useful result'
          exit 0
        fi
        exit 2
        """)
        let runner = QMDRunner(preferences: fixture.preferences, lockRetryDelays: [])

        let results = try await runner.search(query: "useful", mode: .keyword)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].displayTitle, "Example")
        XCTAssertEqual(results[0].displaySnippet, "Useful result")
        let resolvedPath = try await runner.resolvedFilePath(for: results[0])
        XCTAssertEqual(resolvedPath, "/tmp/example.md")
    }

    func testCollectionPlanFindsAddsReplacementsAndManagedRemovals() async throws {
        let fixture = try ShellFixture(script: """
        #!/bin/sh
        if [ "$1" = "collection" ] && [ "$2" = "list" ]; then
          echo 'alpha (qmd://alpha/)'
          echo 'stale (qmd://stale/)'
          echo 'external (qmd://external/)'
          exit 0
        fi
        if [ "$1" = "collection" ] && [ "$2" = "show" ]; then
          echo "Collection: $3"
          case "$3" in
            alpha)
              echo "  Path: $HOME/agent-memory/alpha"
              echo '  Pattern: *.txt'
              ;;
            stale)
              echo "  Path: $HOME/agent-memory/stale"
              echo '  Pattern: **/*.md'
              ;;
            external)
              echo '  Path: /tmp/external-notes'
              echo '  Pattern: **/*.md'
              ;;
          esac
          exit 0
        fi
        exit 2
        """)
        let memoryRoot = fixture.directory.appendingPathComponent("agent-memory", isDirectory: true)
        try FileManager.default.createDirectory(
            at: memoryRoot.appendingPathComponent("alpha", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: memoryRoot.appendingPathComponent("new folder", isDirectory: true),
            withIntermediateDirectories: true
        )
        var preferences = fixture.preferences
        preferences.memoryRoot = memoryRoot.path

        let plan = try await QMDRunner(
            preferences: preferences,
            lockRetryDelays: []
        ).collectionReconciliationPlan()

        XCTAssertTrue(plan.changes.contains { $0.action == .replace && $0.existing?.name == "alpha" })
        XCTAssertTrue(plan.changes.contains { $0.action == .remove && $0.existing?.name == "stale" })
        XCTAssertTrue(plan.changes.contains { $0.action == .add && $0.desired?.name == "new-folder" })
        XCTAssertTrue(plan.changes.contains { $0.action == .add && $0.desired?.name == "agent-memory-root" })
        XCTAssertFalse(plan.changes.contains { $0.existing?.name == "external" })
    }
}

private final class ShellFixture {
    let directory: URL
    let executable: URL
    let preferences: QMDPreferences

    init(script: String) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QMDMenuBarTests-\(UUID().uuidString)", isDirectory: true)
        executable = directory.appendingPathComponent("qmd-fixture")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        var value = QMDPreferences.defaults
        value.qmdBinaryPath = executable.path
        value.workingDirectory = directory.path
        value.homeDirectory = directory.path
        value.pathEnvironment = "/usr/bin:/bin"
        value.npmCachePath = directory.appendingPathComponent("npm-cache").path
        value.commandTimeoutSeconds = 5
        preferences = value
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}
