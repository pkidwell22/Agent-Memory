import Foundation

enum QMDCommand: CaseIterable, Identifiable {
    case updateAndEmbed
    case updateIndex
    case generateEmbeddings
    case forceRebuildEmbeddings
    case ensureCollection

    var id: String {
        switch self {
        case .updateAndEmbed:
            "updateAndEmbed"
        case .updateIndex:
            "updateIndex"
        case .generateEmbeddings:
            "generateEmbeddings"
        case .forceRebuildEmbeddings:
            "forceRebuildEmbeddings"
        case .ensureCollection:
            "ensureCollection"
        }
    }

    var title: String {
        switch self {
        case .updateAndEmbed:
            "Update + Embed"
        case .updateIndex:
            "Update Index"
        case .generateEmbeddings:
            "Generate Embeddings"
        case .forceRebuildEmbeddings:
            "Force Rebuild"
        case .ensureCollection:
            "Ensure Collection"
        }
    }

    var systemImage: String {
        switch self {
        case .updateAndEmbed:
            "arrow.triangle.2.circlepath"
        case .updateIndex:
            "tray.and.arrow.down"
        case .generateEmbeddings:
            "sparkles"
        case .forceRebuildEmbeddings:
            "exclamationmark.arrow.triangle.2.circlepath"
        case .ensureCollection:
            "folder.badge.plus"
        }
    }
}
