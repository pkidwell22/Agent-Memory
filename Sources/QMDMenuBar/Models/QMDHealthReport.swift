import Foundation

enum QMDHealthState: String, Sendable {
    case passed
    case warning
    case failed

    var systemImage: String {
        switch self {
        case .passed: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }
}

struct QMDHealthItem: Identifiable, Sendable {
    let id: String
    let title: String
    let state: QMDHealthState
    let detail: String
    let remediation: String?
}

struct QMDHealthReport: Sendable {
    let checkedAt: Date
    let qmdVersion: String?
    let resolvedQMDPath: String
    let runtimePath: String?
    let runtimeVersion: String?
    let indexPath: String
    let memoryRoot: String
    let status: QMDStatus?
    let items: [QMDHealthItem]

    var hasFailures: Bool {
        items.contains { $0.state == .failed }
    }
}
