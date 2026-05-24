import Foundation

struct QMDRunResult: Sendable {
    let command: String
    let exitCode: Int32
    let output: String
    let startedAt: Date
    let finishedAt: Date

    var succeeded: Bool {
        exitCode == 0
    }
}
