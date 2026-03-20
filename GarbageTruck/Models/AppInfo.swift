import Foundation

struct AppInfo: Identifiable, Hashable, Sendable {
    let id: URL // path to .app bundle
    let bundleIdentifier: String
    let name: String
    let version: String?
    let isSystemApp: Bool
    let nameVariants: [String]
    let bundleIDLastComponent: String

    init(url: URL, bundleIdentifier: String, name: String, version: String?, isSystemApp: Bool) {
        self.id = url
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.version = version
        self.isSystemApp = isSystemApp
        self.bundleIDLastComponent = bundleIdentifier.components(separatedBy: ".").last ?? bundleIdentifier
        self.nameVariants = Self.generateNameVariants(name)
    }

    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    private static func generateNameVariants(_ name: String) -> [String] {
        var variants: [String] = [name]

        let lowercased = name.lowercased()
        if lowercased != name { variants.append(lowercased) }

        // Remove spaces and hyphens
        let compacted = name.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
        if compacted != name { variants.append(compacted) }
        let compactedLower = compacted.lowercased()
        if !variants.contains(compactedLower) { variants.append(compactedLower) }

        // Strip trailing version numbers (e.g. "Things3" → "Things")
        let stripped = name.replacingOccurrences(
            of: "\\d+$",
            with: "",
            options: .regularExpression
        )
        if !stripped.isEmpty && stripped != name && !variants.contains(stripped) {
            variants.append(stripped)
        }
        let strippedLower = stripped.lowercased()
        if !stripped.isEmpty && !variants.contains(strippedLower) {
            variants.append(strippedLower)
        }

        return variants
    }
}
