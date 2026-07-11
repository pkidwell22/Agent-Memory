import Foundation

struct QMDCollectionDefinition: Equatable, Sendable {
    let name: String
    let path: String
    let pattern: String
}

struct QMDCollectionChange: Identifiable, Equatable, Sendable {
    enum Action: String, Sendable {
        case add
        case rename
        case replace
        case remove

        var title: String { rawValue.capitalized }
    }

    let id: UUID
    let action: Action
    let existing: QMDCollectionDefinition?
    let desired: QMDCollectionDefinition?
    let detail: String

    init(
        id: UUID = UUID(),
        action: Action,
        existing: QMDCollectionDefinition? = nil,
        desired: QMDCollectionDefinition? = nil,
        detail: String
    ) {
        self.id = id
        self.action = action
        self.existing = existing
        self.desired = desired
        self.detail = detail
    }
}

struct QMDCollectionPlan: Sendable {
    let createdAt: Date
    let changes: [QMDCollectionChange]

    var isEmpty: Bool { changes.isEmpty }
}
