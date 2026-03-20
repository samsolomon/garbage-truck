import Foundation

struct ScanResult: Sendable {
    let app: AppInfo
    var files: [MatchedFile]
    let scanDuration: Duration
    let skippedDirectories: [URL]

    var totalSizeBytes: Int64 {
        files.compactMap(\.sizeBytes).reduce(0, +)
    }
}
