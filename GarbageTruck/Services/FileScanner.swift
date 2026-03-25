import Foundation

struct FileScanner: Sendable {
    private let matchingEngine = MatchingEngine()

    func scan(app: AppInfo) async -> ScanResult {
        let clock = ContinuousClock()
        let start = clock.now

        let directories = ScanDirectory.userDirectories()
        var allFiles: [MatchedFile] = []

        await withTaskGroup(of: [MatchedFile].self) { group in
            for dir in directories {
                group.addTask {
                    let fm = FileManager()
                    guard fm.isReadableFile(atPath: dir.url.path()) else {
                        return []
                    }
                    return matchingEngine.findMatches(for: app, in: dir)
                }
            }

            for await files in group {
                allFiles.append(contentsOf: files)
            }
        }

        // Deduplicate by URL
        var seen = Set<URL>()
        allFiles = allFiles.filter { seen.insert($0.id).inserted }

        // Add the .app bundle itself as the primary item (skip if already trashed)
        if FileManager.default.fileExists(atPath: app.id.path()) {
            allFiles.append(MatchedFile(
                id: app.id,
                confidence: .high,
                matchReason: .bundleIDExact(app.bundleIdentifier),
                category: .application,
                isDirectory: true
            ))
        }

        // Sort: high confidence first, then by category, then by name
        allFiles.sort(by: Self.displayOrder)

        let duration = clock.now - start

        return ScanResult(
            app: app,
            files: allFiles,
            scanDuration: duration
        )
    }

    static let displayOrder: @Sendable (MatchedFile, MatchedFile) -> Bool = { a, b in
        if a.confidence != b.confidence { return a.confidence > b.confidence }
        if a.category.sortOrder != b.category.sortOrder {
            return a.category.sortOrder < b.category.sortOrder
        }
        return a.id.lastPathComponent.localizedCaseInsensitiveCompare(b.id.lastPathComponent) == .orderedAscending
    }

    // NSCache is thread-safe internally
    private nonisolated(unsafe) static let sizeCache: NSCache<NSURL, NSNumber> = {
        let cache = NSCache<NSURL, NSNumber>()
        cache.countLimit = 5000
        return cache
    }()

    static func computeSize(for url: URL) -> Int64 {
        let key = url.standardizedFileURL as NSURL
        if let cached = sizeCache.object(forKey: key) {
            return cached.int64Value
        }

        let fm = FileManager()
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey]

        guard let values = try? url.resourceValues(forKeys: keys) else {
            sizeCache.setObject(NSNumber(value: 0), forKey: key)
            return 0
        }

        let result: Int64
        if values.isDirectory == true {
            var total: Int64 = 0
            if let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
                options: [.skipsHiddenFiles, .producesRelativePathURLs]
            ) {
                for case let fileURL as URL in enumerator {
                    if let fileValues = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey]),
                       let size = fileValues.totalFileAllocatedSize
                    {
                        total += Int64(size)
                    }
                }
            }
            result = total
        } else {
            result = Int64(values.totalFileAllocatedSize ?? 0)
        }

        sizeCache.setObject(NSNumber(value: result), forKey: key)
        return result
    }
}
