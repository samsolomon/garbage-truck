import Foundation
import Testing

@testable import GarbageTruck

struct FileScannerTests {

    // MARK: - 8a: computeSize for single file

    @Test func computeSize_singleFile() throws {
        let tmpDir = try TestFixtures.makeTempDirectory(prefix: "sizeTest")
        let file = tmpDir.appending(path: "test.dat")
        try Data(repeating: 0x42, count: 1024).write(to: file)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let size = FileScanner.computeSize(for: file)
        #expect(size > 0)
    }

    // MARK: - 8b: computeSize for directory with nested files

    @Test func computeSize_directoryWithNestedFiles() throws {
        let tmpDir = try TestFixtures.makeTempDirectory(prefix: "sizeTest")
        let subDir = tmpDir.appending(path: "sub")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 512).write(to: tmpDir.appending(path: "a.dat"))
        try Data(repeating: 0x42, count: 512).write(to: subDir.appending(path: "b.dat"))
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let size = FileScanner.computeSize(for: tmpDir)
        #expect(size > 0)
    }

    // MARK: - 8c: computeSize for nonexistent path

    @Test func computeSize_nonexistentPath() {
        let url = URL(filePath: "/tmp/nonexistent-\(UUID().uuidString)")
        let size = FileScanner.computeSize(for: url)
        #expect(size == 0)
    }
}
