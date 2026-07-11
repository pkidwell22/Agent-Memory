import Foundation
import AppKit
import SwiftUI
import XCTest
@testable import QMDMenuBar

final class QMDStoreTests: XCTestCase {
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
