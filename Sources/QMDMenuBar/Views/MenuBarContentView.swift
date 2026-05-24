import SwiftUI

struct MenuBarContentView: View {
    @Bindable var store: QMDStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HeaderView(store: store)

            Divider()

            VStack(spacing: 8) {
                CommandButton(command: .updateAndEmbed, store: store)
                CommandButton(command: .updateIndex, store: store)
                CommandButton(command: .generateEmbeddings, store: store)
                CommandButton(command: .forceRebuildEmbeddings, store: store, role: .destructive)
                CommandButton(command: .ensureCollection, store: store)
            }

            Divider()

            Toggle(isOn: $store.automaticUpdatesEnabled) {
                Label("Automatic Updates", systemImage: "clock.arrow.circlepath")
            }
            .toggleStyle(.switch)

            HStack {
                Label("Every \(store.automaticUpdateMinutes) min", systemImage: "timer")
                    .foregroundStyle(.secondary)
                Spacer()
                Stepper("", value: $store.automaticUpdateMinutes, in: 5...720, step: 5)
                    .labelsHidden()
            }
            .disabled(!store.automaticUpdatesEnabled)

            Divider()

            LastRunView(result: store.lastResult)

            Divider()

            FooterView(store: store, openSettings: openSettings)
        }
        .padding(14)
    }
}

private struct HeaderView: View {
    let store: QMDStore

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: store.menuBarSystemImage)
                .font(.title2)
                .foregroundStyle(store.lastError == nil ? Color.accentColor : Color.red)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 5) {
                Text("QMD Agent Memory")
                    .font(.headline)

                Text(store.status.summary)
                    .foregroundStyle(.secondary)

                if let updated = store.status.updated {
                    Text("Updated \(updated)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                Task { await store.refreshStatus() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(store.isRunning)
            .help("Refresh status")
        }
    }
}

private struct CommandButton: View {
    let command: QMDCommand
    let store: QMDStore
    var role: ButtonRole?

    var body: some View {
        Button(role: role) {
            store.run(command)
        } label: {
            HStack {
                Label(command.title, systemImage: command.systemImage)
                Spacer()
                if store.activeCommand == command {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .disabled(store.isRunning)
    }
}

private struct LastRunView: View {
    let result: QMDRunResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Last Run", systemImage: "clock.badge.checkmark")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                if let result {
                    Text(result.succeeded ? "OK" : "Failed")
                        .font(.caption)
                        .foregroundStyle(result.succeeded ? .green : .red)
                }
            }

            if let result {
                Text("\(result.actionTitle) at \(result.finishedAtText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Duration \(result.durationText), exit \(result.exitCode)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !result.conciseOutput.isEmpty {
                    Text(result.conciseOutput)
                        .font(.caption.monospaced())
                        .foregroundStyle(result.succeeded ? Color.secondary : Color.red)
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
            } else {
                Text("No QMD command has been recorded yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct FooterView: View {
    let store: QMDStore
    let openSettings: OpenSettingsAction

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = store.lastError, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            } else if let result = store.lastResult {
                Text("\(result.succeeded ? "Done" : "Failed") at \(DateFormatters.shortTime.string(from: result.finishedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    store.openMemoryRoot()
                } label: {
                    Image(systemName: "folder")
                }
                .help("Open agent-memory")

                Button {
                    store.openQMDCache()
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .help("Open QMD cache")

                Spacer()

                Button {
                    openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
    }
}
