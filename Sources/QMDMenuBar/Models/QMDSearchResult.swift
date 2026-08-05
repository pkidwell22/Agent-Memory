import Foundation

enum QMDSearchMode: String, CaseIterable, Identifiable, Sendable {
    case keyword
    case fast
    case deep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keyword: "Keyword"
        case .fast: "Fast"
        case .deep: "Deep"
        }
    }

    var help: String {
        switch self {
        case .keyword:
            "Immediate lexical search for exact words, names, paths, and commands."
        case .fast:
            "Direct semantic + lexical retrieval without query expansion or reranking. Exact-looking queries use keyword search."
        case .deep:
            "Full query expansion and reranking. Best used with a collection scope."
        }
    }

    func effectiveMode(for query: String) -> QMDSearchMode {
        self == .fast && Self.prefersKeywordSearch(query) ? .keyword : self
    }

    static func prefersKeywordSearch(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercase = trimmed.lowercased()
        let quoteCount = trimmed.filter { $0 == "\"" }.count
        let commandPrefixes = ["qmd ", "git ", "gh ", "swift ", "bun ", "npm ", "curl "]
        let fileExtensions = [".md", ".txt", ".json", ".swift", ".sh", ".yml", ".yaml", ".toml", ".plist"]
        let tokens = lowercase.split { $0.isWhitespace }
        let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?)]}")
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")

        return quoteCount > 0
            || trimmed.contains("`")
            || lowercase.contains("qmd://")
            || lowercase.hasPrefix("--")
            || lowercase.contains(" --")
            || trimmed.contains("/")
            || commandPrefixes.contains { lowercase.hasPrefix($0) }
            || tokens.contains { token in
                let normalized = String(token).trimmingCharacters(in: trailingPunctuation)
                return fileExtensions.contains { normalized.hasSuffix($0) }
            }
            || tokens.contains { token in
                let normalized = String(token).trimmingCharacters(in: trailingPunctuation)
                guard normalized.hasPrefix("#"), normalized.count >= 7 else { return false }
                return normalized.dropFirst().unicodeScalars.allSatisfy(hexadecimal.contains)
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
