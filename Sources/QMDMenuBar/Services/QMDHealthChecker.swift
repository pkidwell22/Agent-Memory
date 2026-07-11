import Foundation

struct QMDHealthChecker: Sendable {
    let preferences: QMDPreferences

    func check() async -> QMDHealthReport {
        let fileManager = FileManager.default
        let configuredQMDURL = URL(fileURLWithPath: preferences.qmdBinaryPath)
        let resolvedQMDPath = configuredQMDURL.resolvingSymlinksInPath().path
        let runtimePath = resolveExecutable(named: "node") ?? resolveExecutable(named: "bun")
        let runtimeVersion = runtimePath.flatMap(probeVersion(executable:))
        var items: [QMDHealthItem] = []

        let qmdIsExecutable = fileManager.isExecutableFile(atPath: resolvedQMDPath)
        items.append(QMDHealthItem(
            id: "qmd-executable",
            title: "QMD executable",
            state: qmdIsExecutable ? .passed : .failed,
            detail: resolvedQMDPath,
            remediation: qmdIsExecutable ? nil : "Choose an executable QMD binary in Settings or reinstall QMD."
        ))

        if let runtimePath {
            items.append(QMDHealthItem(
                id: "runtime",
                title: URL(fileURLWithPath: runtimePath).lastPathComponent == "bun" ? "Bun runtime" : "Node runtime",
                state: runtimeVersion == nil ? .warning : .passed,
                detail: [runtimePath, runtimeVersion].compactMap { $0 }.joined(separator: " — "),
                remediation: runtimeVersion == nil ? "Verify that the runtime can launch with the configured PATH." : nil
            ))
        } else {
            items.append(QMDHealthItem(
                id: "runtime",
                title: "JavaScript runtime",
                state: .failed,
                detail: "No Node or Bun executable was found in the app PATH.",
                remediation: "Install Node or Bun, then add its bin directory to the configured PATH."
            ))
        }

        let memoryRootURL = URL(fileURLWithPath: preferences.memoryRoot)
        var isDirectory: ObjCBool = false
        let memoryRootExists = fileManager.fileExists(atPath: memoryRootURL.path, isDirectory: &isDirectory)
        let memoryRootAccessible = memoryRootExists && isDirectory.boolValue && fileManager.isReadableFile(atPath: memoryRootURL.path)
        items.append(QMDHealthItem(
            id: "memory-root",
            title: "Agent-memory folder",
            state: memoryRootAccessible ? .passed : .failed,
            detail: memoryRootURL.path,
            remediation: memoryRootAccessible ? nil : "Choose an existing readable folder and confirm iCloud Drive is available."
        ))

        var workingDirectoryIsDirectory: ObjCBool = false
        let workingDirectoryExists = fileManager.fileExists(
            atPath: preferences.workingDirectory,
            isDirectory: &workingDirectoryIsDirectory
        )
        items.append(QMDHealthItem(
            id: "working-directory",
            title: "Working directory",
            state: workingDirectoryExists && workingDirectoryIsDirectory.boolValue ? .passed : .failed,
            detail: preferences.workingDirectory,
            remediation: workingDirectoryExists && workingDirectoryIsDirectory.boolValue
                ? nil
                : "Choose an existing working directory in Settings."
        ))

        var qmdVersion: String?
        var qmdStatus: QMDStatus?
        var statusFailure: String?

        if qmdIsExecutable {
            do {
                qmdVersion = try await QMDRunner(preferences: preferences).version()
                items.append(QMDHealthItem(
                    id: "qmd-version",
                    title: "QMD version",
                    state: .passed,
                    detail: qmdVersion ?? "Unknown",
                    remediation: nil
                ))
            } catch {
                items.append(QMDHealthItem(
                    id: "qmd-version",
                    title: "QMD launch",
                    state: .failed,
                    detail: error.localizedDescription,
                    remediation: "Check the QMD binary and app PATH, then reinstall QMD if its native dependencies target a different runtime."
                ))
            }

            do {
                qmdStatus = try await QMDRunner(preferences: preferences).status()
            } catch {
                statusFailure = error.localizedDescription
            }
        }

        let fallbackIndexPath = "\(preferences.homeDirectory)/.cache/qmd/index.sqlite"
        let reportedIndexPath = qmdStatus?.indexPath ?? ""
        let indexPath = reportedIndexPath.isEmpty ? fallbackIndexPath : reportedIndexPath
        let indexExists = fileManager.fileExists(atPath: indexPath)
        let indexAccessible = indexExists && fileManager.isReadableFile(atPath: indexPath) && fileManager.isWritableFile(atPath: indexPath)
        let indexDetail = statusFailure.map { "\(indexPath) — \($0)" } ?? indexPath
        items.append(QMDHealthItem(
            id: "index",
            title: "QMD index",
            state: indexAccessible && statusFailure == nil ? .passed : .failed,
            detail: indexDetail,
            remediation: indexAccessible && statusFailure == nil
                ? nil
                : "Run QMD Doctor. If the runtime ABI is incompatible, rebuild QMD dependencies with the runtime shown above; otherwise run Update Index."
        ))

        return QMDHealthReport(
            checkedAt: Date(),
            qmdVersion: qmdVersion,
            resolvedQMDPath: resolvedQMDPath,
            runtimePath: runtimePath,
            runtimeVersion: runtimeVersion,
            indexPath: indexPath,
            memoryRoot: preferences.memoryRoot,
            status: qmdStatus,
            items: items
        )
    }

    private func resolveExecutable(named name: String) -> String? {
        for directory in preferences.pathEnvironment.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate).resolvingSymlinksInPath().path
            }
        }
        return nil
    }

    private func probeVersion(executable: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--version"]
        process.environment = environment()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func environment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = preferences.homeDirectory
        environment["PATH"] = preferences.pathEnvironment
        environment["npm_config_cache"] = preferences.npmCachePath
        return environment
    }
}
