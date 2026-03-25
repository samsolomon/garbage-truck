import AppKit
import os

private let logger = Logger(subsystem: "com.garbagetruck.app", category: "AppDelegate")

final class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?

    private static var sentinelURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".garbagetruck/last_run")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.global(qos: .utility).async {
            Self.checkPreviousRun()
            Self.writeSentinel("running")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.writeSentinel("exited")
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first,
              url.isFileURL,
              url.pathExtension == "app"
        else { return }
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.pathExtension == "app" else { return }
        guard let appState else { return }
        Task { @MainActor in
            await appState.scanAppByURL(resolved)
        }
    }

    nonisolated private static func checkPreviousRun() {
        let url = Self.sentinelURL
        do {
            let contents = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            if contents == "running" {
                logger.fault("Previous run did not exit cleanly — possible crash")
            }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // Expected on first run
        } catch {
            logger.warning("Could not read sentinel file: \(error.localizedDescription)")
        }
    }

    nonisolated private static func writeSentinel(_ value: String) {
        let url = Self.sentinelURL
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try value.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            logger.warning("Could not write sentinel file: \(error.localizedDescription)")
        }
    }
}
