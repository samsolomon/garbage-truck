import os
import SwiftUI
import ServiceManagement

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
    var isAutoNavigateEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.autoNavigateKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.autoNavigateKey) }
    }
    var protectedAppBundleIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.protectedAppsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.protectedAppsKey) }
    }
    private(set) var wantsMenuBarExtra = false
    private(set) var wantsDockIcon = true
    var autoCheckForUpdates: Bool {
        get { UserDefaults.standard.bool(forKey: Self.autoCheckForUpdatesKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.autoCheckForUpdatesKey) }
    }
    var updateState: UpdateState = .idle

    private var previousAppIDs: Set<URL> = []
    private var scanGeneration = 0
    private var isCheckingForRemovedApps = false
    private var lastRemovalCheckDate: Date?
    private let discoveryService = AppDiscoveryService()
    private let fileScanner = FileScanner()
    private let deletionManager = DeletionManager()
    private let runningAppDetector = RunningAppDetector()
    private var directoryMonitor: DirectoryMonitor?
    private var sentinelProcess: Process?
    private weak var presentationCoordinator: AppPresentationCoordinator?
    private var pendingActivationTarget: ActivationTarget?

    private static let maxUndoHistory = 10
    private static let smartDeleteKey = "smartDeleteEnabled"
    private static let autoNavigateKey = "autoNavigateOnSmartDelete"
    private static let protectedAppsKey = "protectedAppBundleIDs"
    private static let menuBarExtraKey = "showInMenuBar"
    private static let dockIconKey = "showInDock"
    private static let autoCheckForUpdatesKey = "autoCheckForUpdates"
    private static let removalCheckInterval: TimeInterval = 5

    private enum ActivationTarget {
        case list
        case currentDestination
    }

    init() {
        UserDefaults.standard.register(defaults: [
            Self.smartDeleteKey: true,
            Self.autoNavigateKey: true,
            Self.menuBarExtraKey: false,
            Self.dockIconKey: true,
            Self.autoCheckForUpdatesKey: true,
        ])
        let storedMenuBarExtra = UserDefaults.standard.bool(forKey: Self.menuBarExtraKey)
        let storedDockIcon = UserDefaults.standard.bool(forKey: Self.dockIconKey)
        let normalized = Self.normalizePresentationPreferences(
            menuBarExtraEnabled: storedMenuBarExtra,
            dockIconVisible: storedDockIcon
        )
        wantsMenuBarExtra = normalized.menuBarExtraEnabled
        wantsDockIcon = normalized.dockIconVisible
        persistPresentationPreferences()
        logger.notice("AppState initialized")
    }

    func configurePresentationCoordinator(_ coordinator: AppPresentationCoordinator) {
        presentationCoordinator = coordinator
        coordinator.configure(menuBarExtraEnabled: wantsMenuBarExtra, dockIconVisible: wantsDockIcon)
    }

    func markMainWindowReady() {
        presentationCoordinator?.markMainWindowReady()
    }

    func setMenuBarExtraEnabled(_ isEnabled: Bool) {
        let dockIconVisible = isEnabled ? wantsDockIcon : true
        updatePresentationPreferences(menuBarExtraEnabled: isEnabled, dockIconVisible: dockIconVisible)
    }

    func setDockIconVisible(_ isVisible: Bool) {
        let menuBarExtraEnabled = isVisible ? wantsMenuBarExtra : true
        updatePresentationPreferences(menuBarExtraEnabled: menuBarExtraEnabled, dockIconVisible: isVisible)
    }

    func setSmartDeleteEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: Self.smartDeleteKey)
        if isEnabled {
            startSentinelIfNeeded()
        } else {
            stopSentinelIfNeeded()
        }
    }

    func revealListView() {
        navigationPath = []
        pendingActivationTarget = .list
        presentationCoordinator?.revealMainWindow()
    }

    func handleShowListRoute() {
        revealListView()
    }

    func revealCurrentDestination() {
        pendingActivationTarget = .currentDestination
        presentationCoordinator?.revealMainWindow()
    }

    func handleShowAppRoute(appURL: URL?, bundleIdentifier: String?, appName: String?) async {
        guard let app = resolvedRouteAppInfo(appURL: appURL, bundleIdentifier: bundleIdentifier, appName: appName) else {
            return
        }

        if !allApps.contains(where: { $0.id == app.id }) {
            allApps.append(app)
            allApps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        navigationPath = [app]
        revealCurrentDestination()
    }

    func handleActivationWithoutVisibleWindows() {
        let target = pendingActivationTarget ?? .list
        pendingActivationTarget = nil
        if case .list = target {
            navigationPath = []
        }
        presentationCoordinator?.revealMainWindow()
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
        startSentinelIfNeeded()
    }

    private func startDirectoryMonitor() {
        guard directoryMonitor == nil else { return }
        directoryMonitor = DirectoryMonitor(directories: AppDiscoveryService.applicationDirectories) { [weak self] in
            Task { @MainActor in
                let pathBefore = self?.navigationPath ?? []
                await self?.checkForRemovedApps()
                if let self, self.isAutoNavigateEnabled, self.navigationPath != pathBefore {
                    self.revealCurrentDestination()
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
        scanGeneration += 1
        let generation = scanGeneration
        isScanning = true
        selectedFileIDs = []
        currentScan = nil

        let result = await fileScanner.scan(app: app)
        guard generation == scanGeneration else { return }

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
        revealCurrentDestination()
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
        _ = runningAppDetector.forceTerminate(bundleIdentifier: app.bundleIdentifier)
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
            logger.error("Restore failed: \(error.localizedDescription)")
            deletionResultMessage = "Undo failed: \(error.localizedDescription)"
        }
    }

    func addProtectedApp(_ bundleID: String) {
        var ids = protectedAppBundleIDs
        ids.insert(bundleID)
        protectedAppBundleIDs = ids
    }

    func removeProtectedApp(_ bundleID: String) {
        var ids = protectedAppBundleIDs
        ids.remove(bundleID)
        protectedAppBundleIDs = ids
    }

    private func updatePresentationPreferences(menuBarExtraEnabled: Bool, dockIconVisible: Bool) {
        let normalized = Self.normalizePresentationPreferences(
            menuBarExtraEnabled: menuBarExtraEnabled,
            dockIconVisible: dockIconVisible
        )
        guard normalized.menuBarExtraEnabled != wantsMenuBarExtra || normalized.dockIconVisible != wantsDockIcon else {
            return
        }
        wantsMenuBarExtra = normalized.menuBarExtraEnabled
        wantsDockIcon = normalized.dockIconVisible
        persistPresentationPreferences()
        presentationCoordinator?.configure(
            menuBarExtraEnabled: wantsMenuBarExtra,
            dockIconVisible: wantsDockIcon
        )
    }

    private func persistPresentationPreferences() {
        UserDefaults.standard.set(wantsMenuBarExtra, forKey: Self.menuBarExtraKey)
        UserDefaults.standard.set(wantsDockIcon, forKey: Self.dockIconKey)
    }

    private static func normalizePresentationPreferences(
        menuBarExtraEnabled: Bool,
        dockIconVisible: Bool
    ) -> (menuBarExtraEnabled: Bool, dockIconVisible: Bool) {
        if !menuBarExtraEnabled && !dockIconVisible {
            return (false, true)
        }
        return (menuBarExtraEnabled, dockIconVisible)
    }

    private func resolvedRouteAppInfo(appURL: URL?, bundleIdentifier: String?, appName: String?) -> AppInfo? {
        if let appURL,
           let discoveredApp = discoveryService.appInfo(from: appURL) {
            return discoveredApp
        }

        if let bundleIdentifier,
           let existingApp = allApps.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            return existingApp
        }

        guard let bundleIdentifier else { return nil }

        let fallbackName = appName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName: String
        if let fallbackName, !fallbackName.isEmpty {
            resolvedName = fallbackName
        } else {
            resolvedName = bundleIdentifier.components(separatedBy: ".").last ?? bundleIdentifier
        }

        let urlHint = appURL ?? URL(fileURLWithPath: "/Applications/\(resolvedName).app")
        let isSystemApp = bundleIdentifier.hasPrefix("com.apple.")

        return AppInfo(
            url: urlHint,
            bundleIdentifier: bundleIdentifier,
            name: resolvedName,
            version: nil,
            isSystemApp: isSystemApp
        )
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                logger.error("Failed to \(newValue ? "register" : "unregister") login item: \(error.localizedDescription)")
            }
        }
    }

    func checkForUpdate() async {
        if case .checking = updateState { return }
        updateState = .checking
        do {
            if let release = try await UpdateService.checkForUpdate() {
                updateState = .available(release)
            } else {
                updateState = .idle
            }
        } catch {
            updateState = .failed(error.localizedDescription)
        }
    }

    func installUpdate() async {
        guard case .available(let release) = updateState, let url = release.dmgURL else { return }
        updateState = .installing
        do {
            try await UpdateService.downloadAndInstall(from: url)
            updateState = .needsRestart
        } catch {
            updateState = .failed(error.localizedDescription)
        }
    }

    func relaunch() {
        let appPath = Bundle.main.bundleURL.path(percentEncoded: false)
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", "sleep 1 && open \"\(appPath)\""]
        try? process.run()
        NSApp.terminate(nil)
    }

    private func startSentinelIfNeeded() {
        guard isSmartDeleteEnabled else { return }
        guard sentinelProcess?.isRunning != true else { return }
        guard let helperURL = bundledSentinelURL else {
            logger.error("Bundled sentinel helper not found")
            return
        }

        let process = Process()
        process.executableURL = helperURL
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.sentinelProcess = nil
            }
        }

        do {
            try process.run()
            sentinelProcess = process
        } catch {
            logger.error("Failed to start sentinel helper: \(error.localizedDescription)")
        }
    }

    private func stopSentinelIfNeeded() {
        guard let sentinelProcess else { return }
        if sentinelProcess.isRunning {
            sentinelProcess.terminate()
        }
        self.sentinelProcess = nil
    }

    private var bundledSentinelURL: URL? {
        let helperURL = Bundle.main.bundleURL
            .appending(path: "Contents")
            .appending(path: "Helpers")
            .appending(path: "GarbageTruckSentinel")
        guard FileManager.default.isExecutableFile(atPath: helperURL.path(percentEncoded: false)) else {
            return nil
        }
        return helperURL
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
        guard !isCheckingForRemovedApps else {
            logger.notice("already checking, skipping")
            return
        }

        isCheckingForRemovedApps = true
        defer { isCheckingForRemovedApps = false }
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
        let protectedIDs = protectedAppBundleIDs

        for id in removedIDs {
            guard let app = oldApps.first(where: { $0.id == id }) else {
                logger.debug("\(id.lastPathComponent): not in old app list, skipping")
                continue
            }
            if app.isSystemApp {
                logger.debug("\(app.name): system app, skipping")
                continue
            }
            if protectedIDs.contains(app.bundleIdentifier) {
                logger.debug("\(app.name): protected app, skipping")
                continue
            }
            if app.id == selfBundleURL {
                logger.debug("\(app.name): is self, skipping")
                continue
            }
            if runningAppDetector.isRunning(bundleIdentifier: app.bundleIdentifier) {
                logger.debug("\(app.name): still running, skipping")
                continue
            }
            if fm.fileExists(atPath: app.id.path()) {
                logger.debug("\(app.name): .app still exists, skipping")
                continue
            }

            logger.notice("detected removal: \(app.name)")
            if isAutoNavigateEnabled {
                navigationPath = [app]
            }
            return
        }
    }

}
