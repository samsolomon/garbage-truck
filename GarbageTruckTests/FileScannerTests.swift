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

    // MARK: - Scan result sorting

    @Test func scanResultsSortedByConfidenceThenCategoryThenName() throws {
        let tmpDir = try TestFixtures.makeTempDirectory(prefix: "sortTest")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let cacheDir = tmpDir.appending(path: "Caches")
        let prefDir = tmpDir.appending(path: "Preferences")
        let supportDir = tmpDir.appending(path: "Application Support")
        for dir in [cacheDir, prefDir, supportDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // High confidence (bundle ID match) in caches
        FileManager.default.createFile(
            atPath: cacheDir.appending(path: "com.example.tbx.cache").path(percentEncoded: false), contents: nil)
        // High confidence (bundle ID match) in application support
        FileManager.default.createFile(
            atPath: supportDir.appending(path: "com.example.tbx").path(percentEncoded: false), contents: nil)
        // Medium confidence (name match only) in preferences
        // "Toolbox" doesn't appear in the bundle ID, so it matches via tier 4 (app name)
        FileManager.default.createFile(
            atPath: prefDir.appending(path: "Toolbox Helper.plist").path(percentEncoded: false), contents: nil)

        // Bundle ID last component "tbx" is < 4 chars, so tier 3 is skipped.
        // "Toolbox Helper.plist" will only match via tier 4 (app name, medium confidence).
        let app = TestFixtures.makeApp(name: "Toolbox", bundleID: "com.example.tbx")
        let engine = MatchingEngine()
        var allFiles: [MatchedFile] = []
        let dirs = [
            ScanDirectory(url: supportDir, category: .applicationSupport),
            ScanDirectory(url: prefDir, category: .preferences),
            ScanDirectory(url: cacheDir, category: .caches),
        ]
        for dir in dirs {
            allFiles.append(contentsOf: engine.findMatches(for: app, in: dir))
        }

        // Use the same sort comparator as FileScanner
        allFiles.sort(by: FileScanner.displayOrder)

        try #require(allFiles.count == 3)

        // All high confidence files should appear before any medium
        let highFiles = allFiles.filter { $0.confidence == .high }
        let medFiles = allFiles.filter { $0.confidence == .medium }
        try #require(highFiles.count == 2)
        try #require(medFiles.count == 1)

        let lastHighIndex = try #require(allFiles.lastIndex(where: { $0.confidence == .high }))
        let firstMedIndex = try #require(allFiles.firstIndex(where: { $0.confidence == .medium }))
        #expect(lastHighIndex < firstMedIndex)

        // Within high confidence, applicationSupport (sortOrder 1) before caches (sortOrder 3)
        #expect(allFiles[0].category == .applicationSupport)
        #expect(allFiles[1].category == .caches)
        #expect(allFiles[2].confidence == .medium)
    }

    // MARK: - Deduplication across directories

    @Test func deduplication_sameFileScanTwice() throws {
        let tmpDir = try TestFixtures.makeTempDirectory(prefix: "dedupTest")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        FileManager.default.createFile(
            atPath: tmpDir.appending(path: "com.test.myapp.plist").path(), contents: nil)

        let app = TestFixtures.makeApp(name: "MyApp", bundleID: "com.test.myapp")
        let engine = MatchingEngine()
        let dir = ScanDirectory(url: tmpDir, category: .preferences)
        let matches1 = engine.findMatches(for: app, in: dir)
        let matches2 = engine.findMatches(for: app, in: dir)

        // Combine and deduplicate like FileScanner does
        var allFiles = matches1 + matches2
        var seen = Set<URL>()
        allFiles = allFiles.filter { seen.insert($0.id).inserted }

        #expect(matches1.count == 1)
        #expect(matches2.count == 1)
        #expect(allFiles.count == 1, "Duplicate file should be deduplicated to a single entry")
    }
}
