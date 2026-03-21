import Foundation
import Testing

@testable import GarbageTruck

struct MatchingEngineTests {
    private let engine = MatchingEngine()

    // MARK: - Tier Correctness (3a)

    @Test func tier1_bundleIDExactMatch() {
        let app = TestFixtures.makeApp(name: "Slack", bundleID: "com.tinyspeck.slackmacgap")
        let match = engine.matchItem(
            itemName: "com.tinyspeck.slackmacgap.plist",
            itemURL: URL(filePath: "/tmp/com.tinyspeck.slackmacgap.plist"),
            isDirectory: false,
            app: app,
            category: .preferences
        )
        #expect(match?.confidence == .high)
        #expect(match?.matchReason == .bundleIDExact("com.tinyspeck.slackmacgap"))
    }

    @Test func tier2_containerMatch() {
        // Tier 1 catches exact bundle ID before Tier 2 can fire (both check containment).
        // This verifies container directories with bundle ID names are matched at high confidence.
        let app = TestFixtures.makeApp(name: "Slack", bundleID: "com.tinyspeck.slackmacgap")
        let match = engine.matchItem(
            itemName: "com.tinyspeck.slackmacgap",
            itemURL: URL(filePath: "/tmp/com.tinyspeck.slackmacgap"),
            isDirectory: true,
            app: app,
            category: .containers
        )
        #expect(match?.confidence == .high)
        #expect(match?.matchReason == .bundleIDExact("com.tinyspeck.slackmacgap"))
    }

    @Test func tier3_bundleIDComponentMatch() {
        let app = TestFixtures.makeApp(name: "Slack", bundleID: "com.tinyspeck.slackmacgap")
        let match = engine.matchItem(
            itemName: "slackmacgap-helper",
            itemURL: URL(filePath: "/tmp/slackmacgap-helper"),
            isDirectory: false,
            app: app,
            category: .caches
        )
        #expect(match?.confidence == .high)
        #expect(match?.matchReason == .bundleIDComponent("slackmacgap"))
    }

    @Test func tier4_appNameMatch() {
        let app = TestFixtures.makeApp(name: "Slack", bundleID: "com.tinyspeck.slackmacgap")
        let match = engine.matchItem(
            itemName: "Slack Helper.log",
            itemURL: URL(filePath: "/tmp/Slack Helper.log"),
            isDirectory: false,
            app: app,
            category: .other
        )
        #expect(match?.confidence == .medium)
        #expect(match?.matchReason == .appNameMatch("Slack"))
    }

    @Test func tier5_appNameNormalizedMatch() {
        let app = TestFixtures.makeApp(name: "Visual Studio Code", bundleID: "com.microsoft.VSCode")
        let match = engine.matchItem(
            itemName: "visualstudiocode.plist",
            itemURL: URL(filePath: "/tmp/visualstudiocode.plist"),
            isDirectory: false,
            app: app,
            category: .preferences
        )
        #expect(match?.confidence == .medium)
        #expect(match?.matchReason == .appNameNormalized("VisualStudioCode"))
    }

    // MARK: - False Positive Suite (3b)

    @Test func falsePositive_bear_bearerToken() {
        let app = TestFixtures.makeApp(name: "Bear", bundleID: "net.shinyfrog.bear")
        withKnownIssue("Matching engine lacks common-word protection") {
            let match = engine.matchItem(
                itemName: "BearerToken.plist",
                itemURL: URL(filePath: "/tmp/BearerToken.plist"),
                isDirectory: false,
                app: app,
                category: .preferences
            )
            #expect(match == nil, "Bear should not match BearerToken")
        }
    }

    @Test func falsePositive_dash_dashExpander() {
        let app = TestFixtures.makeApp(name: "Dash", bundleID: "com.kapeli.dashdoc")
        withKnownIssue("Matching engine lacks common-word protection") {
            let match = engine.matchItem(
                itemName: "DashExpander",
                itemURL: URL(filePath: "/tmp/DashExpander"),
                isDirectory: true,
                app: app,
                category: .applicationSupport
            )
            #expect(match == nil, "Dash should not match DashExpander")
        }
    }

    @Test func falsePositive_spark_sparkle() {
        let app = TestFixtures.makeApp(name: "Spark", bundleID: "com.readdle.sparkmailapp")
        withKnownIssue("Matching engine lacks common-word protection") {
            let match = engine.matchItem(
                itemName: "org.sparkle-project.Sparkle",
                itemURL: URL(filePath: "/tmp/org.sparkle-project.Sparkle"),
                isDirectory: true,
                app: app,
                category: .caches
            )
            #expect(match == nil, "Spark should not match Sparkle framework")
        }
    }

    @Test func falsePositive_slack_slacker() {
        let app = TestFixtures.makeApp(name: "Slack", bundleID: "com.tinyspeck.slackmacgap")
        withKnownIssue("Matching engine lacks common-word protection") {
            let match = engine.matchItem(
                itemName: "Slacker",
                itemURL: URL(filePath: "/tmp/Slacker"),
                isDirectory: true,
                app: app,
                category: .applicationSupport
            )
            #expect(match == nil, "Slack should not match Slacker")
        }
    }

    // MARK: - Guard Conditions (3c)

    @Test func shortNameSkipped() {
        let app = TestFixtures.makeApp(name: "Arc", bundleID: "company.thebrowser.Browser")
        let match = engine.matchItem(
            itemName: "Arc Helper",
            itemURL: URL(filePath: "/tmp/Arc Helper"),
            isDirectory: false,
            app: app,
            category: .other
        )
        // "Arc" is 3 chars, below minimumNameLength of 4 — tiers 4-5 skipped
        #expect(match == nil)
    }

    @Test func systemAppSkipsNameMatch() {
        let app = TestFixtures.makeApp(name: "Safari", bundleID: "com.apple.Safari", isSystemApp: true)
        let match = engine.matchItem(
            itemName: "Safari Extensions",
            itemURL: URL(filePath: "/tmp/Safari Extensions"),
            isDirectory: true,
            app: app,
            category: .applicationSupport
        )
        // System apps skip tier 3 (isSystemApp check) and tiers 4-5 (guard)
        #expect(match == nil)
    }

    @Test func selfExclusion() throws {
        let tmpDir = try TestFixtures.makeTempDirectory(prefix: "selfExclusionTest")
        let appURL = tmpDir.appending(path: "TestApp.app")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        // Also create a file that SHOULD match, to prove exclusion is targeted
        FileManager.default.createFile(
            atPath: tmpDir.appending(path: "com.test.testapp.plist").path(),
            contents: nil
        )
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let app = AppInfo(
            url: appURL,
            bundleIdentifier: "com.test.testapp",
            name: "TestApp",
            version: nil,
            isSystemApp: false
        )
        let dir = ScanDirectory(url: tmpDir, category: .applicationSupport)
        let matches = engine.findMatches(for: app, in: dir)

        #expect(matches.count == 1)
        #expect(matches[0].id.lastPathComponent == "com.test.testapp.plist")
    }

    @Test func selfExclusion_appBundleNeverMatchedByName() throws {
        // The .app bundle itself should be excluded even when its name matches
        let tmpDir = try TestFixtures.makeTempDirectory(prefix: "selfExclusionNameTest")
        let appURL = tmpDir.appending(path: "Slack.app")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        // Create another matching file to confirm exclusion is targeted
        FileManager.default.createFile(
            atPath: tmpDir.appending(path: "com.tinyspeck.slackmacgap.plist").path(),
            contents: nil
        )
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let app = AppInfo(
            url: appURL,
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            name: "Slack",
            version: nil,
            isSystemApp: false
        )
        let dir = ScanDirectory(url: tmpDir, category: .applicationSupport)
        let matches = engine.findMatches(for: app, in: dir)

        let matchedNames = matches.map { $0.id.lastPathComponent }
        #expect(!matchedNames.contains("Slack.app"), "The app's own .app bundle should be excluded")
        #expect(matchedNames.contains("com.tinyspeck.slackmacgap.plist"))
    }

    @Test func deniedPathFilteredInFindMatches() {
        // matchItem itself doesn't filter paths — findMatches does via PathSafety.
        // Verify matchItem would match if called directly with a system path.
        let app = TestFixtures.makeApp(name: "Slack", bundleID: "com.tinyspeck.slackmacgap")
        let match = engine.matchItem(
            itemName: "com.tinyspeck.slackmacgap",
            itemURL: URL(filePath: "/System/Library/com.tinyspeck.slackmacgap"),
            isDirectory: true,
            app: app,
            category: .other
        )
        #expect(match != nil, "matchItem doesn't filter paths — findMatches does via PathSafety")
    }

    @Test func shortBundleIDLastComponentSkipsTier3() {
        // "com.example.app" → lastComponent "app" (3 chars < minimumNameLength)
        let app = TestFixtures.makeApp(name: "MySpecialApp", bundleID: "com.example.app")
        let match = engine.matchItem(
            itemName: "app-helper",
            itemURL: URL(filePath: "/tmp/app-helper"),
            isDirectory: false,
            app: app,
            category: .caches
        )
        // Tier 3 skipped (short component), tiers 4-5 won't match "MySpecialApp" in "app-helper"
        #expect(match == nil)
    }

    // MARK: - Filesystem Integration (3d)

    @Test func findMatches_fullPipeline() throws {
        let tmpDir = try TestFixtures.makeTempDirectory(prefix: "matchingTest")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let files = [
            "com.tinyspeck.slackmacgap.plist",  // Tier 1
            "Slack Helper.log",                   // Tier 4
            "slackmacgap.db",                     // Tier 3
            "Unrelated.txt",
            "AnotherApp.plist",
        ]
        for file in files {
            FileManager.default.createFile(
                atPath: tmpDir.appending(path: file).path(percentEncoded: false),
                contents: nil
            )
        }

        let app = TestFixtures.makeApp(name: "Slack", bundleID: "com.tinyspeck.slackmacgap")
        let dir = ScanDirectory(url: tmpDir, category: .preferences)
        let matches = engine.findMatches(for: app, in: dir)

        // Use path(percentEncoded: false) to avoid URL percent-encoding issues with spaces
        let matchedPaths = matches.map { $0.id.path(percentEncoded: false) }
        #expect(matchedPaths.contains { $0.hasSuffix("/com.tinyspeck.slackmacgap.plist") })
        #expect(matchedPaths.contains { $0.hasSuffix("/Slack Helper.log") })
        #expect(matchedPaths.contains { $0.hasSuffix("/slackmacgap.db") })
        #expect(!matchedPaths.contains { $0.hasSuffix("/Unrelated.txt") })
        #expect(!matchedPaths.contains { $0.hasSuffix("/AnotherApp.plist") })
    }
}
