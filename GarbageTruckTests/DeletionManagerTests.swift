import Foundation
import Testing

@testable import GarbageTruck

struct DeletionManagerTests {
    private let manager = DeletionManager()

    // MARK: - 6a: PathSafety integration

    @Test func systemPathBlocked() {
        let systemURL = URL(filePath: "/System/Library/Foo")
        let result = manager.moveToTrash(files: [systemURL], appName: "TestApp")

        #expect(result.movedCount == 0)
        #expect(result.failedCount == 1)
        #expect(result.record == nil)
        #expect(result.errors.first?.1 == "Protected system path")
    }

    // MARK: - 6b: Successful trash + record

    @Test func successfulTrashAndRecord() throws {
        let dir = try TestFixtures.makeTempDirectory(prefix: "deletionTest")
        let file = try TestFixtures.makeTempFile(in: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = manager.moveToTrash(files: [file], appName: "TestApp")

        #expect(result.movedCount == 1)
        #expect(result.failedCount == 0)
        #expect(result.record != nil)
        #expect(result.record?.appName == "TestApp")
        #expect(result.record?.entries.count == 1)
        #expect(!FileManager.default.fileExists(atPath: file.path()))

        // Clean up: restore from trash then remove
        try result.record?.restore()
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - 6c: Mixed success/failure

    @Test func mixedSuccessAndFailure() throws {
        let dir = try TestFixtures.makeTempDirectory(prefix: "deletionTest")
        let file = try TestFixtures.makeTempFile(in: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        let nonexistent = URL(filePath: "/tmp/nonexistent-\(UUID().uuidString)")
        let result = manager.moveToTrash(files: [file, nonexistent], appName: "MixedApp")

        #expect(result.movedCount == 1)
        #expect(result.failedCount == 1)
        #expect(result.record != nil)
        #expect(result.record?.entries.count == 1)

        // Clean up
        try result.record?.restore()
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - 6d: Restore round-trip

    @Test func restoreRoundTrip() throws {
        let dir = try TestFixtures.makeTempDirectory(prefix: "deletionTest")
        let file = try TestFixtures.makeTempFile(in: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = manager.moveToTrash(files: [file], appName: "RestoreApp")
        #expect(!FileManager.default.fileExists(atPath: file.path()))

        try result.record!.restore()
        #expect(FileManager.default.fileExists(atPath: file.path()))
    }

    // MARK: - 6e: Empty input

    @Test func emptyInput() {
        let result = manager.moveToTrash(files: [], appName: "EmptyApp")

        #expect(result.movedCount == 0)
        #expect(result.failedCount == 0)
        #expect(result.record == nil)
    }

    // MARK: - 6f: Trash nested directory

    @Test func trashNestedDirectory() throws {
        let dir = try TestFixtures.makeTempDirectory(prefix: "deletionTest")
        defer { try? FileManager.default.removeItem(at: dir) }

        let subDir = dir.appending(path: "com.test.app")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try TestFixtures.makeTempFile(in: subDir, name: "cache1.db")
        let nestedDir = subDir.appending(path: "nested")
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        try TestFixtures.makeTempFile(in: nestedDir, name: "cache2.db")

        let result = manager.moveToTrash(files: [subDir], appName: "NestedApp")

        #expect(result.movedCount == 1)
        #expect(result.failedCount == 0)
        #expect(!FileManager.default.fileExists(atPath: subDir.path()))
        #expect(!FileManager.default.fileExists(atPath: nestedDir.path()))

        // Restore and verify the entire tree comes back
        try #require(result.record != nil)
        try result.record!.restore()
        #expect(FileManager.default.fileExists(atPath: subDir.path()))
        #expect(FileManager.default.fileExists(atPath: nestedDir.path()))
    }

    // MARK: - 6g: Restore after partial failure

    @Test func restoreAfterPartialFailure() throws {
        let dir = try TestFixtures.makeTempDirectory(prefix: "deletionTest")
        defer { try? FileManager.default.removeItem(at: dir) }

        let file1 = try TestFixtures.makeTempFile(in: dir, name: "file1.txt")
        let file2 = try TestFixtures.makeTempFile(in: dir, name: "file2.txt")
        let nonexistent = URL(filePath: "/tmp/nonexistent-\(UUID().uuidString)")

        let result = manager.moveToTrash(files: [file1, file2, nonexistent], appName: "PartialApp")

        #expect(result.movedCount == 2)
        #expect(result.failedCount == 1)
        #expect(result.record != nil)
        #expect(result.record?.entries.count == 2)

        // Both files should be gone
        #expect(!FileManager.default.fileExists(atPath: file1.path()))
        #expect(!FileManager.default.fileExists(atPath: file2.path()))

        // Restore should bring back both successfully trashed files
        try result.record!.restore()
        #expect(FileManager.default.fileExists(atPath: file1.path()))
        #expect(FileManager.default.fileExists(atPath: file2.path()))
    }
}
