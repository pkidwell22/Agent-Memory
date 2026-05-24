import Foundation

struct QMDRunResult: Codable, Identifiable, Sendable {
    let id: UUID
    let actionTitle: String
    let command: String
    let exitCode: Int32
    let output: String
    let startedAt: Date
    let finishedAt: Date

    var succeeded: Bool {
        exitCode == 0
    }

    var duration: TimeInterval {
        finishedAt.timeIntervalSince(startedAt)
    }

    var durationText: String {
        if duration < 1 {
            return String(format: "%.2fs", duration)
        }
        return String(format: "%.1fs", duration)
    }

    var finishedAtText: String {
        DateFormatters.timestamp.string(from: finishedAt)
    }

    var conciseOutput: String {
        let lines = output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let signalLines = lines.filter { line in
            line.contains("Indexed:") ||
                line.contains("Embedded ") ||
                line.contains("All content hashes") ||
                line.contains("already have embeddings") ||
                line.contains("database is locked") ||
                line.contains("SQLiteError")
        }

        let selected = signalLines.isEmpty ? Array(lines.suffix(3)) : Array(signalLines.suffix(4))
        return selected.joined(separator: "\n")
    }

    init(
        id: UUID = UUID(),
        actionTitle: String,
        command: String,
        exitCode: Int32,
        output: String,
        startedAt: Date,
        finishedAt: Date
    ) {
        self.id = id
        self.actionTitle = actionTitle
        self.command = command
        self.exitCode = exitCode
        self.output = output
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    func labeled(_ actionTitle: String) -> QMDRunResult {
        QMDRunResult(
            id: id,
            actionTitle: actionTitle,
            command: command,
            exitCode: exitCode,
            output: output,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
    }
}
