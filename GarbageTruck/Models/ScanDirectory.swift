import Foundation

struct ScanDirectory: Sendable {
    let url: URL
    let category: FileCategory

    static func userDirectories() -> [ScanDirectory] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let lib = home.appending(path: "Library")

        return [
            ScanDirectory(url: lib.appending(path: "Application Support"), category: .applicationSupport),
            ScanDirectory(url: lib.appending(path: "Application Support/CrashReporter"), category: .other),
            ScanDirectory(url: lib.appending(path: "Preferences"), category: .preferences),
            ScanDirectory(url: lib.appending(path: "Preferences/ByHost"), category: .preferences),
            ScanDirectory(url: lib.appending(path: "Caches"), category: .caches),
            ScanDirectory(url: lib.appending(path: "Containers"), category: .containers),
            ScanDirectory(url: lib.appending(path: "Group Containers"), category: .containers),
            ScanDirectory(url: lib.appending(path: "Logs"), category: .other),
            ScanDirectory(url: lib.appending(path: "Saved Application State"), category: .other),
            ScanDirectory(url: lib.appending(path: "HTTPStorages"), category: .other),
            ScanDirectory(url: lib.appending(path: "Cookies"), category: .other),
            ScanDirectory(url: lib.appending(path: "WebKit"), category: .other),
            ScanDirectory(url: lib.appending(path: "LaunchAgents"), category: .other),
        ]
    }
}
