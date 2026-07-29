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

        let indexedCounts = lines.compactMap(Self.parseIndexedCounts)
        let indexedSummary: String? = indexedCounts.isEmpty ? nil : {
            let totals = indexedCounts.reduce(IndexedCounts()) { partial, counts in
                IndexedCounts(
                    newFiles: partial.newFiles + counts.newFiles,
                    updated: partial.updated + counts.updated,
                    unchanged: partial.unchanged + counts.unchanged,
                    removed: partial.removed + counts.removed
                )
            }
            return "Indexed: \(totals.newFiles) new, \(totals.updated) updated, \(totals.unchanged) unchanged, \(totals.removed) removed"
        }()

        let signalLines = lines.filter { line in
            (indexedSummary == nil && line.contains("Indexed:")) ||
                line.contains("Embedded ") ||
                line.contains("All content hashes") ||
                line.contains("already have embeddings") ||
                line.contains("database is locked") ||
                line.contains("SQLiteError")
        }

        let selected: [String]
        if let indexedSummary {
            selected = [indexedSummary] + signalLines.suffix(1)
        } else {
            selected = signalLines.isEmpty ? Array(lines.suffix(3)) : Array(signalLines.suffix(4))
        }
        let summary = selected.joined(separator: "\n")
        let maximumCharacters = 4_000
        guard summary.count > maximumCharacters else { return summary }
        return "[Earlier summary truncated]\n" + summary.suffix(maximumCharacters)
    }

    private struct IndexedCounts {
        var newFiles = 0
        var updated = 0
        var unchanged = 0
        var removed = 0
    }

    private static func parseIndexedCounts(_ line: String) -> IndexedCounts? {
        let prefix = "Indexed:"
        guard line.hasPrefix(prefix) else { return nil }
        let parts = line.dropFirst(prefix.count).split(separator: ",")
        guard parts.count == 4 else { return nil }

        let expectedLabels = ["new", "updated", "unchanged", "removed"]
        let values = zip(parts, expectedLabels).compactMap { part, label -> Int? in
            let fields = part.split(whereSeparator: \Character.isWhitespace)
            guard fields.count == 2, fields[1] == Substring(label) else { return nil }
            return Int(fields[0])
        }
        guard values.count == 4 else { return nil }

        return IndexedCounts(
            newFiles: values[0],
            updated: values[1],
            unchanged: values[2],
            removed: values[3]
        )
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

    var persistedSummary: QMDRunResult {
        QMDRunResult(
            id: id,
            actionTitle: actionTitle,
            command: command,
            exitCode: exitCode,
            output: conciseOutput,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
    }
}
