import Foundation

struct QMDRunResult: Codable, Identifiable, Sendable {
    let id: UUID
    let actionTitle: String
    let command: String
    let exitCode: Int32
    let output: String
    let startedAt: Date
    let finishedAt: Date
    let trigger: QMDRunTrigger

    enum CodingKeys: String, CodingKey {
        case id
        case actionTitle
        case command
        case exitCode
        case output
        case startedAt
        case finishedAt
        case trigger
    }

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

    var displayTitle: String {
        switch trigger {
        case .manual:
            actionTitle
        case .automatic:
            "\(actionTitle) (Automatic)"
        }
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
                line.contains("temporarily refused to spawn") ||
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
        finishedAt: Date,
        trigger: QMDRunTrigger = .manual
    ) {
        self.id = id
        self.actionTitle = actionTitle
        self.command = command
        self.exitCode = exitCode
        self.output = output
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.trigger = trigger
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        actionTitle = try container.decode(String.self, forKey: .actionTitle)
        command = try container.decode(String.self, forKey: .command)
        exitCode = try container.decode(Int32.self, forKey: .exitCode)
        output = try container.decode(String.self, forKey: .output)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        finishedAt = try container.decode(Date.self, forKey: .finishedAt)
        trigger = try container.decodeIfPresent(QMDRunTrigger.self, forKey: .trigger) ?? .manual
    }

    func labeled(_ actionTitle: String) -> QMDRunResult {
        QMDRunResult(
            id: id,
            actionTitle: actionTitle,
            command: command,
            exitCode: exitCode,
            output: output,
            startedAt: startedAt,
            finishedAt: finishedAt,
            trigger: trigger
        )
    }

    func triggeredBy(_ trigger: QMDRunTrigger) -> QMDRunResult {
        QMDRunResult(
            id: id,
            actionTitle: actionTitle,
            command: command,
            exitCode: exitCode,
            output: output,
            startedAt: startedAt,
            finishedAt: finishedAt,
            trigger: trigger
        )
    }
}

enum QMDRunTrigger: String, Codable, Sendable {
    case manual
    case automatic
}
