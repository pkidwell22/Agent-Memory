import Foundation

enum CollectionNaming {
    static func canonicalName(for folderName: String) -> String {
        let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        var result = ""
        var pendingSeparator = false

        for scalar in trimmed.unicodeScalars {
            if allowed.contains(scalar) {
                if pendingSeparator, !result.isEmpty, !result.hasSuffix("-") {
                    result.append("-")
                }
                result.unicodeScalars.append(scalar)
                pendingSeparator = false
            } else {
                pendingSeparator = true
            }
        }

        let normalized = result.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return normalized.isEmpty ? "collection" : normalized
    }

    static func uniqueNames(for folderNames: [String], reserved: Set<String> = []) -> [String] {
        var used = Set(reserved.map { $0.lowercased() })

        return folderNames.map { folderName in
            let base = canonicalName(for: folderName)
            var candidate = base
            var suffix = 2

            while used.contains(candidate.lowercased()) {
                candidate = "\(base)-\(suffix)"
                suffix += 1
            }

            used.insert(candidate.lowercased())
            return candidate
        }
    }
}
