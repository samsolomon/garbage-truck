import Foundation

struct ScanIndex: Sendable {
    private static let engine = MatchingEngine()

    /// Scans each library directory once, matching files against all apps.
    /// Returns matched files keyed by app URL.
    static func buildIndex(apps: [AppInfo]) -> [URL: [MatchedFile]] {
        let fm = FileManager()
        let directories = ScanDirectory.userDirectories()
        let appStandardURLs = apps.map { $0.id.standardizedFileURL }
        var index: [URL: [MatchedFile]] = [:]

        for dir in directories {
            let contents: [URL]
            do {
                contents = try fm.contentsOfDirectory(
                    at: dir.url,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
            } catch {
                continue
            }

            for itemURL in contents {
                if PathSafety.isDenied(itemURL) { continue }

                let standardizedItem = itemURL.standardizedFileURL
                let itemName = itemURL.lastPathComponent
                let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey])
                let isDir = resourceValues?.isDirectory ?? false

                for (i, app) in apps.enumerated() {
                    if standardizedItem == appStandardURLs[i] { continue }

                    if let match = engine.matchItem(
                        itemName: itemName,
                        itemURL: itemURL,
                        isDirectory: isDir,
                        app: app,
                        category: dir.category
                    ) {
                        index[app.id, default: []].append(match)
                    }
                }
            }
        }

        return index
    }
}
