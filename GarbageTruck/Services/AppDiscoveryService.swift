import Foundation

struct AppDiscoveryService: Sendable {
    func discoverApps() async -> [AppInfo] {
        let searchPaths = [
            URL(filePath: "/Applications"),
            URL(filePath: "/Applications/Utilities"),
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications"),
        ]

        var apps: [AppInfo] = []

        for searchPath in searchPaths {
            let fm = FileManager()
            guard let contents = try? fm.contentsOfDirectory(
                at: searchPath,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

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
