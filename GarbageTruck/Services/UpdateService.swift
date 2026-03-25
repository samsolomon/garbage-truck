import Foundation
import os

private let logger = Logger(subsystem: "com.garbagetruck.app", category: "UpdateService")

struct Release: Decodable, Sendable {
    let tagName: String
    let htmlUrl: String
    let body: String?
    let assets: [Asset]

    struct Asset: Decodable, Sendable {
        let name: String
        let browserDownloadUrl: String
    }

    var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    var dmgURL: URL? {
        assets.first { $0.name.hasSuffix(".dmg") }
            .flatMap { URL(string: $0.browserDownloadUrl) }
    }
}

enum UpdateState {
    case idle
    case checking
    case available(Release)
    case installing
    case needsRestart
    case failed(String)
}

struct UpdateService: Sendable {
    private static let apiURL = URL(string: "https://api.github.com/repos/samsolomon/garbage-truck/releases/latest")!

    static func checkForUpdate() async throws -> Release? {
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.serverError
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let release = try decoder.decode(Release.self, from: data)

        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        guard isNewer(release.version, than: currentVersion) else {
            return nil
        }

        return release
    }

    static func downloadAndInstall(from url: URL) async throws {
        let appDirectory = Bundle.main.bundleURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: appDirectory.path()) else {
            throw UpdateError.locationNotWritable
        }

        logger.notice("Downloading update from \(url)")
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.downloadFailed
        }

        // URLSession temp files are cleaned up unpredictably; move to a stable path for hdiutil
        let dmgPath = FileManager.default.temporaryDirectory.appending(path: "GarbageTruck-update.dmg")
        try? FileManager.default.removeItem(at: dmgPath)
        try FileManager.default.moveItem(at: tempURL, to: dmgPath)

        defer { try? FileManager.default.removeItem(at: dmgPath) }

        let mountPoint = try await mountDMG(at: dmgPath)
        defer { unmountDMG(at: mountPoint) }

        let contents = try FileManager.default.contentsOfDirectory(
            at: URL(filePath: mountPoint),
            includingPropertiesForKeys: nil
        )
        guard let appBundle = contents.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.appNotFound
        }

        let currentApp = Bundle.main.bundleURL
        logger.notice("Replacing \(currentApp.path()) with \(appBundle.path())")
        _ = try FileManager.default.replaceItemAt(currentApp, withItemAt: appBundle)

        logger.notice("Update installed successfully")
    }

    // MARK: - Private

    private static func mountDMG(at url: URL) async throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/hdiutil")
        process.arguments = ["attach", url.path(percentEncoded: false), "-nobrowse", "-noverify", "-noautoopen", "-plist"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        let status = try await runProcess(process)
        guard status == 0 else {
            throw UpdateError.mountFailed
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first
        else {
            throw UpdateError.mountFailed
        }

        logger.notice("Mounted DMG at \(mountPoint)")
        return mountPoint
    }

    private static func unmountDMG(at mountPoint: String) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountPoint, "-quiet"]
        try? process.run()
        process.waitUntilExit()
    }

    private static func runProcess(_ process: Process) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }
        let count = max(remoteParts.count, localParts.count)
        for i in 0..<count {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }
}

enum UpdateError: LocalizedError {
    case serverError
    case downloadFailed
    case mountFailed
    case appNotFound
    case locationNotWritable

    var errorDescription: String? {
        switch self {
        case .serverError: "Could not reach GitHub."
        case .downloadFailed: "Download failed."
        case .mountFailed: "Could not open the update package."
        case .appNotFound: "Update package was empty."
        case .locationNotWritable: "Move Garbage Truck to the Applications folder before updating."
        }
    }
}
