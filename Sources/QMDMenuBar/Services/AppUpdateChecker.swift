import Foundation

struct AppUpdateChecker: Sendable {
    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: URL
        let publishedAt: Date?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case publishedAt = "published_at"
        }
    }

    let releasesURL = URL(string: "https://api.github.com/repos/pkidwell22/QMD/releases/latest")!

    func check(currentVersion: String) async throws -> AppUpdateState {
        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("QMDMenuBar/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 404 {
            return .noPublishedReleases
        }
        guard http.statusCode == 200 else {
            let status = http.statusCode
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "GitHub Releases returned HTTP \(status)."])
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let release = try decoder.decode(GitHubRelease.self, from: data)
        let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        if latest.compare(currentVersion, options: .numeric) == .orderedDescending {
            return .available(AppRelease(version: latest, pageURL: release.htmlURL, publishedAt: release.publishedAt))
        }
        return .current(latestVersion: latest)
    }
}
