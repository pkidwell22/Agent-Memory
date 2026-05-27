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
        let result = try await run(arguments: ["status"])
        return QMDStatus.parse(result.output, collectionName: preferences.collectionName)
    }

    func run(command: QMDCommand) async throws -> QMDRunResult {
        switch command {
        case .updateAndEmbed:
            let update = try await run(arguments: ["update"])
            guard update.succeeded else { return update.labeled(command.title) }
            let embed = try await run(arguments: ["embed", "--chunk-strategy", "auto"])
            return QMDRunResult(
                actionTitle: command.title,
                command: "\(update.command) && \(embed.command)",
                exitCode: embed.exitCode,
                output: "Update:\n\(update.output)\n\nEmbed:\n\(embed.output)",
                startedAt: update.startedAt,
                finishedAt: embed.finishedAt
            )
        case .updateIndex:
            return try await run(arguments: ["update"]).labeled(command.title)
        case .generateEmbeddings:
            return try await run(arguments: ["embed", "--chunk-strategy", "auto"]).labeled(command.title)
        case .forceRebuildEmbeddings:
            return try await run(arguments: ["embed", "-f", "--chunk-strategy", "auto"]).labeled(command.title)
        case .ensureCollection:
            return try await ensureCollection().labeled(command.title)
        }
    }

    private func ensureCollection() async throws -> QMDRunResult {
        let list = try await run(arguments: ["collection", "list"])
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

        return try await run(arguments: [
            "collection",
            "add",
            preferences.memoryRoot,
            "--name",
            preferences.collectionName,
            "--pattern",
            preferences.fileMask
        ])
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

        try process.run()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .seconds(preferences.commandTimeoutSeconds)) {
                    state.finish {
                        if process.isRunning {
                            process.terminate()
                        }
                        continuation.resume(throwing: QMDRunnerError.timedOut(
                            command: command,
                            seconds: preferences.commandTimeoutSeconds
                        ))
                    }
                }

                DispatchQueue.global(qos: .utility).async {
                    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    state.finish {
                        continuation.resume(returning: QMDRunResult(
                            actionTitle: arguments.first ?? "QMD",
                            command: command,
                            exitCode: process.terminationStatus,
                            output: output,
                            startedAt: startedAt,
                            finishedAt: Date()
                        ))
                    }
                }
            }
        } onCancel: {
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
