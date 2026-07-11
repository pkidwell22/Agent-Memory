import Foundation

struct AppRelease: Sendable {
    let version: String
    let pageURL: URL
    let publishedAt: Date?
}

enum AppUpdateState: Sendable {
    case idle
    case checking
    case noPublishedReleases
    case current(latestVersion: String)
    case available(AppRelease)
    case failed(String)
}
