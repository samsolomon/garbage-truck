import Foundation

enum PathSafety {
    static let deniedPrefixes = [
        "/System/", "/usr/bin/", "/usr/sbin/", "/bin/", "/sbin/",
        "/Library/Apple/", "/Library/LaunchDaemons/", "/Library/LaunchAgents/",
        "/private/var/protected/", "/private/var/db/",
    ]

    static func isDenied(_ url: URL) -> Bool {
        let path = url.path()
        return deniedPrefixes.contains { path.hasPrefix($0) }
    }
}
