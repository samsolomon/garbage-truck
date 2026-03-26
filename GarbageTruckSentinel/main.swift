import AppKit
import Darwin
import Foundation

private let trashURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash")
private let lockURL = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: "Library")
    .appending(path: "Application Support")
    .appending(path: "GarbageTruck")
    .appending(path: "GarbageTruckSentinel.lock")
private let ignoredBundleIdentifiers: Set<String> = [
    "com.garbagetruck.app",
    "com.garbagetruck.sentinel",
]
private let lockFileDescriptor = acquireLock()

private struct TrashedApp: Hashable {
    let url: URL
    let bundleIdentifier: String?
    let name: String

    var standardizedPath: String {
        url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
    }
}

private final class TrashWatcher {
    private let url: URL
    private let queue: DispatchQueue
    private let handler: @Sendable () -> Void
    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?

    init(url: URL, queue: DispatchQueue, handler: @escaping @Sendable () -> Void) {
        self.url = url
        self.queue = queue
        self.handler = handler
    }

    func start() {
        guard source == nil else { return }

        fileDescriptor = open(url.path(percentEncoded: false), O_EVTONLY)
        guard fileDescriptor >= 0 else {
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: queue
        )
        source.setEventHandler(handler: handler)
        source.setCancelHandler { [fileDescriptor] in
            if fileDescriptor >= 0 {
                close(fileDescriptor)
            }
        }
        self.source = source
        source.resume()
    }

    deinit {
        source?.cancel()
    }
}

private final class SentinelController: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.garbagetruck.sentinel")
    private lazy var watcher = TrashWatcher(url: trashURL, queue: queue) { [weak self] in
        self?.handleTrashChange()
    }
    private var knownPaths = Set<String>()

    func start() {
        knownPaths = Set(currentTrashedApps().map(\.standardizedPath))
        watcher.start()
    }

    private func handleTrashChange() {
        let currentApps = currentTrashedApps()
        let currentPaths = Set(currentApps.map(\.standardizedPath))
        let addedApps = currentApps.filter { !knownPaths.contains($0.standardizedPath) }
        knownPaths = currentPaths

        for app in addedApps {
            routeToMainApp(for: app)
        }
    }

    private func currentTrashedApps() -> [TrashedApp] {
        let fm = FileManager.default
        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: trashURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        return contents.compactMap { url in
            guard url.pathExtension == "app" else { return nil }

            let bundle = Bundle(url: url)
            let bundleIdentifier = bundle?.bundleIdentifier
            if let bundleIdentifier, ignoredBundleIdentifiers.contains(bundleIdentifier) {
                return nil
            }

            let info = bundle?.infoDictionary
            let name = (info?["CFBundleName"] as? String)
                ?? (info?["CFBundleDisplayName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent

            return TrashedApp(url: url, bundleIdentifier: bundleIdentifier, name: name)
        }
    }

    private func routeToMainApp(for app: TrashedApp) {
        var components = URLComponents()
        components.scheme = "garbagetruck"
        components.host = "show-app"
        components.queryItems = [
            URLQueryItem(name: "path", value: app.standardizedPath),
            URLQueryItem(name: "name", value: app.name),
        ]

        if let bundleIdentifier = app.bundleIdentifier {
            components.queryItems?.append(URLQueryItem(name: "bundleID", value: bundleIdentifier))
        }

        guard let url = components.url else { return }
        DispatchQueue.main.async {
            NSWorkspace.shared.open(url)
        }
    }
}

private func acquireLock() -> Int32? {
    let directoryURL = lockURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

    let fileDescriptor = open(lockURL.path(percentEncoded: false), O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard fileDescriptor >= 0 else {
        return nil
    }

    guard flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
        close(fileDescriptor)
        return nil
    }

    return fileDescriptor
}

if lockFileDescriptor != nil {
    let controller = SentinelController()
    controller.start()
    RunLoop.main.run()
}
