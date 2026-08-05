import Foundation
import AppKit
import SwiftUI
import XCTest
@testable import QMDMenuBar

final class QMDStoreTests: XCTestCase {
    @MainActor
    func testSearchModeAndCollectionPersist() throws {
        let defaults = try makeDefaults()
        let store = QMDStore(defaults: defaults, refreshOnLaunch: false)
        store.searchMode = .deep
        store.searchCollection = "qmd"

        let restored = QMDStore(defaults: defaults, refreshOnLaunch: false)

        XCTAssertEqual(restored.searchMode, .deep)
        XCTAssertEqual(restored.searchCollection, "qmd")
    }

    @MainActor
    func testRapidSearchesCancelEarlierWorkAndOnlyPublishLatestResults() async throws {
        let runner = SearchStressRunner()
        let store = QMDStore(
            defaults: try makeDefaults(),
            runnerFactory: { _ in runner },
            refreshOnLaunch: false
        )
        store.searchMode = .fast
        store.searchCollection = "qmd"

        store.searchQuery = "first"
        store.performSearch()
        try await waitUntil { await runner.startedCount == 1 }

        store.searchQuery = "second"
        store.performSearch()
        try await waitUntil { await runner.startedCount == 2 }

        store.searchQuery = "final"
        store.performSearch()
        try await waitUntil {
            !store.isSearching && store.searchResults.first?.displayTitle == "final"
        }

        let cancellationCount = await runner.cancellationCount
        XCTAssertEqual(cancellationCount, 2)
        let calls = await runner.calls
        XCTAssertEqual(calls.map(\.query), ["first", "second", "final"])
        XCTAssertTrue(calls.allSatisfy { $0.mode == .fast && $0.collection == "qmd" && $0.limit == 8 })
        XCTAssertNil(store.searchError)
    }

    @MainActor
    func testLargeCollectionSetFiltersEmptyEntriesAndSortsDeterministically() throws {
        let store = QMDStore(defaults: try makeDefaults(), refreshOnLaunch: false)
        store.status.collections = (0..<150).map { index in
            QMDCollectionStatus(
                name: String(format: "collection-%03d-with-a-deliberately-long-name", 149 - index),
                files: index.isMultiple(of: 5) ? 0 : index + 1
            )
        }

        let collections = store.searchableCollections

        XCTAssertEqual(collections.count, 120)
        XCTAssertTrue(collections.allSatisfy { ($0.files ?? 0) > 0 })
        XCTAssertEqual(collections.map(\.name), collections.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        XCTAssertTrue(menuHeight(store: store).isFinite)
    }

    @MainActor
    func testCancellationWaitsForTerminationBeforeAllowingNewRun() async throws {
        let defaults = try makeDefaults()
        let runner = CancellationRunner()
        let store = QMDStore(
            defaults: defaults,
            runnerFactory: { _ in runner },
            refreshOnLaunch: false
        )

        store.run(.updateIndex)
        try await waitUntil { await runner.startedCount == 1 }
        store.resetActiveCommand()
        store.run(.generateEmbeddings)
        XCTAssertTrue(store.isCancellingCommand)
        let startsWhileCancelling = await runner.currentStartedCount()
        XCTAssertEqual(startsWhileCancelling, 1)
        try await waitUntil { !store.isCancellingCommand }
        store.run(.generateEmbeddings)
        try await waitUntil { await runner.startedCount == 2 }
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertTrue(store.activeCommand == .generateEmbeddings)
        let cancellationCount = await runner.currentCancellationCount()
        XCTAssertEqual(cancellationCount, 1)
        store.resetActiveCommand()
        try await waitUntil { !store.isCancellingCommand }
    }

    @MainActor
    func testRunHistoryPersistsOnlySummaryOutput() async throws {
        let defaults = try makeDefaults()
        let runner = ImmediateRunner(output: String(repeating: "z", count: 100_000))
        let store = QMDStore(
            defaults: defaults,
            runnerFactory: { _ in runner },
            refreshOnLaunch: false
        )

        store.run(.updateIndex)
        try await waitUntil { store.activeCommand == nil && !store.runHistory.isEmpty }

        let data = try XCTUnwrap(defaults.data(forKey: "runHistory"))
        let saved = try JSONDecoder().decode([QMDRunResult].self, from: data)
        XCTAssertEqual(saved.count, 1)
        XCTAssertLessThan(saved[0].output.count, 4_100)
    }

    @MainActor
    func testMenuHeightStaysStableAcrossRunStateTransition() throws {
        let store = QMDStore(defaults: try makeDefaults(), refreshOnLaunch: false)
        let emptyHeight = menuHeight(store: store)

        store.lastResult = QMDRunResult(
            actionTitle: "Update + Embed",
            command: "qmd update && qmd embed",
            exitCode: 0,
            output: "Indexed: 1 new\nEmbedded 1 document\nAll content hashes updated\nalready have embeddings",
            startedAt: Date(timeIntervalSince1970: 10),
            finishedAt: Date(timeIntervalSince1970: 11)
        )
        let completedHeight = menuHeight(store: store)

        store.activeCommand = .updateAndEmbed
        store.activeCommandStartedAt = Date()
        let runningHeight = menuHeight(store: store)

        store.activeCommand = nil
        store.activeCommandStartedAt = nil
        store.isCancellingCommand = true
        let cancellingHeight = menuHeight(store: store)

        XCTAssertEqual(completedHeight, emptyHeight, accuracy: 1)
        XCTAssertEqual(completedHeight, runningHeight, accuracy: 1)
        XCTAssertEqual(completedHeight, cancellingHeight, accuracy: 1)
    }

    @MainActor
    func testMenuHeightStaysStableWhenFirstAutomaticRunFinishes() throws {
        let store = QMDStore(defaults: try makeDefaults(), refreshOnLaunch: false)
        store.automaticUpdatesEnabled = true
        defer { store.automaticUpdatesEnabled = false }
        store.nextAutomaticUpdateAt = Date().addingTimeInterval(300)
        let beforeFirstRun = menuHeight(store: store)

        store.lastAutomaticUpdateAt = Date()
        let afterFirstRun = menuHeight(store: store)

        XCTAssertEqual(beforeFirstRun, afterFirstRun, accuracy: 1)
    }

    @MainActor
    func testMenuHeightStaysStableWhenAppUpdateBecomesAvailable() throws {
        let store = QMDStore(defaults: try makeDefaults(), refreshOnLaunch: false)
        let currentHeight = menuHeight(store: store)

        store.updateState = .available(
            AppUpdate(
                identifier: "2222222222222222222222222222222222222222",
                displayBuild: "2222222",
                pageURL: URL(string: "https://github.com/pkidwell22/Agent-Memory/commit/2222222")!,
                publishedAt: nil,
                summary: "Latest change"
            )
        )
        let updateHeight = menuHeight(store: store)

        XCTAssertEqual(currentHeight, updateHeight, accuracy: 1)
    }

    @MainActor
    func testAdaptiveAutomaticUpdateDelayThrottlesLifecycleEvents() {
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(
            QMDStore.adaptiveAutomaticUpdateDelay(
                requestedDelay: 5,
                now: now,
                lastSuccessfulUpdate: nil
            ),
            5
        )
        XCTAssertEqual(
            QMDStore.adaptiveAutomaticUpdateDelay(
                requestedDelay: 5,
                now: now,
                lastSuccessfulUpdate: now.addingTimeInterval(-60)
            ),
            240
        )
        XCTAssertEqual(
            QMDStore.adaptiveAutomaticUpdateDelay(
                requestedDelay: 5,
                now: now,
                lastSuccessfulUpdate: now.addingTimeInterval(-600)
            ),
            5
        )
    }

    func testMemoryRootMonitorObservesNestedFileChanges() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QMDMenuBarTests-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("collection/nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = nested.appendingPathComponent("note.md")
        try Data("before".utf8).write(to: file)
        let observed = expectation(description: "Nested file change observed")
        let monitor = MemoryRootMonitor()
        monitor.start(path: root.path) {
            observed.fulfill()
        }
        defer { monitor.stop() }

        try Data("after".utf8).write(to: file)
        wait(for: [observed], timeout: 3)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "QMDMenuBarTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @MainActor
    private func menuHeight(store: QMDStore) -> CGFloat {
        let hostingView = NSHostingView(
            rootView: MenuBarContentView(store: store).frame(width: 340)
        )
        hostingView.layoutSubtreeIfNeeded()
        return hostingView.fittingSize.height
    }

    @MainActor
    private func waitUntil(
        timeoutIterations: Int = 100,
        condition: @escaping () async -> Bool
    ) async throws {
        for _ in 0..<timeoutIterations {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition was not met before timeout")
    }
}

private actor CancellationRunner: QMDRunning {
    private(set) var startedCount = 0
    private(set) var cancellationCount = 0

    func status() async throws -> QMDStatus { QMDStatus() }

    func search(
        query: String,
        mode: QMDSearchMode,
        collection: String?,
        limit: Int
    ) async throws -> [QMDSearchResult] { [] }

    func currentCancellationCount() -> Int { cancellationCount }
    func currentStartedCount() -> Int { startedCount }

    func run(command: QMDCommand) async throws -> QMDRunResult {
        startedCount += 1
        let call = startedCount
        let startedAt = Date()

        do {
            try await Task.sleep(for: .seconds(call == 1 ? 10 : 30))
        } catch {
            cancellationCount += 1
            if call == 1 {
                try? await Task.sleep(for: .milliseconds(50))
            } else {
                throw error
            }
        }

        return QMDRunResult(
            actionTitle: command.title,
            command: command.title,
            exitCode: 0,
            output: "completed",
            startedAt: startedAt,
            finishedAt: Date()
        )
    }
}

private struct ImmediateRunner: QMDRunning {
    let output: String

    func status() async throws -> QMDStatus { QMDStatus() }

    func search(
        query: String,
        mode: QMDSearchMode,
        collection: String?,
        limit: Int
    ) async throws -> [QMDSearchResult] { [] }

    func run(command: QMDCommand) async throws -> QMDRunResult {
        QMDRunResult(
            actionTitle: command.title,
            command: command.title,
            exitCode: 0,
            output: output,
            startedAt: Date(),
            finishedAt: Date()
        )
    }
}

private actor SearchStressRunner: QMDRunning {
    struct Call: Sendable {
        let query: String
        let mode: QMDSearchMode
        let collection: String?
        let limit: Int
    }

    private(set) var calls: [Call] = []
    private(set) var cancellationCount = 0
    var startedCount: Int { calls.count }

    func status() async throws -> QMDStatus { QMDStatus() }

    func run(command: QMDCommand) async throws -> QMDRunResult {
        throw CancellationError()
    }

    func search(
        query: String,
        mode: QMDSearchMode,
        collection: String?,
        limit: Int
    ) async throws -> [QMDSearchResult] {
        calls.append(Call(query: query, mode: mode, collection: collection, limit: limit))

        do {
            try await Task.sleep(for: query == "final" ? .milliseconds(20) : .seconds(10))
        } catch {
            cancellationCount += 1
            throw error
        }

        return [QMDSearchResult(
            docid: "#\(query)",
            score: 1,
            file: "qmd://qmd/\(query).md",
            line: 1,
            title: query,
            context: "Stress test",
            snippet: query
        )]
    }
}
