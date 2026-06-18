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

            RunStateView(store: store)

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

                if let checkedAt = store.lastStatusRefreshAt ?? store.lastResult?.finishedAt {
                    Text("Checked \(DateFormatters.shortTime.string(from: checkedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let updated = store.status.updated {
                    Text("Newest indexed content \(updated)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HoverIconButton(systemImage: "arrow.clockwise", help: "Refresh status", disabled: store.isRefreshingStatus) {
                Task { await store.refreshStatus() }
            }
        }
    }
}

private struct CommandButton: View {
    let command: QMDCommand
    let store: QMDStore
    var role: ButtonRole?

    var body: some View {
        HoverRowButton(disabled: store.isCommandRunning) {
            store.run(command)
        } label: {
            HStack {
                Label(command.title, systemImage: command.systemImage)
                Spacer()
                if store.activeCommand == command {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
                        .fixedSize()
                        .clipped()
                }
            }
            .frame(height: 26)
            .foregroundStyle(Color.primary)
        }
    }
}

private struct RunStateView: View {
    let store: QMDStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(store.activeCommand == nil ? "Last Run" : "Running", systemImage: "clock.badge.checkmark")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                if let activeCommand = store.activeCommand {
                    Text(activeTitle(for: activeCommand))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let result = store.lastResult {
                    Text(result.succeeded ? "OK" : "Failed")
                        .font(.caption)
                        .foregroundStyle(result.succeeded ? .green : .red)
                }
            }

            if let activeCommand = store.activeCommand {
                Text("\(activeTitle(for: activeCommand)) started \(DateFormatters.shortTime.string(from: store.activeCommandStartedAt ?? Date()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    store.resetActiveCommand()
                } label: {
                    Label("Reset Stuck Run", systemImage: "stop.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            } else if let result = store.lastResult {
                Text("\(result.displayTitle) at \(result.finishedAtText)")
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

    private func activeTitle(for command: QMDCommand) -> String {
        guard store.activeCommandTrigger == .automatic else {
            return command.title
        }

        return "\(command.title) (Automatic)"
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
                HoverIconButton(systemImage: "folder", help: "Open agent-memory") {
                    store.openMemoryRoot()
                }

                HoverIconButton(systemImage: "doc.text.magnifyingglass", help: "Open QMD cache") {
                    store.openQMDCache()
                }

                Spacer()

                HoverTextButton(systemImage: "gearshape", title: "Settings") {
                    openSettings()
                }

                HoverTextButton(title: "Quit") {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}

private struct HoverRowButton<LabelContent: View>: View {
    var disabled = false
    let action: () -> Void
    @ViewBuilder let label: () -> LabelContent

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .background(hoverBackground)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.08)) {
                isHovered = hovering && !disabled
            }
        }
    }

    private var hoverBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isHovered ? Color.primary.opacity(0.10) : Color.clear)
    }
}

private struct HoverIconButton: View {
    let systemImage: String
    var help: String?
    var disabled = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .background(hoverBackground)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .help(help ?? "")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.08)) {
                isHovered = hovering && !disabled
            }
        }
    }

    private var hoverBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isHovered ? Color.primary.opacity(0.10) : Color.clear)
    }
}

private struct HoverTextButton: View {
    var systemImage: String?
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 11)
            .frame(height: 28)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .background(hoverBackground)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.08)) {
                isHovered = hovering
            }
        }
    }

    private var hoverBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isHovered ? Color.primary.opacity(0.10) : Color.clear)
    }
}
