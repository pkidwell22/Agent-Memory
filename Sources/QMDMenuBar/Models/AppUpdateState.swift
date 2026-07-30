import Foundation

struct AppUpdate: Sendable {
    let identifier: String
    let displayBuild: String
    let pageURL: URL
    let publishedAt: Date?
    let summary: String
}

enum AppUpdateState: Sendable {
    case idle
    case checking
    case current(latestBuild: String)
    case available(AppUpdate)
    case failed(String)
}
