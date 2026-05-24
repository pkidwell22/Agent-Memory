import Foundation

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
            guard update.succeeded else { return update }
            return try await run(arguments: ["embed", "--chunk-strategy", "auto"])
        case .updateIndex:
            return try await run(arguments: ["update"])
        case .generateEmbeddings:
            return try await run(arguments: ["embed", "--chunk-strategy", "auto"])
        case .forceRebuildEmbeddings:
            return try await run(arguments: ["embed", "-f", "--chunk-strategy", "auto"])
        case .ensureCollection:
            return try await ensureCollection()
        }
    }

    private func ensureCollection() async throws -> QMDRunResult {
        let list = try await run(arguments: ["collection", "list"])
        if list.output.contains("\n\(preferences.collectionName) (qmd://\(preferences.collectionName)/)") ||
            list.output.contains(" \(preferences.collectionName) (qmd://\(preferences.collectionName)/)") {
            return QMDRunResult(
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

        try process.run()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: QMDRunResult(
                        command: commandDescription(arguments: process.arguments ?? []),
                        exitCode: process.terminationStatus,
                        output: output,
                        startedAt: startedAt,
                        finishedAt: Date()
                    ))
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
