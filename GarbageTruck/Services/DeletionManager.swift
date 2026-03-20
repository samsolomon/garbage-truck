import Foundation

struct DeletionRecord: Sendable {
    let date: Date
    let appName: String
    let entries: [(originalURL: URL, trashURL: URL)]

    func restore() throws {
        let fm = FileManager()
        for entry in entries {
            try fm.moveItem(at: entry.trashURL, to: entry.originalURL)
        }
    }
}

struct DeletionResult: Sendable {
    let movedCount: Int
    let failedCount: Int
    let record: DeletionRecord?
    let errors: [(URL, String)]
}

struct DeletionManager: Sendable {
    func moveToTrash(files: [URL], appName: String) -> DeletionResult {
        let fm = FileManager()
        var entries: [(originalURL: URL, trashURL: URL)] = []
        var errors: [(URL, String)] = []

        for url in files {
            if PathSafety.isDenied(url) {
                errors.append((url, "Protected system path"))
                continue
            }

            do {
                var trashURL: NSURL?
                try fm.trashItem(at: url, resultingItemURL: &trashURL)
                if let trashURL = trashURL as URL? {
                    entries.append((originalURL: url, trashURL: trashURL))
                }
            } catch {
                errors.append((url, error.localizedDescription))
            }
        }

        let record = entries.isEmpty ? nil : DeletionRecord(
            date: Date(),
            appName: appName,
            entries: entries
        )

        return DeletionResult(
            movedCount: entries.count,
            failedCount: errors.count,
            record: record,
            errors: errors
        )
    }
}
