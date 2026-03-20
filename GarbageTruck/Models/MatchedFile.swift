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

    var tooltip: String {
        switch self {
        case .high: "High confidence this file belongs to the app — matched by bundle identifier"
        case .medium: "Medium confidence — matched by app name, may be a false positive"
        }
    }
}

enum FileCategory: String, CaseIterable, Sendable {
    case application = "Application"
    case applicationSupport = "Application Support"
    case preferences = "Preferences"
    case caches = "Caches"
    case containers = "Containers"
    case other = "Other"

    var sortOrder: Int {
        FileCategory.allCases.firstIndex(of: self)!
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
