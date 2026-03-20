import Foundation

struct MatchedFile: Identifiable, Hashable, Sendable {
    let id: URL
    var sizeBytes: Int64?
    let confidence: Confidence
    let matchReason: MatchReason
    let category: FileCategory
    let isDirectory: Bool
}

enum Confidence: Int, Comparable, CaseIterable, Sendable {
    case high = 2
    case medium = 1

    static func < (lhs: Confidence, rhs: Confidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        }
    }
}

enum FileCategory: String, CaseIterable, Sendable {
    case applicationSupport = "Application Support"
    case preferences = "Preferences"
    case caches = "Caches"
    case containers = "Containers"
    case other = "Other"

    var sortOrder: Int {
        switch self {
        case .applicationSupport: 0
        case .preferences: 1
        case .caches: 2
        case .containers: 3
        case .other: 4
        }
    }
}

enum MatchReason: Hashable, Sendable {
    case bundleIDExact(String)
    case bundleIDComponent(String)
    case containerMatch(String)
    case appNameMatch(String)
    case appNameNormalized(String)

    var description: String {
        switch self {
        case .bundleIDExact(let id): "Bundle ID: \(id)"
        case .bundleIDComponent(let component): "Bundle ID component: \(component)"
        case .containerMatch(let id): "Container: \(id)"
        case .appNameMatch(let name): "App name: \(name)"
        case .appNameNormalized(let name): "Normalized name: \(name)"
        }
    }
}
