import Foundation
import XCTest
@testable import QMDMenuBar

final class QMDRunnerTests: XCTestCase {
    func testRetriesTransientSpawnFailureBeforeSucceeding() async throws {
        let attempts = AttemptRecorder()
        let runner = QMDRunner(
            preferences: .defaults,
            spawnRetryDelays: [0, 0],
            commandExecutor: { arguments in
                let attempt = await attempts.next()
                if attempt < 3 {
                    throw NSError(
                        domain: NSPOSIXErrorDomain,
                        code: Int(POSIXErrorCode.EAGAIN.rawValue)
                    )
                }

                return QMDRunResult(
                    actionTitle: arguments.first ?? "QMD",
                    command: arguments.joined(separator: " "),
                    exitCode: 0,
                    output: "Indexed: 0 new, 0 updated, 153 unchanged, 0 removed",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }
        )

        let result = try await runner.run(command: .updateIndex)
        let count = await attempts.count()

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(count, 3)
        XCTAssertEqual(result.actionTitle, "Update Index")
    }

    func testReturnsDiagnosticResultAfterSpawnRetriesAreExhausted() async throws {
        let attempts = AttemptRecorder()
        let runner = QMDRunner(
            preferences: .defaults,
            spawnRetryDelays: [0, 0],
            commandExecutor: { _ in
                _ = await attempts.next()
                throw NSError(
                    domain: NSPOSIXErrorDomain,
                    code: Int(POSIXErrorCode.EAGAIN.rawValue)
                )
            }
        )

        let result = try await runner.run(command: .updateIndex)
        let count = await attempts.count()

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.exitCode, -4)
        XCTAssertEqual(count, 3)
        XCTAssertTrue(result.command.contains("/qmd/bin/qmd --index obsidian-agent-memory update"))
        XCTAssertTrue(result.output.contains("temporarily refused to spawn"))
    }

    func testDoesNotRetryNonTransientSpawnFailure() async throws {
        let attempts = AttemptRecorder()
        let runner = QMDRunner(
            preferences: .defaults,
            spawnRetryDelays: [0, 0],
            commandExecutor: { _ in
                _ = await attempts.next()
                throw NSError(
                    domain: NSPOSIXErrorDomain,
                    code: Int(POSIXErrorCode.ENOENT.rawValue)
                )
            }
        )

        do {
            _ = try await runner.run(command: .updateIndex)
            XCTFail("Expected non-transient spawn failure to be thrown")
        } catch {
            let count = await attempts.count()
            XCTAssertEqual(count, 1)
        }
    }
}

private actor AttemptRecorder {
    private var value = 0

    func count() -> Int {
        value
    }

    func next() -> Int {
        value += 1
        return value
    }
}
