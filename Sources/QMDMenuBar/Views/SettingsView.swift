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

            Section("Diagnostics") {
                LabeledContent("Documents", value: store.status.totalDocuments.map(String.init) ?? "Unknown")
                LabeledContent("Vectors", value: store.status.vectors.map(String.init) ?? "Unknown")
                LabeledContent("Collection files", value: store.status.collectionFiles.map(String.init) ?? "Unknown")
                LabeledContent("Last updated", value: store.status.updated ?? "Unknown")
                LabeledContent("Last error", value: store.lastError ?? "None")

                Button {
                    Task { await store.refreshStatus() }
                } label: {
                    Label("Refresh Status", systemImage: "arrow.clockwise")
                }
                .disabled(store.isRunning)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 620)
    }
}
