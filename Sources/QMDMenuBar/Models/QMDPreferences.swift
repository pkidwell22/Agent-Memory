import Foundation

struct QMDPreferences: Sendable {
    var qmdBinaryPath: String
    var memoryRoot: String
    var collectionName: String
    var indexName: String
    var fileMask: String
    var workingDirectory: String
    var homeDirectory: String
    var pathEnvironment: String
    var npmCachePath: String
    var useGPU: Bool
    var automaticUpdatesEnabled: Bool
    var automaticUpdateMinutes: Int
    var commandTimeoutSeconds: Int

    static var defaults: QMDPreferences {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        return QMDPreferences(
            qmdBinaryPath: "\(home)/qmd/bin/qmd",
            memoryRoot: "\(home)/Library/Mobile Documents/com~apple~CloudDocs/agent-memory",
            collectionName: "agent-memory-root",
            indexName: "",
            fileMask: "**/*.md",
            workingDirectory: "\(home)/qmd",
            homeDirectory: home,
            pathEnvironment: "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(home)/.bun/bin:\(home)/.local/bin",
            npmCachePath: "/tmp/qmd-npm-cache",
            useGPU: false,
            automaticUpdatesEnabled: false,
            automaticUpdateMinutes: 60,
            commandTimeoutSeconds: 180
        )
    }
}
