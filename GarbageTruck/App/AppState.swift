import os
import SwiftUI

private let logger = Logger(subsystem: "com.garbagetruck.app", category: "SmartDelete")

@Observable @MainActor
final class AppState {
    var allApps: [AppInfo] = []
    var searchText: String = ""
    var isLoadingApps = false
    var currentScan: ScanResult? = nil
    var isScanning = false
    var selectedFileIDs: Set<URL> = []
    var deletionHistory: [DeletionRecord] = []
    var navigationPath: [AppInfo] = []
    var showDeleteConfirmation = false
    var deletionResultMessage: String? = nil
    var skippedDirectoryCount = 0
    var isSmartDeleteEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.smartDeleteKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.smartDeleteKey) }
    }

    private var previousAppIDs: Set<URL> = []
    private var lastRemovalCheckDate: Date?
    private let discoveryService = AppDiscoveryService()
    private let fileScanner = FileScanner()
    private let deletionManager = DeletionManager()
    private let runningAppDetector = RunningAppDetector()
    private var directoryMonitor: DirectoryMonitor?

    private static let maxUndoHistory = 10
    private static let smartDeleteKey = "smartDeleteEnabled"
    private static let removalCheckInterval: TimeInterval = 5

    init() {
        UserDefaults.standard.register(defaults: [Self.smartDeleteKey: true])
        logger.notice("AppState initialized")
    }

    var filteredApps: [AppInfo] {
        if searchText.isEmpty { return allApps }
        return allApps.filter { app in
            app.name.localizedCaseInsensitiveContains(searchText)
                || app.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }

    var selectedFiles: [MatchedFile] {
        currentScan?.files.filter { selectedFileIDs.contains($0.id) } ?? []
    }

    var selectedTotalSize: Int64 {
        selectedFiles.compactMap(\.sizeBytes).reduce(0, +)
    }

    func loadApps() async {
        logger.notice("loadApps called")
        isLoadingApps = true
        previousAppIDs = Set(allApps.map(\.id))
        allApps = await discoveryService.discoverApps()
        if previousAppIDs.isEmpty {
            previousAppIDs = Set(allApps.map(\.id))
        }
        recheckPermissions()
        isLoadingApps = false
        startDirectoryMonitor()
    }

    private func startDirectoryMonitor() {
        guard directoryMonitor == nil else { return }
        directoryMonitor = DirectoryMonitor(directories: AppDiscoveryService.applicationDirectories) { [weak self] in
            Task { @MainActor in
                let pathBefore = self?.navigationPath ?? []
                await self?.checkForRemovedApps()
                if let self, self.navigationPath != pathBefore {
                    NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                    NSApp.mainWindow?.orderFrontRegardless()
                }
            }
        }
        directoryMonitor?.start()
    }

    func recheckPermissions() {
        skippedDirectoryCount = ScanDirectory.userDirectories()
            .filter { !FileManager.default.isReadableFile(atPath: $0.url.path()) }
            .count
    }

    func scanApp(_ app: AppInfo) async {
        if currentScan?.app == app && !isScanning { return }

        isScanning = true
        selectedFileIDs = []

        let result = await fileScanner.scan(app: app)
        currentScan = result

        // Auto-select high confidence files
        selectedFileIDs = Set(
            result.files
                .filter { $0.confidence == .high }
                .map(\.id)
        )

        isScanning = false
    }

    func scanAppByURL(_ url: URL) async {
        guard let app = discoveryService.appInfo(from: url) else { return }

        // Ensure the app is in our list
        if !allApps.contains(where: { $0.id == app.id }) {
            allApps.append(app)
            allApps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        navigationPath = [app]
    }

    func isAppRunning(_ app: AppInfo) -> Bool {
        runningAppDetector.isRunning(bundleIdentifier: app.bundleIdentifier)
    }

    func terminateApp(_ app: AppInfo) async -> Bool {
        guard runningAppDetector.isRunning(bundleIdentifier: app.bundleIdentifier) else { return true }
        let success = runningAppDetector.terminate(bundleIdentifier: app.bundleIdentifier)
        if success {
            try? await Task.sleep(for: .seconds(1))
        }
        return !runningAppDetector.isRunning(bundleIdentifier: app.bundleIdentifier)
    }

    func forceTerminateApp(_ app: AppInfo) {
        runningAppDetector.forceTerminate(bundleIdentifier: app.bundleIdentifier)
    }

    func batchUpdateSizes(_ updates: [(url: URL, size: Int64)]) {
        guard var scan = currentScan else { return }
        for update in updates {
            if let index = scan.files.firstIndex(where: { $0.id == update.url }) {
                scan.files[index].sizeBytes = update.size
            }
        }
        currentScan = scan
    }

    func deleteSelectedFiles() {
        guard var scan = currentScan else { return }
        let filesToDelete = selectedFiles.map(\.id)
        guard !filesToDelete.isEmpty else { return }

        let result = deletionManager.moveToTrash(files: filesToDelete, appName: scan.app.name)

        if let record = result.record {
            deletionHistory.append(record)
            if deletionHistory.count > Self.maxUndoHistory {
                deletionHistory.removeFirst()
            }
        }

        // Remove deleted files from scan result
        let deletedURLs = Set(result.record?.entries.map(\.originalURL) ?? [])
        scan.files.removeAll { deletedURLs.contains($0.id) }
        selectedFileIDs.subtract(deletedURLs)
        currentScan = scan

        if result.failedCount > 0 {
            let errorDetails = result.errors.map { "\($0.0.lastPathComponent): \($0.1)" }.joined(separator: "\n")
            deletionResultMessage = "Moved \(result.movedCount) files to Trash. \(result.failedCount) failed:\n\(errorDetails)"
        } else {
            deletionResultMessage = "Moved \(result.movedCount) files to Trash."
        }

        // Return to list if no files remain
        if scan.files.isEmpty {
            navigationPath = []
        }
    }

    func undoLastDeletion() {
        guard let record = deletionHistory.last else { return }
        do {
            try record.restore()
            deletionHistory.removeLast()
            if let app = navigationPath.last {
                Task { await scanApp(app) }
            }
        } catch {
            deletionResultMessage = "Undo failed: \(error.localizedDescription)"
        }
    }

    func checkForRemovedApps() async {
        guard isSmartDeleteEnabled else {
            logger.notice("disabled, skipping")
            return
        }
        guard !previousAppIDs.isEmpty else {
            logger.notice("no baseline yet, skipping")
            return
        }

        // Throttle: skip if checked recently
        if let last = lastRemovalCheckDate, Date.now.timeIntervalSince(last) < Self.removalCheckInterval {
            logger.notice("throttled, skipping")
            return
        }
        lastRemovalCheckDate = .now

        let oldApps = allApps
        let freshApps = await discoveryService.discoverApps()
        let freshIDs = Set(freshApps.map(\.id))
        let removedIDs = previousAppIDs.subtracting(freshIDs)

        let baselineCount = previousAppIDs.count
        logger.notice("baseline: \(baselineCount), fresh: \(freshIDs.count), removed: \(removedIDs.count)")

        if freshApps != allApps {
            allApps = freshApps
        }
        previousAppIDs = freshIDs

        let selfBundleURL = Bundle.main.bundleURL
        let fm = FileManager.default

        for id in removedIDs {
            guard let app = oldApps.first(where: { $0.id == id }) else {
                logger.notice("\(id.lastPathComponent): not in old app list, skipping")
                continue
            }
            if app.isSystemApp {
                logger.notice("\(app.name): system app, skipping")
                continue
            }
            if app.id == selfBundleURL {
                logger.notice("\(app.name): is self, skipping")
                continue
            }
            if runningAppDetector.isRunning(bundleIdentifier: app.bundleIdentifier) {
                logger.notice("\(app.name): still running, skipping")
                continue
            }
            if fm.fileExists(atPath: app.id.path()) {
                logger.notice("\(app.name): .app still exists at \(app.id.path()), skipping")
                continue
            }

            logger.notice("detected removal: \(app.name)")
            navigationPath = [app]
            return
        }
    }

}
