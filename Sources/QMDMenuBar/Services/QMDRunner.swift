import Foundation

enum QMDRunnerError: LocalizedError, Equatable {
    case timedOut(command: String, seconds: Int)
    case commandFailed(command: String, exitCode: Int32, output: String)
    case invalidOutput(command: String, detail: String)

    var errorDescription: String? {
        switch self {
        case let .timedOut(command, seconds):
            "QMD command timed out after \(seconds)s: \(command)"
        case let .commandFailed(command, exitCode, output):
            if output.isEmpty {
                "QMD command failed with exit code \(exitCode): \(command)"
            } else {
                "QMD command failed with exit code \(exitCode): \(command)\n\(output)"
            }
        case let .invalidOutput(command, detail):
            "QMD returned unreadable output for \(command): \(detail)"
        }
    }
}

protocol QMDRunning: Sendable {
    func status() async throws -> QMDStatus
    func run(command: QMDCommand) async throws -> QMDRunResult
}

struct QMDRunner: QMDRunning, Sendable {
    static let maximumCapturedOutputBytes = 512 * 1024
    static let semanticCandidateLimit = 16
    static let collectionRecheckInterval: TimeInterval = 24 * 60 * 60
    private static let collectionCheckCache = CollectionCheckCache()

    let preferences: QMDPreferences
    let lockRetryDelays: [Duration]

    init(
        preferences: QMDPreferences,
        lockRetryDelays: [Duration] = [.seconds(2), .seconds(4), .seconds(6)]
    ) {
        self.preferences = preferences
        self.lockRetryDelays = lockRetryDelays
    }

    func status() async throws -> QMDStatus {
        let result = try await runWithLockRetry(arguments: ["status"])
        try requireSuccess(result)
        return QMDStatus.parse(result.output, collectionName: preferences.collectionName)
    }

    func version() async throws -> String {
        let result = try await run(arguments: ["--version"])
        try requireSuccess(result)
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func search(query: String, mode: QMDSearchMode, limit: Int = 8) async throws -> [QMDSearchResult] {
        let subcommand = mode == .keyword ? "search" : "query"
        var arguments = [subcommand, query, "--format", "json", "-n", String(limit)]
        if mode != .keyword {
            arguments += ["-C", String(Self.semanticCandidateLimit)]
        }
        if mode == .fastHybrid {
            arguments.append("--no-rerank")
        }
        let result = try await run(arguments: arguments)
        try requireSuccess(result)

        guard let start = result.output.firstIndex(of: "["),
              let end = result.output.lastIndex(of: "]"),
              start <= end else {
            throw QMDRunnerError.invalidOutput(command: result.command, detail: "No JSON result array was found.")
        }

        let json = String(result.output[start...end])
        do {
            return try JSONDecoder().decode([QMDSearchResult].self, from: Data(json.utf8))
        } catch {
            throw QMDRunnerError.invalidOutput(command: result.command, detail: error.localizedDescription)
        }
    }

    func resolvedFilePath(for result: QMDSearchResult) async throws -> String {
        let commandResult = try await run(arguments: ["get", result.file, "-l", "1", "--full-path"])
        try requireSuccess(commandResult)
        guard let firstLine = commandResult.output.split(separator: "\n").first else {
            throw QMDRunnerError.invalidOutput(command: commandResult.command, detail: "No file path was returned.")
        }
        let path = String(firstLine).trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/") else {
            throw QMDRunnerError.invalidOutput(command: commandResult.command, detail: "Expected an absolute file path, got \(path)")
        }
        return path
    }

    func collectionReconciliationPlan() async throws -> QMDCollectionPlan {
        let desired = try agentMemoryCollections()
        let list = try await runWithLockRetry(arguments: ["collection", "list"])
        try requireSuccess(list)
        let names = collectionNames(from: list.output)
        var existing: [QMDCollectionDefinition] = []

        for name in names {
            let shown = try await runWithLockRetry(arguments: ["collection", "show", name])
            try requireSuccess(shown)
            if let definition = collectionDefinition(from: shown.output, fallbackName: name) {
                existing.append(definition)
            }
        }

        var changes: [QMDCollectionChange] = []
        var matchedExistingNames = Set<String>()

        for target in desired {
            if let sameName = existing.first(where: { $0.name.caseInsensitiveCompare(target.name) == .orderedSame }) {
                matchedExistingNames.insert(sameName.name)
                if normalizedPath(sameName.path) != normalizedPath(target.path) || sameName.pattern != target.pattern {
                    changes.append(QMDCollectionChange(
                        action: .replace,
                        existing: sameName,
                        desired: target,
                        detail: "Replace \(sameName.name) to use \(target.path) with mask \(target.pattern). Existing collection contexts may need to be restored."
                    ))
                }
            } else if let samePath = existing.first(where: { normalizedPath($0.path) == normalizedPath(target.path) }) {
                matchedExistingNames.insert(samePath.name)
                if samePath.pattern == target.pattern {
                    changes.append(QMDCollectionChange(
                        action: .rename,
                        existing: samePath,
                        desired: target,
                        detail: "Rename \(samePath.name) to \(target.name)."
                    ))
                } else {
                    changes.append(QMDCollectionChange(
                        action: .replace,
                        existing: samePath,
                        desired: target,
                        detail: "Replace \(samePath.name) with \(target.name) and mask \(target.pattern). Existing collection contexts may need to be restored."
                    ))
                }
            } else {
                changes.append(QMDCollectionChange(
                    action: .add,
                    desired: target,
                    detail: "Add \(target.name) from \(target.path) with mask \(target.pattern)."
                ))
            }
        }

        let root = normalizedPath(preferences.memoryRoot)
        for current in existing where !matchedExistingNames.contains(current.name) {
            let path = normalizedPath(current.path)
            guard path == root || path.hasPrefix(root + "/") else { continue }
            changes.append(QMDCollectionChange(
                action: .remove,
                existing: current,
                detail: "Remove stale collection \(current.name) at \(current.path)."
            ))
        }

        return QMDCollectionPlan(createdAt: Date(), changes: changes)
    }

    func applyCollectionPlan(_ plan: QMDCollectionPlan) async throws -> QMDRunResult {
        let startedAt = Date()
        guard !plan.isEmpty else {
            return QMDRunResult(
                actionTitle: QMDCommand.ensureCollection.title,
                command: "qmd collection reconcile",
                exitCode: 0,
                output: "Collections already match the agent-memory folders.",
                startedAt: startedAt,
                finishedAt: Date()
            )
        }

        var outputs: [String] = []
        var commands: [String] = []
        var exitCode: Int32 = 0

        for change in plan.changes {
            let argumentSets: [[String]]
            switch change.action {
            case .add:
                guard let desired = change.desired else { continue }
                argumentSets = [collectionAddArguments(desired)]
            case .rename:
                guard let existing = change.existing, let desired = change.desired else { continue }
                argumentSets = [["collection", "rename", existing.name, desired.name]]
            case .replace:
                guard let existing = change.existing, let desired = change.desired else { continue }
                argumentSets = [["collection", "remove", existing.name], collectionAddArguments(desired)]
            case .remove:
                guard let existing = change.existing else { continue }
                argumentSets = [["collection", "remove", existing.name]]
            }

            for arguments in argumentSets {
                let result = try await runWithLockRetry(arguments: arguments)
                commands.append(result.command)
                outputs.append("\(change.action.title): \(change.detail)\n\(result.output)")
                exitCode = result.exitCode
                if !result.succeeded { break }
            }
            if exitCode != 0 { break }
        }

        return QMDRunResult(
            actionTitle: QMDCommand.ensureCollection.title,
            command: commands.joined(separator: " && "),
            exitCode: exitCode,
            output: outputs.joined(separator: "\n\n"),
            startedAt: startedAt,
            finishedAt: Date()
        )
    }

    func run(command: QMDCommand) async throws -> QMDRunResult {
        switch command {
        case .updateAndEmbed:
            let collections = try await ensureAgentMemoryCollectionsIfNeeded()
            guard collections.succeeded else { return collections.labeled(command.title) }
            let update = try await runWithLockRetry(arguments: ["update"])
            guard update.succeeded else { return update.labeled(command.title) }
            let embed = try await runWithLockRetry(arguments: ["embed", "--chunk-strategy", "auto"])
            return QMDRunResult(
                actionTitle: command.title,
                command: joinedCommands(collections.command, update.command, embed.command),
                exitCode: embed.exitCode,
                output: "Update:\n\(update.output)\n\nEmbed:\n\(embed.output)",
                startedAt: collections.startedAt,
                finishedAt: embed.finishedAt
            )
        case .updateIndex:
            let collections = try await ensureAgentMemoryCollectionsIfNeeded()
            guard collections.succeeded else { return collections.labeled(command.title) }
            let update = try await runWithLockRetry(arguments: ["update"])
            return QMDRunResult(
                actionTitle: command.title,
                command: joinedCommands(collections.command, update.command),
                exitCode: update.exitCode,
                output: update.output,
                startedAt: collections.startedAt,
                finishedAt: update.finishedAt
            )
        case .generateEmbeddings:
            return try await runWithLockRetry(arguments: ["embed", "--chunk-strategy", "auto"]).labeled(command.title)
        case .forceRebuildEmbeddings:
            return try await runWithLockRetry(arguments: ["embed", "-f", "--chunk-strategy", "auto"]).labeled(command.title)
        case .ensureCollection:
            let desiredCollections = try agentMemoryCollections()
            let result = try await ensureAgentMemoryCollections(desiredCollections: desiredCollections)
            if result.succeeded {
                await markCollectionsReconciled(desiredCollections)
            }
            return result.labeled(command.title)
        case .doctor:
            return try await runWithLockRetry(arguments: ["doctor"]).labeled(command.title)
        }
    }

    private func ensureAgentMemoryCollectionsIfNeeded() async throws -> QMDRunResult {
        let desiredCollections = try agentMemoryCollections()
        let fingerprint = collectionFingerprint(desiredCollections)
        let cacheKey = normalizedPath(preferences.memoryRoot)
        let now = Date()
        let needsCheck = await Self.collectionCheckCache.needsCheck(
            key: cacheKey,
            fingerprint: fingerprint,
            now: now,
            maximumAge: Self.collectionRecheckInterval
        )

        guard needsCheck else {
            return QMDRunResult(
                actionTitle: "Ensure Collections",
                command: "",
                exitCode: 0,
                output: "Collection reconciliation skipped because the agent-memory folder layout is unchanged.",
                startedAt: now,
                finishedAt: now
            )
        }

        let result = try await ensureAgentMemoryCollections(desiredCollections: desiredCollections)
        if result.succeeded {
            await markCollectionsReconciled(desiredCollections, checkedAt: result.finishedAt)
        }
        return result
    }

    private func ensureAgentMemoryCollections(
        desiredCollections: [QMDCollectionDefinition]
    ) async throws -> QMDRunResult {
        let list = try await runWithLockRetry(arguments: ["collection", "list"])
        try requireSuccess(list)
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
                "--mask",
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

    private func markCollectionsReconciled(
        _ collections: [QMDCollectionDefinition],
        checkedAt: Date = Date()
    ) async {
        await Self.collectionCheckCache.markChecked(
            key: normalizedPath(preferences.memoryRoot),
            fingerprint: collectionFingerprint(collections),
            checkedAt: checkedAt
        )
    }

    private func collectionFingerprint(_ collections: [QMDCollectionDefinition]) -> String {
        collections
            .map { "\($0.name)\u{1F}\(normalizedPath($0.path))\u{1F}\($0.pattern)" }
            .joined(separator: "\u{1E}")
    }

    private func joinedCommands(_ commands: String...) -> String {
        commands.filter { !$0.isEmpty }.joined(separator: " && ")
    }

    private func collectionExists(_ name: String, in collectionList: String) -> Bool {
        collectionList.split(separator: "\n").contains { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            return line.caseInsensitiveCompare("\(name) (qmd://\(name)/)") == .orderedSame
        }
    }

    private func agentMemoryCollections() throws -> [QMDCollectionDefinition] {
        let rootURL = URL(fileURLWithPath: preferences.memoryRoot)
        let directoryURLs = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )

        let folders = try directoryURLs.filter { url in
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            return values.isDirectory == true
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        let names = CollectionNaming.uniqueNames(
            for: folders.map(\.lastPathComponent),
            reserved: ["agent-memory-root"]
        )

        return [
            QMDCollectionDefinition(
                name: "agent-memory-root",
                path: preferences.memoryRoot,
                pattern: "*.md"
            )
        ] + zip(folders, names).map { folder, name in
            QMDCollectionDefinition(
                name: name,
                path: folder.path,
                pattern: preferences.fileMask
            )
        }
    }

    private func collectionNames(from output: String) -> [String] {
        output.split(separator: "\n").compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let marker = line.range(of: " (qmd://"), line.hasSuffix("/)") else { return nil }
            return String(line[..<marker.lowerBound])
        }
    }

    private func collectionDefinition(from output: String, fallbackName: String) -> QMDCollectionDefinition? {
        var name = fallbackName
        var path: String?
        var pattern: String?
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Collection:") {
                name = line.dropFirst("Collection:".count).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Path:") {
                path = line.dropFirst("Path:".count).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Pattern:") {
                pattern = line.dropFirst("Pattern:".count).trimmingCharacters(in: .whitespaces)
            }
        }
        guard let path, let pattern else { return nil }
        return QMDCollectionDefinition(name: name, path: path, pattern: pattern)
    }

    private func collectionAddArguments(_ collection: QMDCollectionDefinition) -> [String] {
        ["collection", "add", collection.path, "--name", collection.name, "--mask", collection.pattern]
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func runWithLockRetry(arguments: [String]) async throws -> QMDRunResult {
        var lastResult: QMDRunResult?

        for attempt in 0...lockRetryDelays.count {
            let result = try await run(arguments: arguments)
            if !isDatabaseLocked(result.output) {
                return result
            }

            lastResult = result
            if attempt < lockRetryDelays.count {
                try await Task.sleep(for: lockRetryDelays[attempt])
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

    private func requireSuccess(_ result: QMDRunResult) throws {
        guard result.succeeded else {
            throw QMDRunnerError.commandFailed(
                command: result.command,
                exitCode: result.exitCode,
                output: result.conciseOutput
            )
        }
    }

    @discardableResult
    private func run(arguments: [String]) async throws -> QMDRunResult {
        try Task.checkCancellation()
        let startedAt = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: preferences.qmdBinaryPath)
        let indexName = preferences.indexName.trimmingCharacters(in: .whitespacesAndNewlines)
        process.arguments = indexName.isEmpty ? arguments : ["--index", indexName] + arguments
        let workingDirectory = URL(fileURLWithPath: preferences.workingDirectory)
        process.currentDirectoryURL = FileManager.default.fileExists(atPath: workingDirectory.path)
            ? workingDirectory
            : URL(fileURLWithPath: preferences.homeDirectory)
        process.environment = environment()

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        let command = commandDescription(arguments: process.arguments ?? [])
        let state = ProcessRunState()
        let output = ProcessOutputBuffer(maximumBytes: Self.maximumCapturedOutputBytes)
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            output.append(data)
        }

        let result: QMDRunResult = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<QMDRunResult, Error>) in
                let timeoutTask = Task {
                    do {
                        try await Task.sleep(for: .seconds(preferences.commandTimeoutSeconds))
                    } catch {
                        return
                    }
                    state.requestTermination(.timedOut) {
                        if process.isRunning {
                            process.terminate()
                        }
                    }
                }

                process.terminationHandler = { terminatedProcess in
                    timeoutTask.cancel()
                    state.finish { reason in
                        outputPipe.fileHandleForReading.readabilityHandler = nil
                        switch reason {
                        case .cancelled:
                            continuation.resume(throwing: CancellationError())
                        case .timedOut:
                            continuation.resume(throwing: QMDRunnerError.timedOut(
                                command: command,
                                seconds: preferences.commandTimeoutSeconds
                            ))
                        case nil:
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
                }

                do {
                    if let reason = state.terminationReason {
                        timeoutTask.cancel()
                        state.finish { _ in
                            outputPipe.fileHandleForReading.readabilityHandler = nil
                            switch reason {
                            case .cancelled:
                                continuation.resume(throwing: CancellationError())
                            case .timedOut:
                                continuation.resume(throwing: QMDRunnerError.timedOut(
                                    command: command,
                                    seconds: preferences.commandTimeoutSeconds
                                ))
                            }
                        }
                        return
                    }
                    try process.run()
                    if state.terminationReason != nil, process.isRunning {
                        process.terminate()
                    }
                } catch {
                    timeoutTask.cancel()
                    state.finish { reason in
                        outputPipe.fileHandleForReading.readabilityHandler = nil
                        switch reason {
                        case .cancelled:
                            continuation.resume(throwing: CancellationError())
                        case .timedOut:
                            continuation.resume(throwing: QMDRunnerError.timedOut(
                                command: command,
                                seconds: preferences.commandTimeoutSeconds
                            ))
                        case nil:
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        } onCancel: {
            state.requestTermination(.cancelled) {
                outputPipe.fileHandleForReading.readabilityHandler = nil
                if process.isRunning {
                    process.terminate()
                }
            }
        }
        try Task.checkCancellation()
        return result
    }

    private func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = preferences.homeDirectory
        if preferences.useGPU {
            env.removeValue(forKey: "QMD_LLAMA_GPU")
        } else {
            env["QMD_LLAMA_GPU"] = "false"
        }
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
    private let maximumBytes: Int
    private var data = Data()
    private var wasTruncated = false

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    var string: String {
        lock.lock()
        let snapshot = data
        let truncated = wasTruncated
        lock.unlock()
        let decoded = String(decoding: snapshot, as: UTF8.self)
        return truncated ? "[Earlier output truncated]\n\(decoded)" : decoded
    }

    func append(_ newData: Data) {
        lock.lock()
        if newData.count >= maximumBytes {
            data = Data(newData.suffix(maximumBytes))
            wasTruncated = true
        } else {
            data.append(newData)
            if data.count > maximumBytes {
                data.removeFirst(data.count - maximumBytes)
                wasTruncated = true
            }
        }
        lock.unlock()
    }
}

private final class ProcessRunState: @unchecked Sendable {
    enum TerminationReason {
        case cancelled
        case timedOut
    }

    private let lock = NSLock()
    private var didFinish = false
    private var requestedTermination: TerminationReason?

    var terminationReason: TerminationReason? {
        lock.lock()
        let value = requestedTermination
        lock.unlock()
        return value
    }

    func requestTermination(_ reason: TerminationReason, _ body: () -> Void) {
        lock.lock()
        let shouldRunBody = !didFinish && requestedTermination == nil
        if shouldRunBody {
            requestedTermination = reason
        }
        lock.unlock()
        if shouldRunBody {
            body()
        }
    }

    func finish(_ body: (TerminationReason?) -> Void) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }

        didFinish = true
        let reason = requestedTermination
        lock.unlock()
        body(reason)
    }
}

private actor CollectionCheckCache {
    private struct Entry {
        let fingerprint: String
        let checkedAt: Date
    }

    private var entries: [String: Entry] = [:]

    func needsCheck(
        key: String,
        fingerprint: String,
        now: Date,
        maximumAge: TimeInterval
    ) -> Bool {
        guard let entry = entries[key], entry.fingerprint == fingerprint else {
            return true
        }
        let age = now.timeIntervalSince(entry.checkedAt)
        return age < 0 || age >= maximumAge
    }

    func markChecked(key: String, fingerprint: String, checkedAt: Date) {
        entries[key] = Entry(fingerprint: fingerprint, checkedAt: checkedAt)
    }
}
