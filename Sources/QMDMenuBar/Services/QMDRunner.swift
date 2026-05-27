import Foundation

enum QMDRunnerError: LocalizedError {
    case timedOut(command: String, seconds: Int)

    var errorDescription: String? {
        switch self {
        case let .timedOut(command, seconds):
            "QMD command timed out after \(seconds)s: \(command)"
        }
    }
}

struct QMDRunner: Sendable {
    let preferences: QMDPreferences

    func status() async throws -> QMDStatus {
        let result = try await runWithLockRetry(arguments: ["status"])
        return QMDStatus.parse(result.output, collectionName: preferences.collectionName)
    }

    func run(command: QMDCommand) async throws -> QMDRunResult {
        switch command {
        case .updateAndEmbed:
            let update = try await runWithLockRetry(arguments: ["update"])
            guard update.succeeded else { return update.labeled(command.title) }
            let embed = try await runWithLockRetry(arguments: ["embed", "--chunk-strategy", "auto"])
            return QMDRunResult(
                actionTitle: command.title,
                command: "\(update.command) && \(embed.command)",
                exitCode: embed.exitCode,
                output: "Update:\n\(update.output)\n\nEmbed:\n\(embed.output)",
                startedAt: update.startedAt,
                finishedAt: embed.finishedAt
            )
        case .updateIndex:
            return try await runWithLockRetry(arguments: ["update"]).labeled(command.title)
        case .generateEmbeddings:
            return try await runWithLockRetry(arguments: ["embed", "--chunk-strategy", "auto"]).labeled(command.title)
        case .forceRebuildEmbeddings:
            return try await runWithLockRetry(arguments: ["embed", "-f", "--chunk-strategy", "auto"]).labeled(command.title)
        case .ensureCollection:
            return try await ensureCollection().labeled(command.title)
        }
    }

    private func ensureCollection() async throws -> QMDRunResult {
        let list = try await runWithLockRetry(arguments: ["collection", "list"])
        if list.output.contains("\n\(preferences.collectionName) (qmd://\(preferences.collectionName)/)") ||
            list.output.contains(" \(preferences.collectionName) (qmd://\(preferences.collectionName)/)") {
            return QMDRunResult(
                actionTitle: "Ensure Collection",
                command: list.command,
                exitCode: 0,
                output: "Collection '\(preferences.collectionName)' already exists.\n\n\(list.output)",
                startedAt: list.startedAt,
                finishedAt: list.finishedAt
            )
        }

        return try await runWithLockRetry(arguments: [
            "collection",
            "add",
            preferences.memoryRoot,
            "--name",
            preferences.collectionName,
            "--pattern",
            preferences.fileMask
        ])
    }

    private func runWithLockRetry(arguments: [String]) async throws -> QMDRunResult {
        var lastResult: QMDRunResult?

        for attempt in 1...4 {
            let result = try await run(arguments: arguments)
            if !isDatabaseLocked(result.output) {
                return result
            }

            lastResult = result
            if attempt < 4 {
                try await Task.sleep(for: .seconds(attempt * 2))
            }
        }

        return lastResult ?? QMDRunResult(
            actionTitle: arguments.first ?? "QMD",
            command: arguments.joined(separator: " "),
            exitCode: 1,
            output: "QMD database stayed locked after retries.",
            startedAt: Date(),
            finishedAt: Date()
        )
    }

    private func isDatabaseLocked(_ output: String) -> Bool {
        output.localizedCaseInsensitiveContains("database is locked") ||
            output.localizedCaseInsensitiveContains("SQLITE_BUSY")
    }

    @discardableResult
    private func run(arguments: [String]) async throws -> QMDRunResult {
        let startedAt = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: preferences.qmdBinaryPath)
        process.arguments = ["--index", preferences.indexName] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: preferences.workingDirectory)
        process.environment = environment()

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        let command = commandDescription(arguments: process.arguments ?? [])
        let state = ProcessRunState()
        let output = ProcessOutputBuffer()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            output.append(data)
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .seconds(preferences.commandTimeoutSeconds)) {
                    state.finish {
                        outputPipe.fileHandleForReading.readabilityHandler = nil
                        if process.isRunning {
                            process.terminate()
                        }
                        continuation.resume(throwing: QMDRunnerError.timedOut(
                            command: command,
                            seconds: preferences.commandTimeoutSeconds
                        ))
                    }
                }

                process.terminationHandler = { terminatedProcess in
                    state.finish {
                        outputPipe.fileHandleForReading.readabilityHandler = nil
                        continuation.resume(returning: QMDRunResult(
                            actionTitle: arguments.first ?? "QMD",
                            command: command,
                            exitCode: terminatedProcess.terminationStatus,
                            output: output.string,
                            startedAt: startedAt,
                            finishedAt: Date()
                        ))
                    }
                }

                do {
                    try process.run()
                } catch {
                    state.finish {
                        outputPipe.fileHandleForReading.readabilityHandler = nil
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            if process.isRunning {
                process.terminate()
            }
        }
    }

    private func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = preferences.homeDirectory
        env["QMD_LLAMA_GPU"] = preferences.useGPU ? "true" : "false"
        env["npm_config_cache"] = preferences.npmCachePath
        env["PATH"] = preferences.pathEnvironment
        return env
    }

    private func commandDescription(arguments: [String]) -> String {
        ([preferences.qmdBinaryPath] + arguments).joined(separator: " ")
    }
}

private final class ProcessOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    var string: String {
        lock.lock()
        let snapshot = data
        lock.unlock()
        return String(data: snapshot, encoding: .utf8) ?? ""
    }

    func append(_ newData: Data) {
        lock.lock()
        data.append(newData)
        lock.unlock()
    }
}

private final class ProcessRunState: @unchecked Sendable {
    private let lock = NSLock()
    private var didFinish = false

    func finish(_ body: () -> Void) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }

        didFinish = true
        lock.unlock()
        body()
    }
}
