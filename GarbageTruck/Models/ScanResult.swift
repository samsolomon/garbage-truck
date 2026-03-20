import Foundation

struct ScanResult: Sendable {
    let app: AppInfo
    var files: [MatchedFile]
    let scanDuration: Duration

    var totalSizeBytes: Int64 {
        files.compactMap(\.sizeBytes).reduce(0, +)
    }
}
