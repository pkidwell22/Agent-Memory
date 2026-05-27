import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class QMDStore {
    var qmdBinaryPath: String {
        didSet { defaults.set(qmdBinaryPath, forKey: Keys.qmdBinaryPath) }
    }

    var memoryRoot: String {
        didSet { defaults.set(memoryRoot, forKey: Keys.memoryRoot) }
    }

    var collectionName: String {
        didSet { defaults.set(collectionName, forKey: Keys.collectionName) }
    }

    var indexName: String {
        didSet { defaults.set(indexName, forKey: Keys.indexName) }
    }

    var fileMask: String {
        didSet { defaults.set(fileMask, forKey: Keys.fileMask) }
    }

    var automaticUpdatesEnabled: Bool {
        didSet {
            defaults.set(automaticUpdatesEnabled, forKey: Keys.automaticUpdatesEnabled)
            configureAutomaticTimer()
        }
    }

    var automaticUpdateMinutes: Int {
        didSet {
            defaults.set(automaticUpdateMinutes, forKey: Keys.automaticUpdateMinutes)
            configureAutomaticTimer()
        }
    }

    var status = QMDStatus()
    var lastResult: QMDRunResult?
    var runHistory: [QMDRunResult]
    var lastError: String?
    var activeCommand: QMDCommand?
    var activeCommandStartedAt: Date?
    var isRefreshingStatus = false
    var lastStatusRefreshAt: Date?

    private let defaults: UserDefaults
    private var automaticTask: Task<Void, Never>?
    private var commandWatchdogTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let fallback = QMDPreferences.defaults
        qmdBinaryPath = defaults.string(forKey: Keys.qmdBinaryPath) ?? fallback.qmdBinaryPath
        memoryRoot = defaults.string(forKey: Keys.memoryRoot) ?? fallback.memoryRoot
        collectionName = defaults.string(forKey: Keys.collectionName) ?? fallback.collectionName
        indexName = defaults.string(forKey: Keys.indexName) ?? fallback.indexName
        fileMask = defaults.string(forKey: Keys.fileMask) ?? fallback.fileMask
        automaticUpdatesEnabled = defaults.object(forKey: Keys.automaticUpdatesEnabled) as? Bool ?? fallback.automaticUpdatesEnabled
        let savedMinutes = defaults.integer(forKey: Keys.automaticUpdateMinutes)
        automaticUpdateMinutes = savedMinutes > 0 ? savedMinutes : fallback.automaticUpdateMinutes
        runHistory = Self.loadRunHistory(from: defaults)
        lastResult = runHistory.first

        configureAutomaticTimer()
        Task { await refreshStatus() }
    }

    var preferences: QMDPreferences {
        var preferences = QMDPreferences.defaults
        preferences.qmdBinaryPath = qmdBinaryPath
        preferences.memoryRoot = memoryRoot
        preferences.collectionName = collectionName
        preferences.indexName = indexName
        preferences.fileMask = fileMask
        preferences.automaticUpdatesEnabled = automaticUpdatesEnabled
        preferences.automaticUpdateMinutes = automaticUpdateMinutes
        return preferences
    }

    var isRunning: Bool {
        activeCommand != nil || isRefreshingStatus
    }

    var isCommandRunning: Bool {
        activeCommand != nil
    }

    var menuBarSystemImage: String {
        if activeCommand != nil {
            "arrow.triangle.2.circlepath"
        } else if lastError != nil {
            "exclamationmark.triangle"
        } else {
            "externaldrive.connected.to.line.below"
        }
    }

    func refreshStatus() async {
        guard !isRefreshingStatus else { return }
        isRefreshingStatus = true
        defer { isRefreshingStatus = false }

        do {
            status = try await QMDRunner(preferences: preferences).status()
            lastStatusRefreshAt = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func run(_ command: QMDCommand) {
        guard activeCommand == nil else { return }
        activeCommand = command
        activeCommandStartedAt = Date()
        lastError = nil
        startCommandWatchdog(for: command)

        Task {
            var shouldRefresh = false

            do {
                let result = try await QMDRunner(preferences: preferences).run(command: command)
                record(result)
                shouldRefresh = result.succeeded
                if !result.succeeded {
                    lastError = result.conciseOutput
                }
            } catch {
                let result = QMDRunResult(
                    actionTitle: command.title,
                    command: command.title,
                    exitCode: -1,
                    output: error.localizedDescription,
                    startedAt: Date(),
                    finishedAt: Date()
                )
                record(result)
                lastError = result.conciseOutput
            }

            activeCommand = nil
            activeCommandStartedAt = nil
            commandWatchdogTask?.cancel()
            commandWatchdogTask = nil

            if shouldRefresh {
                await refreshStatus()
            }
        }
    }

    func resetActiveCommand() {
        guard let command = activeCommand else { return }
        let result = QMDRunResult(
            actionTitle: command.title,
            command: command.title,
            exitCode: -2,
            output: "Run state was reset manually because QMD was no longer making progress.",
            startedAt: activeCommandStartedAt ?? Date(),
            finishedAt: Date()
        )
        record(result)
        activeCommand = nil
        activeCommandStartedAt = nil
        commandWatchdogTask?.cancel()
        commandWatchdogTask = nil
        lastError = result.conciseOutput
    }

    func clearRunHistory() {
        runHistory = []
        lastResult = nil
        defaults.removeObject(forKey: Keys.runHistory)
    }

    func openMemoryRoot() {
        NSWorkspace.shared.open(URL(fileURLWithPath: memoryRoot))
    }

    func openQMDCache() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "\(preferences.homeDirectory)/.cache/qmd"))
    }

    private func configureAutomaticTimer() {
        automaticTask?.cancel()
        guard automaticUpdatesEnabled else { return }

        let seconds = max(5, automaticUpdateMinutes) * 60
        automaticTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                await self?.runAutomaticUpdate()
            }
        }
    }

    private func runAutomaticUpdate() async {
        guard activeCommand == nil else { return }
        run(.updateAndEmbed)
    }

    private func startCommandWatchdog(for command: QMDCommand) {
        commandWatchdogTask?.cancel()
        let timeout = UInt64(QMDPreferences.defaults.commandTimeoutSeconds + 15)

        commandWatchdogTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Int(timeout)))
            self?.expireStuckCommand(command)
        }
    }

    private func expireStuckCommand(_ command: QMDCommand) {
        guard activeCommand == command else { return }
        let result = QMDRunResult(
            actionTitle: command.title,
            command: command.title,
            exitCode: -3,
            output: "Run state expired automatically because QMD did not finish within the app watchdog window.",
            startedAt: activeCommandStartedAt ?? Date(),
            finishedAt: Date()
        )
        record(result)
        activeCommand = nil
        activeCommandStartedAt = nil
        lastError = result.conciseOutput
    }

    private func record(_ result: QMDRunResult) {
        lastResult = result
        runHistory.insert(result, at: 0)
        runHistory = Array(runHistory.prefix(20))
        persistRunHistory()
    }

    private func persistRunHistory() {
        guard let data = try? JSONEncoder().encode(runHistory) else { return }
        defaults.set(data, forKey: Keys.runHistory)
    }

    private static func loadRunHistory(from defaults: UserDefaults) -> [QMDRunResult] {
        guard let data = defaults.data(forKey: Keys.runHistory),
              let history = try? JSONDecoder().decode([QMDRunResult].self, from: data) else {
            return []
        }

        return history.sorted { $0.finishedAt > $1.finishedAt }
    }

    private enum Keys {
        static let qmdBinaryPath = "qmdBinaryPath"
        static let memoryRoot = "memoryRoot"
        static let collectionName = "collectionName"
        static let indexName = "indexName"
        static let fileMask = "fileMask"
        static let automaticUpdatesEnabled = "automaticUpdatesEnabled"
        static let automaticUpdateMinutes = "automaticUpdateMinutes"
        static let runHistory = "runHistory"
    }
}
