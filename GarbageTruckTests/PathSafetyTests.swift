import Foundation
import Testing

@testable import GarbageTruck

struct PathSafetyTests {

    // MARK: - Denied paths

    @Test(arguments: [
        "/System/Library/Foo",
        "/usr/bin/python",
        "/usr/sbin/nfsd",
        "/bin/zsh",
        "/sbin/mount",
        "/Library/Apple/something",
        "/private/var/protected/data",
    ])
    func deniedPaths(path: String) {
        let url = URL(filePath: path)
        #expect(PathSafety.isDenied(url), "\(path) should be denied")
    }

    // MARK: - Allowed paths

    @Test(arguments: [
        "/Applications/Foo.app",
    ])
    func allowedPaths(path: String) {
        let url = URL(filePath: path)
        #expect(!PathSafety.isDenied(url), "\(path) should be allowed")
    }

    @Test func allowedPath_userCaches() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appending(path: "Library/Caches/com.foo")
        #expect(!PathSafety.isDenied(url))
    }

    @Test func allowedPath_userAppSupport() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appending(path: "Library/Application Support/Bar")
        #expect(!PathSafety.isDenied(url))
    }
}
