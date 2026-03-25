import AppKit
import os

private let logger = Logger(subsystem: "com.garbagetruck.app", category: "AppDelegate")

private enum AppRoute {
    case showList
    case showApp(appURL: URL?, bundleIdentifier: String?, appName: String?)

    init?(url: URL) {
        guard url.scheme == "garbagetruck" else { return nil }
        switch url.host {
        case "show-list":
            self = .showList
        case "show-app":
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return nil
            }
            let path = components.queryItems?.first(where: { $0.name == "path" })?.value
            let bundleIdentifier = components.queryItems?.first(where: { $0.name == "bundleID" })?.value
            let appName = components.queryItems?.first(where: { $0.name == "name" })?.value
            let appURL = path.map { URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath() }
            if let appURL, appURL.pathExtension != "app" {
                return nil
            }
            guard appURL != nil || bundleIdentifier != nil else {
                return nil
            }
            self = .showApp(appURL: appURL, bundleIdentifier: bundleIdentifier, appName: appName)
        default:
            return nil
        }
    }
}

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

    func applicationDidBecomeActive(_ notification: Notification) {
        guard let appState else { return }
        let hasVisibleWindows = NSApp.windows.contains { $0.isVisible }
        guard !hasVisibleWindows else { return }
        Task { @MainActor in
            appState.handleActivationWithoutVisibleWindows()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.writeSentinel("exited")
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let appState else { return }

        for url in urls {
            if let route = AppRoute(url: url) {
                Task { @MainActor in
                    switch route {
                    case .showList:
                        appState.handleShowListRoute()
                    case .showApp(let appURL, let bundleIdentifier, let appName):
                        await appState.handleShowAppRoute(
                            appURL: appURL,
                            bundleIdentifier: bundleIdentifier,
                            appName: appName
                        )
                    }
                }
                continue
            }

            guard url.isFileURL else { continue }
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            guard resolved.pathExtension == "app" else { continue }
            Task { @MainActor in
                await appState.handleShowAppRoute(appURL: resolved, bundleIdentifier: nil, appName: nil)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag, let appState else { return true }
        Task { @MainActor in
            appState.handleActivationWithoutVisibleWindows()
        }
        return false
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
