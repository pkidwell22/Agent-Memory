import SwiftUI

struct MenuBarContentView: View {
    @Bindable var store: QMDStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HeaderView(store: store)

            Divider()

            SearchView(store: store)

            Divider()

            VStack(spacing: 8) {
                CommandButton(command: .updateAndEmbed, store: store)
                CommandButton(command: .updateIndex, store: store)
                CommandButton(command: .generateEmbeddings, store: store)
                CommandButton(command: .forceRebuildEmbeddings, store: store, role: .destructive)
                HoverRowButton(disabled: store.isRunning) {
                    openSettings()
                    Task { await store.prepareCollectionReconciliation() }
                } label: {
                    Label("Review Collections", systemImage: "folder.badge.gearshape")
                        .frame(height: 26)
                        .foregroundStyle(Color.primary)
                }
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

            if store.automaticUpdatesEnabled {
                HStack {
                    Text("Next")
                    Spacer()
                    if let next = store.nextAutomaticUpdateAt {
                        Text(next, style: .relative)
                    } else {
                        Text("Scheduling…")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack {
                    Text("Last automatic run")
                    Spacer()
                    if let last = store.lastAutomaticUpdateAt {
                        Text(last, style: .relative)
                    } else {
                        Text("Never")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Divider()

            RunStateView(store: store)

            Divider()

            FooterView(store: store, openSettings: openSettings)
        }
        .padding(14)
    }
}

private struct SearchView: View {
    let store: QMDStore
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField("Search agent memory", text: Bindable(store).searchQuery)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(
                        Color.primary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(isSearchFocused ? 0.24 : 0.12), lineWidth: 1)
                    }
                    .focused($isSearchFocused)
                    .onSubmit { store.performSearch() }

                Button {
                    store.performSearch()
                } label: {
                    if store.isSearching {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isRunning)
                .help("Search")

                Button {
                    isSearchFocused = true
                } label: {
                    Image(systemName: "command")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("f", modifiers: .command)
                .help("Focus search (⌘F)")
            }

            SearchModeSelector(store: store)

            if let error = store.searchError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            if !store.searchResults.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(store.searchResults) { result in
                            SearchResultRow(result: result, store: store)
                        }
                    }
                }
                .frame(maxHeight: 230)
            }
        }
        .onAppear { isSearchFocused = true }
    }
}

private struct SearchModeSelector: View {
    let store: QMDStore

    var body: some View {
        HStack(spacing: 2) {
            ForEach(QMDSearchMode.allCases) { mode in
                let isSelected = store.searchMode == mode
                Button {
                    store.searchMode = mode
                } label: {
                    Text(mode.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .frame(minWidth: 88, minHeight: 26)
                        .background(
                            isSelected ? Color(nsColor: .darkGray) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(
            Color.primary.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }
}

private struct SearchResultRow: View {
    let result: QMDSearchResult
    let store: QMDStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(result.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Button {
                    store.copySearchResult(result)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy result")

                Button {
                    store.openSearchResult(result)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .disabled(store.isRunning)
                .help("Open source file")
            }

            Text(result.file)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !result.displaySnippet.isEmpty {
                Text(result.displaySnippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct HeaderView: View {
    let store: QMDStore

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .center, spacing: 5) {
                HStack(spacing: 9) {
                    Image(systemName: store.menuBarSystemImage)
                        .font(.title2)
                        .foregroundStyle(store.lastError == nil ? Color.accentColor : Color.red)
                        .frame(width: 28, height: 28)

                    Text("QMD Agent Memory")
                        .font(.headline)
                }

                Text(store.status.summary)
                    .foregroundStyle(.secondary)

                if let checkedAt = store.lastStatusRefreshAt ?? store.lastResult?.finishedAt {
                    Text("Checked \(DateFormatters.shortTime.string(from: checkedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not checked yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let updated = store.status.updated {
                    Text("Newest indexed content \(updated)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Newest indexed content unknown")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)

            HoverIconButton(systemImage: "arrow.clockwise", help: "Refresh status", disabled: store.isRunning) {
                Task { await store.refreshStatus() }
            }
        }
    }
}

private struct CommandButton: View {
    let command: QMDCommand
    let store: QMDStore
    var role: ButtonRole?
    @State private var isConfirmingDestructiveRun = false

    var body: some View {
        HoverRowButton(disabled: store.isRunning) {
            if role == .destructive {
                isConfirmingDestructiveRun = true
            } else {
                store.run(command)
            }
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
        .confirmationDialog(
            "Force rebuild all embeddings?",
            isPresented: $isConfirmingDestructiveRun,
            titleVisibility: .visible
        ) {
            Button("Force Rebuild", role: .destructive) {
                store.run(command)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This discards and regenerates every embedding, which can take significant time and compute. You can cancel the active QMD process from the run panel.")
        }
    }
}

private struct RunStateView: View {
    let store: QMDStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(runStateTitle, systemImage: "clock.badge.checkmark")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                if let activeCommand = store.activeCommand {
                    Text(activeCommand.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let result = store.lastResult {
                    Text(result.succeeded ? "OK" : "Failed")
                        .font(.caption)
                        .foregroundStyle(result.succeeded ? .green : .red)
                }
            }

            if store.isCancellingCommand {
                Text("Waiting for the QMD process to exit before another command can start.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let activeCommand = store.activeCommand {
                Text("\(activeCommand.title) started \(DateFormatters.shortTime.string(from: store.activeCommandStartedAt ?? Date()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    store.resetActiveCommand()
                } label: {
                    Label("Cancel Run", systemImage: "stop.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            } else if let result = store.lastResult {
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
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            } else {
                Text("No QMD command has been recorded yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // MenuBarExtra window placement becomes unstable when its intrinsic height
        // changes while open. Reserve the completed-run height for every run state so
        // transitioning through running/canceling/result never re-anchors the window.
        .frame(height: 94, alignment: .top)
    }

    private var runStateTitle: String {
        if store.isCancellingCommand { return "Canceling" }
        return store.activeCommand == nil ? "Last Run" : "Running"
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
                    .lineLimit(1)
            } else if let result = store.lastResult {
                Text("\(result.succeeded ? "Done" : "Failed") at \(DateFormatters.shortTime.string(from: result.finishedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No completed runs yet")
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
