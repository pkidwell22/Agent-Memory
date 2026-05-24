import SwiftUI

struct SettingsView: View {
    @Bindable var store: QMDStore

    var body: some View {
        Form {
            Section("QMD") {
                TextField("Binary path", text: $store.qmdBinaryPath)
                TextField("Index name", text: $store.indexName)
                TextField("Collection name", text: $store.collectionName)
                TextField("File mask", text: $store.fileMask)
            }

            Section("Agent Memory") {
                TextField("Memory root", text: $store.memoryRoot)

                Button {
                    store.openMemoryRoot()
                } label: {
                    Label("Open Folder", systemImage: "folder")
                }
            }

            Section("Automatic Updates") {
                Toggle("Enable automatic update + embed", isOn: $store.automaticUpdatesEnabled)
                Stepper(value: $store.automaticUpdateMinutes, in: 5...720, step: 5) {
                    Text("Interval: \(store.automaticUpdateMinutes) minutes")
                }
            }

            DiagnosticsSection(store: store)
            RecentRunsSection(store: store)
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 620)
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
