import Foundation

enum QMDSearchMode: String, CaseIterable, Identifiable, Sendable {
    case keyword
    case hybrid
    case fastHybrid

    var id: String { rawValue }
    var title: String {
        switch self {
        case .keyword:
            "Keyword"
        case .hybrid:
            "Hybrid"
        case .fastHybrid:
            "Fast"
        }
    }

    var help: String {
        switch self {
        case .keyword:
            "Fast exact-term search without a language model"
        case .hybrid:
            "Hybrid search with candidate reranking"
        case .fastHybrid:
            "Hybrid search without candidate reranking"
        }
    }
}

struct QMDSearchResult: Codable, Identifiable, Sendable {
    let docid: String
    let score: Double?
    let file: String
    let line: Int?
    let title: String?
    let context: String?
    let snippet: String?

    var id: String { "\(docid)-\(file)-\(line ?? 0)" }

    var displayTitle: String {
        guard let title, !title.isEmpty else {
            return URL(fileURLWithPath: file).lastPathComponent
        }
        return title
    }

    var displaySnippet: String {
        let lines = (snippet ?? "")
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.hasPrefix("@@") }
        return lines.prefix(4).joined(separator: "\n")
    }
}
