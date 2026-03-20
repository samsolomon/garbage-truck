import Foundation
import Testing

@testable import GarbageTruck

@MainActor
struct AppStateTests {

    // MARK: - filteredApps (7a)

    @Test func filteredApps_emptySearch() {
        let state = AppState()
        state.allApps = [
            TestFixtures.makeApp(name: "Slack", bundleID: "com.tinyspeck.slackmacgap"),
            TestFixtures.makeApp(name: "Safari", bundleID: "com.apple.Safari"),
        ]
        state.searchText = ""
        #expect(state.filteredApps.count == 2)
    }

    @Test func filteredApps_searchByName() {
        let state = AppState()
        state.allApps = [
            TestFixtures.makeApp(name: "Slack", bundleID: "com.tinyspeck.slackmacgap"),
            TestFixtures.makeApp(name: "Safari", bundleID: "com.apple.Safari"),
        ]
        state.searchText = "sla"
        #expect(state.filteredApps.count == 1)
        #expect(state.filteredApps[0].name == "Slack")
    }

    @Test func filteredApps_searchByBundleID() {
        let state = AppState()
        state.allApps = [
            TestFixtures.makeApp(name: "Slack", bundleID: "com.tinyspeck.slackmacgap"),
            TestFixtures.makeApp(name: "Safari", bundleID: "com.apple.Safari"),
        ]
        state.searchText = "tinyspeck"
        #expect(state.filteredApps.count == 1)
        #expect(state.filteredApps[0].name == "Slack")
    }

    @Test func filteredApps_noMatch() {
        let state = AppState()
        state.allApps = [
            TestFixtures.makeApp(name: "Slack", bundleID: "com.tinyspeck.slackmacgap"),
        ]
        state.searchText = "zzzzz"
        #expect(state.filteredApps.isEmpty)
    }

    // MARK: - batchUpdateSizes (7b)

    @Test func batchUpdateSizes_updatesCorrectFiles() {
        let state = AppState()
        let app = TestFixtures.makeApp(name: "Test", bundleID: "com.test")
        let url1 = URL(filePath: "/tmp/file1")
        let url2 = URL(filePath: "/tmp/file2")
        let file1 = MatchedFile(
            id: url1, confidence: .high,
            matchReason: .bundleIDExact("com.test"), category: .caches, isDirectory: false
        )
        let file2 = MatchedFile(
            id: url2, confidence: .medium,
            matchReason: .appNameMatch("Test"), category: .other, isDirectory: false
        )
        state.currentScan = ScanResult(app: app, files: [file1, file2], scanDuration: .seconds(0))

        state.batchUpdateSizes([(url: url1, size: 1024)])

        #expect(state.currentScan?.files[0].sizeBytes == 1024)
        #expect(state.currentScan?.files[1].sizeBytes == nil)
    }

    @Test func batchUpdateSizes_ignoresUnknownURLs() {
        let state = AppState()
        let app = TestFixtures.makeApp(name: "Test", bundleID: "com.test")
        let url1 = URL(filePath: "/tmp/file1")
        let file1 = MatchedFile(
            id: url1, confidence: .high,
            matchReason: .bundleIDExact("com.test"), category: .caches, isDirectory: false
        )
        state.currentScan = ScanResult(app: app, files: [file1], scanDuration: .seconds(0))

        let unknownURL = URL(filePath: "/tmp/unknown")
        state.batchUpdateSizes([(url: unknownURL, size: 2048)])

        #expect(state.currentScan?.files[0].sizeBytes == nil)
    }

    @Test func batchUpdateSizes_nilScanNoCrash() {
        let state = AppState()
        #expect(state.currentScan == nil)
        state.batchUpdateSizes([(url: URL(filePath: "/tmp/x"), size: 100)])
        #expect(state.currentScan == nil)
    }

    // MARK: - Deletion history cap (7c)

    @Test func deletionHistoryCap() throws {
        let state = AppState()
        let app = TestFixtures.makeApp(name: "TestApp", bundleID: "com.test.app")

        // Pre-fill with 10 dummy records
        for i in 0..<10 {
            state.deletionHistory.append(DeletionRecord(
                date: Date(timeIntervalSince1970: Double(i)),
                appName: "App\(i)",
                entries: []
            ))
        }

        // Create a real temp file for deletion
        let tmpDir = try TestFixtures.makeTempDirectory(prefix: "capTest")
        let tmpFile = try TestFixtures.makeTempFile(in: tmpDir)

        let matchedFile = MatchedFile(
            id: tmpFile, confidence: .high,
            matchReason: .bundleIDExact("com.test.app"), category: .caches, isDirectory: false
        )
        state.currentScan = ScanResult(app: app, files: [matchedFile], scanDuration: .seconds(0))
        state.selectedFileIDs = [tmpFile]

        state.deleteSelectedFiles()

        #expect(state.deletionHistory.count == 10)
        #expect(state.deletionHistory.first?.appName == "App1") // App0 was evicted
        #expect(state.deletionHistory.last?.appName == "TestApp")

        // Clean up
        try? state.deletionHistory.last?.restore()
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: - handleSmartDelete (7d)

    @Test func handleSmartDelete_setsNavAndClears() {
        let state = AppState()
        let app = TestFixtures.makeApp(name: "RemovedApp", bundleID: "com.removed.app")
        state.smartDeleteApp = app

        state.handleSmartDelete()

        #expect(state.smartDeleteApp == nil)
        #expect(state.navigationPath == [app])
    }
}
