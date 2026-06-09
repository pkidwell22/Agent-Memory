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
            return try await ensureAgentMemoryCollections().labeled(command.title)
        }
    }

    private func ensureAgentMemoryCollections() async throws -> QMDRunResult {
        let list = try await runWithLockRetry(arguments: ["collection", "list"])
        let desiredCollections = try agentMemoryCollections()
        let missingCollections = desiredCollections.filter { !collectionExists($0.name, in: list.output) }

        if missingCollections.isEmpty {
            return QMDRunResult(
                actionTitle: "Ensure Collections",
                command: list.command,
                exitCode: 0,
                output: "All agent-memory collections already exist.\n\n\(list.output)",
                startedAt: list.startedAt,
                finishedAt: list.finishedAt
            )
        }

        var outputs = ["Existing collections:\n\(list.output)"]
        var commands = [list.command]
        var lastResult = list

        for collection in missingCollections {
            let result = try await runWithLockRetry(arguments: [
                "collection",
                "add",
                collection.path,
                "--name",
                collection.name,
                "--pattern",
                collection.pattern
            ])
            lastResult = result
            commands.append(result.command)
            outputs.append("Added/ensured \(collection.name):\n\(result.output)")

            if !result.succeeded {
                break
            }
        }

        return QMDRunResult(
            actionTitle: "Ensure Agent-Memory Collections",
            command: commands.joined(separator: " && "),
            exitCode: lastResult.exitCode,
            output: outputs.joined(separator: "\n\n"),
            startedAt: list.startedAt,
            finishedAt: lastResult.finishedAt
        )
    }

    private func collectionExists(_ name: String, in collectionList: String) -> Bool {
        collectionList.split(separator: "\n").contains { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            return line == "\(name) (qmd://\(name)/)"
        }
    }

    private func agentMemoryCollections() throws -> [AgentMemoryCollection] {
        let rootURL = URL(fileURLWithPath: preferences.memoryRoot)
        let directoryURLs = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        let folders = try directoryURLs.filter { url in
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            return values.isDirectory == true
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        return [
            AgentMemoryCollection(
                name: "agent-memory-root",
                path: preferences.memoryRoot,
                pattern: "*.md"
            )
        ] + folders.map { folder in
            AgentMemoryCollection(
                name: canonicalCollectionName(for: folder.lastPathComponent),
                path: folder.path,
                pattern: preferences.fileMask
            )
        }
    }

    private func canonicalCollectionName(for folderName: String) -> String {
        folderName.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
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
        let indexName = preferences.indexName.trimmingCharacters(in: .whitespacesAndNewlines)
        process.arguments = indexName.isEmpty ? arguments : ["--index", indexName] + arguments
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

private struct AgentMemoryCollection: Sendable {
    let name: String
    let path: String
    let pattern: String
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
