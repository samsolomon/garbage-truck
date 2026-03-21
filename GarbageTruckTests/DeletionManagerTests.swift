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
        #expect(result.failedCount == 0)
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
}
