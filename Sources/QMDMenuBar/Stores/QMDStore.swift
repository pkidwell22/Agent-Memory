import AppKit
import CoreServices
import Foundation
import Network
import Observation
import ServiceManagement

@MainActor
@Observable
final class QMDStore {
    typealias RunnerFactory = @Sendable (QMDPreferences) -> any QMDRunning

    var qmdBinaryPath: String {
        didSet { defaults.set(qmdBinaryPath, forKey: Keys.qmdBinaryPath) }
    }

    var memoryRoot: String {
        didSet {
            defaults.set(memoryRoot, forKey: Keys.memoryRoot)
            configureMemoryRootMonitoring()
            scheduleAutomaticUpdateAfterEvent(requestedDelay: 5)
        }
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

    var workingDirectory: String {
        didSet { defaults.set(workingDirectory, forKey: Keys.workingDirectory) }
    }

    var pathEnvironment: String {
        didSet { defaults.set(pathEnvironment, forKey: Keys.pathEnvironment) }
    }

    var automaticUpdatesEnabled: Bool {
        didSet {
            defaults.set(automaticUpdatesEnabled, forKey: Keys.automaticUpdatesEnabled)
            configureMemoryRootMonitoring()
            if automaticUpdatesEnabled {
                scheduleAutomaticUpdateAfterEvent(requestedDelay: 5)
            } else {
                configureAutomaticTimer()
            }
        }
    }

    var automaticUpdateMinutes: Int {
        didSet {
            defaults.set(automaticUpdateMinutes, forKey: Keys.automaticUpdateMinutes)
            configureAutomaticTimer()
        }
    }

    var useGPU: Bool {
        didSet { defaults.set(useGPU, forKey: Keys.useGPU) }
    }

    private enum RunOrigin {
        case manual
        case automatic
    }

    var status = QMDStatus()
    var lastResult: QMDRunResult?
    var runHistory: [QMDRunResult]
    var lastError: String?
    var activeCommand: QMDCommand?
    var activeCommandStartedAt: Date?
    var isRefreshingStatus = false
    var lastStatusRefreshAt: Date?
    var healthReport: QMDHealthReport?
    var isCheckingHealth = false
    var nextAutomaticUpdateAt: Date?
    var lastAutomaticUpdateAt: Date?
    var launchAtLoginEnabled = false
    var launchAtLoginError: String?
    var searchQuery = ""
    var searchMode: QMDSearchMode = .keyword {
        didSet { defaults.set(searchMode.rawValue, forKey: Keys.searchMode) }
    }
    var searchCollection: String? = nil {
        didSet {
            if let searchCollection {
                defaults.set(searchCollection, forKey: Keys.searchCollection)
            } else {
                defaults.removeObject(forKey: Keys.searchCollection)
            }
        }
    }
    var searchResults: [QMDSearchResult] = []
    var searchError: String?
    var isSearching = false
    var collectionPlan: QMDCollectionPlan?
    var collectionPlanError: String?
    var isPlanningCollections = false
    var updateState: AppUpdateState = .idle
    var isCancellingCommand = false

    private let defaults: UserDefaults
    private let runnerFactory: RunnerFactory
    private var automaticTask: Task<Void, Never>?
    private var commandTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var fileSystemDebounceTask: Task<Void, Never>?
    private var appUpdateTask: Task<Void, Never>?
    private var activeSearchID: UUID?
    private var activeRunID: UUID?
    private var cancelledRunID: UUID?
    private var wakeObserver: NSObjectProtocol?
    private let networkMonitor = NWPathMonitor()
    private let memoryRootMonitor = MemoryRootMonitor()
    private var hasObservedNetworkState = false

    init(
        defaults: UserDefaults = .standard,
        runnerFactory: @escaping RunnerFactory = { QMDRunner(preferences: $0) },
        refreshOnLaunch: Bool = true
    ) {
        self.defaults = defaults
        self.runnerFactory = runnerFactory
        let fallback = QMDPreferences.defaults
        qmdBinaryPath = defaults.string(forKey: Keys.qmdBinaryPath) ?? fallback.qmdBinaryPath
        memoryRoot = defaults.string(forKey: Keys.memoryRoot) ?? fallback.memoryRoot
        if defaults.string(forKey: Keys.collectionName) == "agent-memory" {
            defaults.removeObject(forKey: Keys.collectionName)
        }
        collectionName = defaults.string(forKey: Keys.collectionName) ?? fallback.collectionName
        let savedIndexName = defaults.string(forKey: Keys.indexName)
        if savedIndexName == "obsidian-agent-memory" {
            defaults.removeObject(forKey: Keys.indexName)
            indexName = fallback.indexName
        } else {
            indexName = savedIndexName ?? fallback.indexName
        }
        useGPU = defaults.object(forKey: Keys.useGPU) as? Bool ?? fallback.useGPU
        fileMask = defaults.string(forKey: Keys.fileMask) ?? fallback.fileMask
        workingDirectory = defaults.string(forKey: Keys.workingDirectory) ?? fallback.workingDirectory
        pathEnvironment = defaults.string(forKey: Keys.pathEnvironment) ?? fallback.pathEnvironment
        automaticUpdatesEnabled = defaults.object(forKey: Keys.automaticUpdatesEnabled) as? Bool ?? fallback.automaticUpdatesEnabled
        let savedMinutes = defaults.integer(forKey: Keys.automaticUpdateMinutes)
        automaticUpdateMinutes = savedMinutes > 0 ? savedMinutes : fallback.automaticUpdateMinutes
        searchMode = defaults.string(forKey: Keys.searchMode).flatMap(QMDSearchMode.init(rawValue:)) ?? .keyword
        searchCollection = defaults.string(forKey: Keys.searchCollection)
        runHistory = Self.loadRunHistory(from: defaults)
        lastResult = runHistory.first
        lastAutomaticUpdateAt = defaults.object(forKey: Keys.lastAutomaticUpdateAt) as? Date
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled

        configureLifecycleMonitoring()
        configureMemoryRootMonitoring()
        configureAutomaticTimer(initialDelay: 5)
        if refreshOnLaunch {
            configureAppUpdateTimer()
            Task {
                await runHealthCheck()
                await checkForUpdates()
            }
        }
    }

    var preferences: QMDPreferences {
        var preferences = QMDPreferences.defaults
        preferences.qmdBinaryPath = qmdBinaryPath
        preferences.memoryRoot = memoryRoot
        preferences.collectionName = collectionName
        preferences.indexName = indexName
        preferences.useGPU = useGPU
        preferences.fileMask = fileMask
        preferences.workingDirectory = workingDirectory
        preferences.pathEnvironment = pathEnvironment
        preferences.automaticUpdatesEnabled = automaticUpdatesEnabled
        preferences.automaticUpdateMinutes = automaticUpdateMinutes
        return preferences
    }

    var isRunning: Bool {
        activeCommand != nil || isCancellingCommand || isRefreshingStatus || isCheckingHealth || isSearching || isPlanningCollections
    }

    var searchableCollections: [QMDCollectionStatus] {
        status.collections
            .filter { ($0.files ?? 0) > 0 }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var searchScopeTitle: String {
        searchCollection ?? "All Collections"
    }

    var isCommandRunning: Bool {
        activeCommand != nil
    }

    var menuBarSystemImage: String {
        if activeCommand != nil || isCancellingCommand {
            "arrow.triangle.2.circlepath"
        } else if lastError != nil {
            "exclamationmark.triangle"
        } else {
            "externaldrive.connected.to.line.below"
        }
    }

    func refreshStatus() async {
        guard !isRefreshingStatus, !isCheckingHealth, !isSearching, !isPlanningCollections,
              !isCancellingCommand, activeCommand == nil else { return }
        isRefreshingStatus = true
        defer { isRefreshingStatus = false }

        do {
            applyStatus(try await runnerFactory(preferences).status())
            lastStatusRefreshAt = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshStatusIfStale(maximumAge: TimeInterval = 60) async {
        if let lastStatusRefreshAt,
           Date().timeIntervalSince(lastStatusRefreshAt) < maximumAge {
            return
        }
        await refreshStatus()
    }

    func runHealthCheck() async {
        guard !isCheckingHealth, !isRefreshingStatus, !isSearching, !isPlanningCollections,
              !isCancellingCommand, activeCommand == nil else { return }
        isCheckingHealth = true
        let report = await QMDHealthChecker(preferences: preferences).check()
        healthReport = report
        if let checkedStatus = report.status {
            applyStatus(checkedStatus)
            lastStatusRefreshAt = report.checkedAt
        }
        if report.hasFailures {
            lastError = report.items.first { $0.state == .failed }?.detail
        } else {
            lastError = nil
        }
        isCheckingHealth = false
    }

    private func applyStatus(_ newStatus: QMDStatus) {
        status = newStatus
        if let searchCollection,
           !newStatus.collections.contains(where: {
               $0.name == searchCollection && ($0.files ?? 0) > 0
           }) {
            self.searchCollection = nil
        }
    }

    @discardableResult
    func run(_ command: QMDCommand) -> Bool {
        run(command, origin: .manual)
    }

    @discardableResult
    private func run(_ command: QMDCommand, origin: RunOrigin) -> Bool {
        let runner = runnerFactory(preferences)
        return startRun(command, origin: origin) {
            try await runner.run(command: command)
        }
    }

    @discardableResult
    private func startRun(
        _ command: QMDCommand,
        origin: RunOrigin,
        operation: @escaping @Sendable () async throws -> QMDRunResult
    ) -> Bool {
        guard activeCommand == nil, !isCancellingCommand, !isRefreshingStatus, !isCheckingHealth, !isSearching, !isPlanningCollections else {
            return false
        }
        let runID = UUID()
        activeRunID = runID
        activeCommand = command
        activeCommandStartedAt = Date()
        lastError = nil

        commandTask = Task { [weak self] in
            var shouldRefresh = false
            var outcome: Result<QMDRunResult, Error>

            do {
                outcome = .success(try await operation())
            } catch {
                outcome = .failure(error)
            }

            guard let self else { return }
            if self.cancelledRunID == runID {
                self.cancelledRunID = nil
                self.isCancellingCommand = false
                self.commandTask = nil
                return
            }
            guard self.activeRunID == runID else { return }

            switch outcome {
            case let .success(result):
                self.record(result)
                shouldRefresh = result.succeeded && origin == .manual
                if !result.succeeded {
                    self.lastError = result.conciseOutput
                }
                self.finishAutomaticRunIfNeeded(origin: origin, result: result)
            case let .failure(error):
                let result = QMDRunResult(
                    actionTitle: command.title,
                    command: command.title,
                    exitCode: -1,
                    output: error.localizedDescription,
                    startedAt: Date(),
                    finishedAt: Date()
                )
                self.record(result)
                self.lastError = result.conciseOutput
                self.finishAutomaticRunIfNeeded(origin: origin, result: result)
            }

            self.activeRunID = nil
            self.activeCommand = nil
            self.activeCommandStartedAt = nil
            self.commandTask = nil

            if shouldRefresh {
                if command == .doctor {
                    await self.runHealthCheck()
                } else {
                    await self.refreshStatus()
                }
            }
        }
        return true
    }

    func resetActiveCommand() {
        cancelActiveRun(
            exitCode: -2,
            message: "The run was cancelled manually because QMD was no longer making progress."
        )
    }

    func prepareCollectionReconciliation() async {
        guard !isRunning else { return }
        isPlanningCollections = true
        collectionPlanError = nil
        do {
            collectionPlan = try await QMDRunner(preferences: preferences).collectionReconciliationPlan()
        } catch {
            collectionPlan = nil
            collectionPlanError = error.localizedDescription
        }
        isPlanningCollections = false
    }

    func applyCollectionReconciliation() {
        guard let plan = collectionPlan else { return }
        let runner = QMDRunner(preferences: preferences)
        if startRun(.ensureCollection, origin: .manual, operation: {
            try await runner.applyCollectionPlan(plan)
        }) {
            collectionPlan = nil
        }
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

    func chooseQMDBinary() {
        let panel = NSOpenPanel()
        panel.title = "Choose QMD Executable"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: qmdBinaryPath).deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url {
            qmdBinaryPath = url.path
        }
    }

    func chooseMemoryRoot() {
        let panel = NSOpenPanel()
        panel.title = "Choose Agent-Memory Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: memoryRoot)
        if panel.runModal() == .OK, let url = panel.url {
            memoryRoot = url.path
        }
    }

    func chooseWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose QMD Working Directory"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: workingDirectory)
        if panel.runModal() == .OK, let url = panel.url {
            workingDirectory = url.path
        }
    }

    func performSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, activeCommand == nil, !isCancellingCommand, !isPlanningCollections,
              !isRefreshingStatus, !isCheckingHealth else { return }
        searchTask?.cancel()
        let searchID = UUID()
        activeSearchID = searchID
        searchError = nil
        isSearching = true
        let mode = searchMode
        let collection = searchCollection
        let runner = runnerFactory(preferences)

        searchTask = Task { [weak self] in
            do {
                let results = try await runner.search(
                    query: query,
                    mode: mode,
                    collection: collection,
                    limit: 8
                )
                guard !Task.isCancelled, self?.activeSearchID == searchID else { return }
                self?.searchResults = results
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self?.activeSearchID == searchID else { return }
                self?.searchResults = []
                self?.searchError = error.localizedDescription
            }
            guard self?.activeSearchID == searchID else { return }
            self?.activeSearchID = nil
            self?.isSearching = false
            self?.searchTask = nil
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchTask = nil
        activeSearchID = nil
        isSearching = false
        searchQuery = ""
        searchResults = []
        searchError = nil
    }

    func openSearchResult(_ result: QMDSearchResult) {
        guard !isRunning else { return }
        Task {
            do {
                let path = try await QMDRunner(preferences: preferences).resolvedFilePath(for: result)
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            } catch {
                searchError = error.localizedDescription
            }
        }
    }

    func copySearchResult(_ result: QMDSearchResult) {
        let text = [result.displayTitle, result.file, result.displaySnippet]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        } catch {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            launchAtLoginError = error.localizedDescription
        }
    }

    func checkForUpdates() async {
        if case .checking = updateState { return }
        updateState = .checking
        let currentCommit = Bundle.main.object(forInfoDictionaryKey: "AgentMemoryGitCommit") as? String ?? ""
        do {
            let state = try await AppUpdateChecker().check(currentCommit: currentCommit)
            updateState = state
            if case let .available(update) = state {
                notifyAboutUpdateIfNeeded(update)
            }
        } catch {
            updateState = .failed(error.localizedDescription)
        }
    }

    func openUpdatePage(_ update: AppUpdate) {
        NSWorkspace.shared.open(update.pageURL)
    }

    private func configureAppUpdateTimer() {
        appUpdateTask?.cancel()
        appUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(3_600))
                } catch {
                    break
                }
                await self?.checkForUpdates()
            }
        }
    }

    private func notifyAboutUpdateIfNeeded(_ update: AppUpdate) {
        guard defaults.string(forKey: Keys.lastNotifiedAppUpdate) != update.identifier else { return }
        defaults.set(update.identifier, forKey: Keys.lastNotifiedAppUpdate)
        AppUpdateNotifier.notifyAvailable(update)
    }

    private func configureAutomaticTimer(initialDelay: Int? = nil) {
        automaticTask?.cancel()
        guard automaticUpdatesEnabled else {
            nextAutomaticUpdateAt = nil
            return
        }

        let interval = max(5, automaticUpdateMinutes) * 60
        let firstDelay = initialDelay ?? interval
        automaticTask = Task { [weak self] in
            var delay = firstDelay
            while !Task.isCancelled {
                self?.nextAutomaticUpdateAt = Date().addingTimeInterval(TimeInterval(delay))
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    break
                }
                let started = await self?.runAutomaticUpdate() ?? false
                delay = started ? interval : 60
            }
        }
    }

    private func runAutomaticUpdate() async -> Bool {
        guard automaticUpdatesEnabled, activeCommand == nil, !isCancellingCommand, !isPlanningCollections,
              !isRefreshingStatus, !isCheckingHealth, !isSearching else {
            return false
        }
        return run(.updateAndEmbed, origin: .automatic)
    }

    private func finishAutomaticRunIfNeeded(origin: RunOrigin, result: QMDRunResult) {
        guard origin == .automatic else { return }
        if result.succeeded {
            lastAutomaticUpdateAt = result.finishedAt
            defaults.set(result.finishedAt, forKey: Keys.lastAutomaticUpdateAt)
        } else {
            AutomaticUpdateNotifier.notifyFailure()
        }
    }

    private func configureLifecycleMonitoring() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleAutomaticUpdateAfterEvent(requestedDelay: 5)
            }
        }

        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.hasObservedNetworkState {
                    self.scheduleAutomaticUpdateAfterEvent(requestedDelay: 5)
                } else {
                    self.hasObservedNetworkState = true
                }
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "QMDMenuBar.NetworkMonitor"))
    }

    private func configureMemoryRootMonitoring() {
        fileSystemDebounceTask?.cancel()
        fileSystemDebounceTask = nil
        guard automaticUpdatesEnabled else {
            memoryRootMonitor.stop()
            return
        }

        memoryRootMonitor.start(path: memoryRoot) { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleFileSystemUpdate()
            }
        }
    }

    private func scheduleFileSystemUpdate() {
        fileSystemDebounceTask?.cancel()
        fileSystemDebounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(10))
            } catch {
                return
            }
            self?.scheduleAutomaticUpdateAfterEvent(requestedDelay: 0)
        }
    }

    private func scheduleAutomaticUpdateAfterEvent(requestedDelay: Int) {
        guard automaticUpdatesEnabled else { return }
        let delay = Self.adaptiveAutomaticUpdateDelay(
            requestedDelay: requestedDelay,
            now: Date(),
            lastSuccessfulUpdate: lastAutomaticUpdateAt,
            minimumInterval: 5 * 60
        )
        configureAutomaticTimer(initialDelay: delay)
    }

    static func adaptiveAutomaticUpdateDelay(
        requestedDelay: Int,
        now: Date,
        lastSuccessfulUpdate: Date?,
        minimumInterval: TimeInterval = 5 * 60
    ) -> Int {
        let requested = max(0, requestedDelay)
        guard let lastSuccessfulUpdate else { return requested }
        let remaining = minimumInterval - now.timeIntervalSince(lastSuccessfulUpdate)
        return max(requested, Int(ceil(max(0, remaining))))
    }

    private func cancelActiveRun(exitCode: Int32, message: String) {
        guard let command = activeCommand, let runID = activeRunID else { return }
        let result = QMDRunResult(
            actionTitle: command.title,
            command: command.title,
            exitCode: exitCode,
            output: message,
            startedAt: activeCommandStartedAt ?? Date(),
            finishedAt: Date()
        )
        activeRunID = nil
        cancelledRunID = runID
        isCancellingCommand = true
        commandTask?.cancel()
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
        let summaries = runHistory.map(\.persistedSummary)
        guard let data = try? JSONEncoder().encode(summaries) else { return }
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
        static let useGPU = "useGPU"
        static let fileMask = "fileMask"
        static let workingDirectory = "workingDirectory"
        static let pathEnvironment = "pathEnvironment"
        static let automaticUpdatesEnabled = "automaticUpdatesEnabled"
        static let automaticUpdateMinutes = "automaticUpdateMinutes"
        static let searchMode = "searchMode"
        static let searchCollection = "searchCollection"
        static let runHistory = "runHistory"
        static let lastAutomaticUpdateAt = "lastAutomaticUpdateAt"
        static let lastNotifiedAppUpdate = "lastNotifiedAppUpdate"
    }
}

final class MemoryRootMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "QMDMenuBar.MemoryRootMonitor")
    private var stream: FSEventStreamRef?
    private var eventHandler: (@Sendable () -> Void)?

    func start(path: String, eventHandler: @escaping @Sendable () -> Void) {
        stop()
        guard FileManager.default.fileExists(atPath: path) else { return }

        lock.lock()
        self.eventHandler = eventHandler
        lock.unlock()

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<MemoryRootMonitor>
                .fromOpaque(info)
                .takeUnretainedValue()
                .handleEvent()
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1,
            flags
        ) else {
            clearEventHandler()
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            stop()
            return
        }
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        clearEventHandler()
    }

    private func handleEvent() {
        lock.lock()
        let handler = eventHandler
        lock.unlock()
        handler?()
    }

    private func clearEventHandler() {
        lock.lock()
        eventHandler = nil
        lock.unlock()
    }

    deinit {
        stop()
    }
}
