import Foundation

enum QMDSearchMode: String, CaseIterable, Identifiable, Sendable {
    case keyword
    case hybrid

    var id: String { rawValue }
    var title: String { self == .keyword ? "Keyword" : "Hybrid" }
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
