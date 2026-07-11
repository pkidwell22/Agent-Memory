import SwiftUI

struct SettingsView: View {
    @Bindable var store: QMDStore

    var body: some View {
        Form {
            Section("QMD") {
                LabeledContent("Binary") {
                    HStack {
                        TextField("Binary path", text: $store.qmdBinaryPath)
                        Button("Choose…") { store.chooseQMDBinary() }
                    }
                }
                LabeledContent("Working directory") {
                    HStack {
                        TextField("Working directory", text: $store.workingDirectory)
                        Button("Choose…") { store.chooseWorkingDirectory() }
                    }
                }
                TextField("PATH", text: $store.pathEnvironment)
                LabeledContent("Index", value: "Default QMD index")
                LabeledContent("Collections", value: "iCloud agent-memory directories")
                TextField("File mask", text: $store.fileMask)
            }

            Section("Agent Memory") {
                LabeledContent("Memory root") {
                    HStack {
                        TextField("Memory root", text: $store.memoryRoot)
                        Button("Choose…") { store.chooseMemoryRoot() }
                    }
                }

                Button {
                    store.openMemoryRoot()
                } label: {
                    Label("Open Folder", systemImage: "folder")
                }
            }

            Section("Automatic Updates") {
                Toggle("Use GPU acceleration", isOn: $store.useGPU)
                Toggle("Enable automatic update + embed", isOn: $store.automaticUpdatesEnabled)
                Stepper(value: $store.automaticUpdateMinutes, in: 5...720, step: 5) {
                    Text("Interval: \(store.automaticUpdateMinutes) minutes")
                }

                if let next = store.nextAutomaticUpdateAt, store.automaticUpdatesEnabled {
                    LabeledContent("Next update") {
                        Text(next, style: .relative)
                    }
                }
                if let last = store.lastAutomaticUpdateAt {
                    LabeledContent("Last automatic update", value: DateFormatters.timestamp.string(from: last))
                }

                Toggle("Launch at Login", isOn: Binding(
                    get: { store.launchAtLoginEnabled },
                    set: { store.setLaunchAtLogin($0) }
                ))
                if let error = store.launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            HealthSection(store: store)
            CollectionReconciliationSection(store: store)
            UpdatesSection(store: store)
            DiagnosticsSection(store: store)
            RecentRunsSection(store: store)
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 680, height: 720)
    }
}

private struct UpdatesSection: View {
    let store: QMDStore

    var body: some View {
        Section("Updates") {
            LabeledContent(
                "Installed version",
                value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
            )

            switch store.updateState {
            case .idle:
                Text("Check GitHub Releases for a newer signed build.")
                    .foregroundStyle(.secondary)
            case .checking:
                Label("Checking…", systemImage: "arrow.triangle.2.circlepath")
            case .noPublishedReleases:
                Text("No GitHub Releases have been published yet.")
                    .foregroundStyle(.secondary)
            case let .current(latestVersion):
                Label("Up to date (\(latestVersion))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case let .available(release):
                VStack(alignment: .leading, spacing: 6) {
                    Label("Version \(release.version) is available", systemImage: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                    Button("Open Release Page") {
                        store.openReleasePage(release)
                    }
                }
            case let .failed(message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await store.checkForUpdates() }
            } label: {
                Label("Check for Updates", systemImage: "arrow.clockwise")
            }
            .disabled(store.updateState.isChecking)
        }
    }
}

private extension AppUpdateState {
    var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }
}

private struct CollectionReconciliationSection: View {
    let store: QMDStore
    @State private var isConfirmingApply = false

    var body: some View {
        Section("Collection Reconciliation") {
            Text("Compare QMD collections with the folders currently present in agent-memory before making changes.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let error = store.collectionPlanError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let plan = store.collectionPlan {
                if plan.isEmpty {
                    Label("Collections already match agent-memory.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    ForEach(plan.changes) { change in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(change.action.title)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(change.action == .remove || change.action == .replace ? Color.orange : Color.accentColor)
                            Text(change.detail)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 2)
                    }

                    Button(role: .destructive) {
                        isConfirmingApply = true
                    } label: {
                        Label("Apply \(plan.changes.count) Changes", systemImage: "checkmark.circle")
                    }
                    .disabled(store.isRunning)
                }
            }

            Button {
                Task { await store.prepareCollectionReconciliation() }
            } label: {
                Label(store.isPlanningCollections ? "Scanning…" : "Preview Changes", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(store.isRunning)
        }
        .confirmationDialog(
            "Apply collection changes?",
            isPresented: $isConfirmingApply,
            titleVisibility: .visible
        ) {
            Button("Apply Changes", role: .destructive) {
                store.applyCollectionReconciliation()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Stale collections will be removed. Replacements remove and re-add a collection, so collection-specific contexts may need to be restored afterward.")
        }
    }
}

private struct HealthSection: View {
    let store: QMDStore

    var body: some View {
        Section("Health Check") {
            if let report = store.healthReport {
                ForEach(report.items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(item.title, systemImage: item.state.systemImage)
                            .foregroundStyle(color(for: item.state))
                        Text(item.detail)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        if let remediation = item.remediation {
                            Text(remediation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                }

                LabeledContent("Last checked", value: DateFormatters.timestamp.string(from: report.checkedAt))
            } else {
                Text("Run the health check to verify QMD, its runtime, index, and agent-memory folder.")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    Task { await store.runHealthCheck() }
                } label: {
                    Label(store.isCheckingHealth ? "Checking…" : "Run Health Check", systemImage: "heart.text.square")
                }
                .disabled(store.isRunning)

                Button {
                    store.run(.doctor)
                } label: {
                    Label("Run QMD Doctor", systemImage: "stethoscope")
                }
                .disabled(store.isRunning)
            }
        }
    }

    private func color(for state: QMDHealthState) -> Color {
        switch state {
        case .passed: .green
        case .warning: .orange
        case .failed: .red
        }
    }
}

private struct DiagnosticsSection: View {
    let store: QMDStore

    var body: some View {
        Section("Diagnostics") {
            LabeledContent("Documents", value: store.status.totalDocuments.map(String.init) ?? "Unknown")
            LabeledContent("Vectors", value: store.status.vectors.map(String.init) ?? "Unknown")
            LabeledContent("Collection files", value: store.status.collectionFiles.map(String.init) ?? "Unknown")
            LabeledContent("Last checked", value: store.lastStatusRefreshAt.map(DateFormatters.timestamp.string(from:)) ?? "Never")
            LabeledContent("Newest indexed content", value: store.status.updated ?? "Unknown")
            LabeledContent("Last error", value: store.lastError ?? "None")
            LabeledContent("Last command", value: store.lastResult?.actionTitle ?? "None")
            LabeledContent("Last run", value: store.lastResult?.finishedAtText ?? "Never")
            LabeledContent("Last duration", value: store.lastResult?.durationText ?? "Unknown")

            Button {
                Task { await store.refreshStatus() }
            } label: {
                Label("Refresh Status", systemImage: "arrow.clockwise")
            }
            .disabled(store.isRunning)
        }
    }
}

private struct RecentRunsSection: View {
    let store: QMDStore

    var body: some View {
        Section("Recent Runs") {
            if store.runHistory.isEmpty {
                Text("No QMD commands have been recorded yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(store.runHistory.prefix(8))) { result in
                    RecentRunRow(result: result)
                }

                Button(role: .destructive) {
                    store.clearRunHistory()
                } label: {
                    Label("Clear Run History", systemImage: "trash")
                }
            }
        }
    }
}

private struct RecentRunRow: View {
    let result: QMDRunResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(result.actionTitle, systemImage: result.succeeded ? "checkmark.circle" : "xmark.octagon")
                    .foregroundStyle(result.succeeded ? Color.green : Color.red)
                Spacer()
                Text(result.durationText)
                    .foregroundStyle(.secondary)
            }

            Text(result.finishedAtText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !result.conciseOutput.isEmpty {
                Text(result.conciseOutput)
                    .font(.caption.monospaced())
                    .foregroundStyle(result.succeeded ? Color.secondary : Color.red)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }
}
