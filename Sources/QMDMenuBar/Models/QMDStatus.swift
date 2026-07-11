import Foundation

struct QMDStatus: Sendable {
    var indexPath: String = ""
    var totalDocuments: Int?
    var vectors: Int?
    var updated: String?
    var collectionName: String?
    var collectionFiles: Int?
    var rawText: String = ""

    var summary: String {
        if let totalDocuments, let vectors {
            "\(totalDocuments) docs, \(vectors) vectors"
        } else if rawText.isEmpty {
            "No status yet"
        } else {
            "Status available"
        }
    }

    static func parse(_ text: String, collectionName preferredCollection: String) -> QMDStatus {
        var status = QMDStatus(rawText: text)
        var activeCollection: String?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("Index:") {
                status.indexPath = trimmed.replacingOccurrences(of: "Index:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Total:") {
                status.totalDocuments = firstInteger(in: trimmed)
            } else if trimmed.hasPrefix("Vectors:") {
                status.vectors = firstInteger(in: trimmed)
            } else if trimmed.hasPrefix("Updated:") {
                status.updated = trimmed.replacingOccurrences(of: "Updated:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if trimmed.contains("(qmd://"), trimmed.hasSuffix("/)") {
                activeCollection = trimmed.components(separatedBy: " ").first
                if activeCollection == preferredCollection {
                    status.collectionName = preferredCollection
                }
            } else if trimmed.hasPrefix("Files:"), let active = activeCollection {
                if active == preferredCollection, let files = firstInteger(in: trimmed) {
                    status.collectionFiles = files
                    status.collectionName = preferredCollection
                }
                activeCollection = nil
            }
        }

        return status
    }

    private static func firstInteger(in text: String) -> Int? {
        let digits = text.replacingOccurrences(of: ",", with: "")
            .split { !$0.isNumber }
            .first
            .map(String.init)
        return digits.flatMap(Int.init)
    }
}
