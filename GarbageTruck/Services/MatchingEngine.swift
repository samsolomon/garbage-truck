import Foundation

struct MatchingEngine: Sendable {
    private static let minimumNameLength = 4

    func findMatches(for app: AppInfo, in directory: ScanDirectory) -> [MatchedFile] {
        let fm = FileManager()
        guard let contents = try? fm.contentsOfDirectory(
            at: directory.url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var matches: [MatchedFile] = []

        for itemURL in contents {
            if itemURL.standardizedFileURL == app.id.standardizedFileURL { continue }
            if PathSafety.isDenied(itemURL) { continue }

            let itemName = itemURL.lastPathComponent
            let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey])
            let isDir = resourceValues?.isDirectory ?? false

            if let match = matchItem(
                itemName: itemName,
                itemURL: itemURL,
                isDirectory: isDir,
                app: app,
                category: directory.category
            ) {
                matches.append(match)
            }
        }

        return matches
    }

    func matchItem(
        itemName: String,
        itemURL: URL,
        isDirectory: Bool,
        app: AppInfo,
        category: FileCategory
    ) -> MatchedFile? {
        // Tier 1: Bundle ID exact match
        if itemName.localizedCaseInsensitiveContains(app.bundleIdentifier) {
            return makeMatch(itemURL, isDirectory: isDirectory, confidence: .high,
                           reason: .bundleIDExact(app.bundleIdentifier), category: category)
        }

        // Tier 2: Container match (for Containers/Group Containers directories)
        if category == .containers && itemName.contains(app.bundleIdentifier) {
            return makeMatch(itemURL, isDirectory: isDirectory, confidence: .high,
                           reason: .containerMatch(app.bundleIdentifier), category: category)
        }

        // Tier 3: Bundle ID last component match
        let lastComponent = app.bundleIDLastComponent
        if lastComponent.count >= Self.minimumNameLength && !app.isSystemApp
            && itemName.localizedCaseInsensitiveContains(lastComponent) {
            return makeMatch(itemURL, isDirectory: isDirectory, confidence: .high,
                           reason: .bundleIDComponent(lastComponent), category: category)
        }

        // Skip name-based matching for system apps and short names
        guard !app.isSystemApp else { return nil }
        guard app.name.count >= Self.minimumNameLength else { return nil }

        // Tier 4: App name exact match (case-insensitive)
        if itemName.localizedCaseInsensitiveContains(app.name) {
            return makeMatch(itemURL, isDirectory: isDirectory, confidence: .medium,
                           reason: .appNameMatch(app.name), category: category)
        }

        // Tier 5: Normalized app name match
        let itemLower = itemName.lowercased()
        for variant in app.nameVariants.dropFirst() {
            guard variant.count >= Self.minimumNameLength else { continue }
            if itemLower.contains(variant.lowercased()) {
                return makeMatch(itemURL, isDirectory: isDirectory, confidence: .medium,
                               reason: .appNameNormalized(variant), category: category)
            }
        }

        return nil
    }

    private func makeMatch(
        _ url: URL, isDirectory: Bool, confidence: Confidence,
        reason: MatchReason, category: FileCategory
    ) -> MatchedFile {
        MatchedFile(id: url, sizeBytes: nil, confidence: confidence,
                   matchReason: reason, category: category, isDirectory: isDirectory)
    }
}
