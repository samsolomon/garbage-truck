import Foundation

@testable import GarbageTruck

enum TestFixtures {
    static func makeApp(
        name: String,
        bundleID: String,
        isSystemApp: Bool = false
    ) -> AppInfo {
        AppInfo(
            url: URL(filePath: "/Applications/\(name).app"),
            bundleIdentifier: bundleID,
            name: name,
            version: nil,
            isSystemApp: isSystemApp
        )
    }

    @discardableResult
    static func makeTempDirectory(prefix: String = "test") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func makeTempFile(in dir: URL, name: String = "test.txt", contents: String = "test") throws -> URL {
        let file = dir.appending(path: name)
        try Data(contents.utf8).write(to: file)
        return file
    }
}
