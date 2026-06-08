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
    typealias CommandExecutor = @Sendable ([String]) async throws -> QMDRunResult

    let preferences: QMDPreferences
    private static let defaultSpawnRetryDelays = [5, 15, 30, 60]
    private let spawnRetryDelays: [Int]
    private let commandExecutor: CommandExecutor

    init(
        preferences: QMDPreferences,
        spawnRetryDelays: [Int] = QMDRunner.defaultSpawnRetryDelays,
        commandExecutor: CommandExecutor? = nil
    ) {
        self.preferences = preferences
        self.spawnRetryDelays = spawnRetryDelays
        self.commandExecutor = commandExecutor ?? { arguments in
            try await Self.runProcess(preferences: preferences, arguments: arguments)
        }
    }

    static func watchdogSeconds(for command: QMDCommand, preferences: QMDPreferences) -> Int {
        let processCount = command == .updateAndEmbed ? 2 : 1
        let spawnRetrySeconds = defaultSpawnRetryDelays.reduce(0, +)
        return (preferences.commandTimeoutSeconds + spawnRetrySeconds) * processCount + 30
    }

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
        let startedAt = Date()
        var lastResult: QMDRunResult?

        for attempt in 1...spawnRetryDelays.count + 1 {
            let result: QMDRunResult

            do {
                result = try await commandExecutor(arguments)
            } catch {
                guard isTransientSpawnError(error) else {
                    throw error
                }

                if attempt <= spawnRetryDelays.count {
                    try await Task.sleep(for: .seconds(spawnRetryDelays[attempt - 1]))
                    continue
                }

                let command = commandDescription(arguments: ["--index", preferences.indexName] + arguments)
                return QMDRunResult(
                    actionTitle: arguments.first ?? "QMD",
                    command: command,
                    exitCode: -4,
                    output: "QMD command could not be started after \(attempt) attempts because macOS temporarily refused to spawn a process.\n\(error.localizedDescription)",
                    startedAt: startedAt,
                    finishedAt: Date()
                )
            }

            if !isDatabaseLocked(result.output) {
                return result
            }

            lastResult = result
            if attempt < spawnRetryDelays.count + 1 {
                try await Task.sleep(for: .seconds(attempt * 2))
            }
        }

        if let lastResult {
            return lastResult
        }

        return QMDRunResult(
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

    private func isTransientSpawnError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSPOSIXErrorDomain &&
            nsError.code == Int(POSIXErrorCode.EAGAIN.rawValue)
    }

    @discardableResult
    private static func runProcess(preferences: QMDPreferences, arguments: [String]) async throws -> QMDRunResult {
        let startedAt = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: preferences.qmdBinaryPath)
        process.arguments = ["--index", preferences.indexName] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: preferences.workingDirectory)
        process.environment = environment(preferences: preferences)

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        let command = commandDescription(qmdBinaryPath: preferences.qmdBinaryPath, arguments: process.arguments ?? [])
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

    private static func environment(preferences: QMDPreferences) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = preferences.homeDirectory
        env["QMD_LLAMA_GPU"] = preferences.useGPU ? "true" : "false"
        env["npm_config_cache"] = preferences.npmCachePath
        env["PATH"] = preferences.pathEnvironment
        return env
    }

    private func commandDescription(arguments: [String]) -> String {
        Self.commandDescription(qmdBinaryPath: preferences.qmdBinaryPath, arguments: arguments)
    }

    private static func commandDescription(qmdBinaryPath: String, arguments: [String]) -> String {
        ([qmdBinaryPath] + arguments).joined(separator: " ")
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
