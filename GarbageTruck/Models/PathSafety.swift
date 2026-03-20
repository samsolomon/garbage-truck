import Foundation

enum PathSafety {
    static let deniedPrefixes = [
        "/System/", "/usr/bin/", "/usr/sbin/", "/bin/", "/sbin/",
        "/Library/Apple/", "/private/var/protected/",
    ]

    static func isDenied(_ url: URL) -> Bool {
        let path = url.path()
        return deniedPrefixes.contains { path.hasPrefix($0) }
    }
}
