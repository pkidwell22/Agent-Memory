import Foundation

struct AppUpdateChecker: Sendable {
    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private struct GitHubCommit: Decodable {
        struct CommitDetails: Decodable {
            struct Committer: Decodable {
                let date: Date?
            }

            let message: String
            let committer: Committer
        }

        let sha: String
        let htmlURL: URL
        let commit: CommitDetails

        enum CodingKeys: String, CodingKey {
            case sha
            case htmlURL = "html_url"
            case commit
        }
    }

    private let dataLoader: DataLoader
    let latestCommitURL = URL(string: "https://api.github.com/repos/pkidwell22/Agent-Memory/commits/main")!

    init(dataLoader: @escaping DataLoader = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }) {
        self.dataLoader = dataLoader
    }

    func check(currentCommit: String) async throws -> AppUpdateState {
        var request = URLRequest(url: latestCommitURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Agent-Memory/\(shortIdentifier(currentCommit))", forHTTPHeaderField: "User-Agent")
        let (data, http) = try await dataLoader(request)
        guard http.statusCode == 200 else {
            let status = http.statusCode
            throw URLError(
                .badServerResponse,
                userInfo: [NSLocalizedDescriptionKey: "GitHub returned HTTP \(status) while checking the latest build."]
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let latest = try decoder.decode(GitHubCommit.self, from: data)
        let latestIdentifier = latest.sha.lowercased()
        if latestIdentifier == currentCommit.lowercased() {
            return .current(latestBuild: shortIdentifier(latestIdentifier))
        }

        return .available(
            AppUpdate(
                identifier: latestIdentifier,
                displayBuild: shortIdentifier(latestIdentifier),
                pageURL: latest.htmlURL,
                publishedAt: latest.commit.committer.date,
                summary: latest.commit.message.components(separatedBy: .newlines).first ?? "New Agent Memory build"
            )
        )
    }

    private func shortIdentifier(_ identifier: String) -> String {
        if identifier.isEmpty { return "development" }
        return String(identifier.prefix(7))
    }
}
