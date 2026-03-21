import Foundation
import os

private let logger = Logger(subsystem: "com.garbagetruck.app", category: "AppDiscovery")

struct AppDiscoveryService: Sendable {
    static var applicationDirectories: [URL] {
        [
            URL(filePath: "/Applications"),
            URL(filePath: "/Applications/Utilities"),
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications"),
        ]
    }

    func discoverApps() async -> [AppInfo] {
        let searchPaths = Self.applicationDirectories

        var apps: [AppInfo] = []

        for searchPath in searchPaths {
            let fm = FileManager()
            let contents: [URL]
            do {
                contents = try fm.contentsOfDirectory(
                    at: searchPath,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
            } catch {
                if searchPath == Self.applicationDirectories.last {
                    logger.warning("Could not read \(searchPath.path()): \(error.localizedDescription)")
                } else {
                    logger.error("Could not read \(searchPath.path()): \(error.localizedDescription)")
                }
                continue
            }

            for url in contents where url.pathExtension == "app" {
                if let app = appInfo(from: url) {
                    apps.append(app)
                }
            }
        }

        apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return apps
    }

    func appInfo(from url: URL) -> AppInfo? {
        guard let bundle = Bundle(url: url),
              let info = bundle.infoDictionary,
              let bundleID = info["CFBundleIdentifier"] as? String
        else { return nil }

        let name = (info["CFBundleName"] as? String)
            ?? (info["CFBundleDisplayName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent

        let version = info["CFBundleShortVersionString"] as? String
        let isSystemApp = bundleID.hasPrefix("com.apple.")

        return AppInfo(
            url: url,
            bundleIdentifier: bundleID,
            name: name,
            version: version,
            isSystemApp: isSystemApp
        )
    }
}
