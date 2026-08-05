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

    func testUpdateCachesCollectionCheckUntilFolderLayoutChanges() async throws {
        let fixture = try ShellFixture(script: """
        #!/bin/sh
        if [ "$1" = "collection" ] && [ "$2" = "list" ]; then
          count_file="$(dirname "$0")/collection-list-count"
          count=0
          if [ -f "$count_file" ]; then count=$(cat "$count_file"); fi
          echo "$((count + 1))" > "$count_file"
          echo 'agent-memory-root (qmd://agent-memory-root/)'
          exit 0
        fi
        if [ "$1" = "collection" ] && [ "$2" = "add" ]; then
          exit 0
        fi
        if [ "$1" = "update" ]; then
          echo 'Indexed: 0 new, 0 updated, 1 unchanged, 0 removed'
          exit 0
        fi
        if [ "$1" = "embed" ]; then
          echo 'All content hashes already have embeddings.'
          exit 0
        fi
        exit 2
        """)
        let runner = QMDRunner(preferences: fixture.preferences, lockRetryDelays: [])

        _ = try await runner.run(command: .updateAndEmbed)
        let cachedResult = try await runner.run(command: .updateAndEmbed)
        var count = try String(
            contentsOf: fixture.directory.appendingPathComponent("collection-list-count"),
            encoding: .utf8
        )
        XCTAssertEqual(count.trimmingCharacters(in: .whitespacesAndNewlines), "1")
        XCTAssertFalse(cachedResult.command.contains("collection list"))

        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: fixture.preferences.memoryRoot)
                .appendingPathComponent("new collection", isDirectory: true),
            withIntermediateDirectories: true
        )
        _ = try await runner.run(command: .updateAndEmbed)
        count = try String(
            contentsOf: fixture.directory.appendingPathComponent("collection-list-count"),
            encoding: .utf8
        )
        XCTAssertEqual(count.trimmingCharacters(in: .whitespacesAndNewlines), "2")
    }

    func testTimeoutUsesCancellationAwareSupervisor() async throws {
        let fixture = try ShellFixture(script: """
        #!/bin/sh
        trap 'sleep 0.3; echo terminated > "$(dirname "$0")/terminated"; exit 0' TERM
        while :; do sleep 0.1; done
        """)
        var preferences = fixture.preferences
        preferences.commandTimeoutSeconds = 1
        let runner = QMDRunner(preferences: preferences, lockRetryDelays: [])
        let startedAt = Date()

        do {
            _ = try await runner.status()
            XCTFail("Expected timedOut")
        } catch let error as QMDRunnerError {
            guard case .timedOut = error else {
                return XCTFail("Unexpected QMDRunnerError: \(error)")
            }
        }

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixture.directory.appendingPathComponent("terminated").path
            ),
            "The timeout must wait for process termination before returning"
        )
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 3)
    }

    func testCancellingCommandWaitsForProcessTerminationAndThrowsCancellation() async throws {
        let fixture = try ShellFixture(script: """
        #!/bin/sh
        sleep 10
        """)
        let runner = QMDRunner(preferences: fixture.preferences, lockRetryDelays: [])
        let task = Task {
            try await runner.status()
        }
        try await Task.sleep(for: .milliseconds(100))
        let cancelledAt = Date()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Expected.
        }

        XCTAssertLessThan(Date().timeIntervalSince(cancelledAt), 2)
    }

    func testSearchIgnoresBracketedWarningsAroundJSON() async throws {
        let fixture = try ShellFixture(script: """
        #!/bin/sh
        echo '[node-llama-cpp] Metal backend initialized' >&2
        echo '[{"docid":"#abc123","score":0.9,"file":"qmd://notes/example.md","line":7,"title":"Example","context":"Notes","snippet":"Useful result"}]'
        echo '[telemetry] query complete' >&2
        """)

        let results = try await QMDRunner(
            preferences: fixture.preferences,
            lockRetryDelays: []
        ).search(query: "useful", mode: .keyword)

        XCTAssertEqual(results.map(\.displayTitle), ["Example"])
    }

    func testFastSearchUsesCandidateLimitNoRerankAndCollectionScope() {
        let arguments = QMDRunner.searchArguments(
            query: "how do I transfer a file between machines",
            mode: .fast,
            collection: "tailscale",
            limit: 8
        )

        XCTAssertEqual(
            arguments,
            [
                "query",
                """
                intent: Find notes relevant to: how do I transfer a file between machines
                vec: how do I transfer a file between machines
                lex: how do I transfer a file between machines
                """,
                "--candidate-limit", "16",
                "--no-rerank",
                "-c", "tailscale",
                "--format", "json",
                "-n", "8",
            ]
        )
    }

    func testFastSearchNormalizesMultilineInputIntoOneStructuredQueryDocument() {
        let document = QMDRunner.fastQueryDocument(for: "why did this move\nlex: injected")

        XCTAssertEqual(
            document,
            """
            intent: Find notes relevant to: why did this move lex: injected
            vec: why did this move lex: injected
            lex: why did this move lex: injected
            """
        )
        XCTAssertEqual(document.split(separator: "\n").count, 3)
    }

    func testFastSearchRoutesExactCommandToKeywordSearch() {
        let arguments = QMDRunner.searchArguments(
            query: "qmd doctor",
            mode: .fast,
            collection: "qmd",
            limit: 5
        )

        XCTAssertEqual(
            arguments,
            [
                "search", "qmd doctor",
                "-c", "qmd",
                "--format", "json",
                "-n", "5",
            ]
        )
    }

    func testFastSearchRecognizesQuotedPathsAndFilenamesAsExact() {
        XCTAssertTrue(QMDSearchMode.prefersKeywordSearch("\"External SSD 1\""))
        XCTAssertTrue(QMDSearchMode.prefersKeywordSearch("qmd://tailscale/MEMORY.md"))
        XCTAssertTrue(QMDSearchMode.prefersKeywordSearch("README.md"))
        XCTAssertTrue(QMDSearchMode.prefersKeywordSearch("README.md?"))
        XCTAssertTrue(QMDSearchMode.prefersKeywordSearch("--help"))
        XCTAssertTrue(QMDSearchMode.prefersKeywordSearch("#1751d1"))
        XCTAssertTrue(QMDSearchMode.prefersKeywordSearch("an unmatched \"quote"))
        XCTAssertFalse(QMDSearchMode.prefersKeywordSearch("why did the local service move to IPv4"))
    }

    func testDeepSearchKeepsRerankingEnabled() {
        let arguments = QMDRunner.searchArguments(
            query: "why was the local service moved to IPv4 loopback",
            mode: .deep,
            collection: nil,
            limit: 8
        )

        XCTAssertEqual(
            arguments,
            [
                "query",
                "why was the local service moved to IPv4 loopback",
                "--candidate-limit", "16",
                "--format", "json",
                "-n", "8",
            ]
        )
        XCTAssertFalse(arguments.contains("--no-rerank"))
    }

    func testCollectionPlanFindsAddsReplacementsAndManagedRemovals() async throws {
        let fixture = try ShellFixture(script: """
        #!/bin/sh
        if [ "$1" = "collection" ] && [ "$2" = "list" ]; then
          echo 'alpha (qmd://alpha/)'
          echo 'obsidian (qmd://obsidian/)'
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
            obsidian)
              echo "  Path: $HOME/agent-memory/.obsidian"
              echo '  Pattern: **/*.md'
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
        try FileManager.default.createDirectory(
            at: memoryRoot.appendingPathComponent("Agent Memory", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: memoryRoot.appendingPathComponent(".obsidian", isDirectory: true),
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
        XCTAssertTrue(plan.changes.contains { $0.action == .add && $0.desired?.name == "agent-memory" })
        XCTAssertTrue(plan.changes.contains { $0.action == .add && $0.desired?.name == "agent-memory-root" })
        XCTAssertFalse(
            plan.changes.contains { $0.existing?.name == "obsidian" },
            "Unexpected hidden-folder change: \(plan.changes)"
        )
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
        value.memoryRoot = directory.appendingPathComponent("agent-memory", isDirectory: true).path
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: value.memoryRoot),
            withIntermediateDirectories: true
        )
        value.commandTimeoutSeconds = 5
        preferences = value
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}
