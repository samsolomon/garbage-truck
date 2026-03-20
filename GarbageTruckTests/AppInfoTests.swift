import Foundation
import Testing

@testable import GarbageTruck

struct AppInfoTests {

    // MARK: - generateNameVariants (4a)

    @Test func variants_slack() {
        let variants = AppInfo.generateNameVariants("Slack")
        #expect(variants.contains("Slack"))
        #expect(variants.contains("slack"))
        // No spaces/hyphens/digits to strip, so no compacted/stripped variants beyond lowercase
    }

    @Test func variants_visualStudioCode() {
        let variants = AppInfo.generateNameVariants("Visual Studio Code")
        #expect(variants.contains("Visual Studio Code"))
        #expect(variants.contains("VisualStudioCode"))
        #expect(variants.contains("visualstudiocode"))
    }

    @Test func variants_things3() {
        let variants = AppInfo.generateNameVariants("Things3")
        #expect(variants.contains("Things3"))
        #expect(variants.contains("Things"))
        #expect(variants.contains("things"))
    }

    @Test func variants_1password7_noTrailingSpace() {
        let variants = AppInfo.generateNameVariants("1Password 7")
        #expect(variants.contains("1Password"))
        // Verify no trailing space after stripping "7"
        for variant in variants {
            #expect(variant == variant.trimmingCharacters(in: .whitespaces),
                    "Variant '\(variant)' has leading/trailing whitespace")
        }
    }

    @Test func variants_braveBrowser() {
        let variants = AppInfo.generateNameVariants("Brave-Browser")
        #expect(variants.contains("Brave-Browser"))
        #expect(variants.contains("BraveBrowser"))
        #expect(variants.contains("bravebrowser"))
    }

    @Test func variants_singleChar() {
        // Should not crash
        let variants = AppInfo.generateNameVariants("X")
        #expect(variants.contains("X"))
    }

    @Test func variants_emptyString() {
        // Should not crash
        let variants = AppInfo.generateNameVariants("")
        #expect(!variants.isEmpty) // At minimum contains the original (empty string)
    }

    // MARK: - bundleIDLastComponent (4b)

    @Test func bundleIDLastComponent_standard() {
        let app = AppInfo(
            url: URL(filePath: "/Applications/Safari.app"),
            bundleIdentifier: "com.apple.Safari",
            name: "Safari",
            version: nil,
            isSystemApp: true
        )
        #expect(app.bundleIDLastComponent == "Safari")
    }

    @Test func bundleIDLastComponent_twoComponents() {
        let app = AppInfo(
            url: URL(filePath: "/Applications/Example.app"),
            bundleIdentifier: "com.example",
            name: "Example",
            version: nil,
            isSystemApp: false
        )
        #expect(app.bundleIDLastComponent == "example")
    }

    @Test func bundleIDLastComponent_standalone() {
        let app = AppInfo(
            url: URL(filePath: "/Applications/Standalone.app"),
            bundleIdentifier: "standalone",
            name: "Standalone",
            version: nil,
            isSystemApp: false
        )
        #expect(app.bundleIDLastComponent == "standalone")
    }

    // MARK: - isSystemApp (4c)

    @Test func isSystemApp_true() {
        let app = AppInfo(
            url: URL(filePath: "/System/Applications/Safari.app"),
            bundleIdentifier: "com.apple.Safari",
            name: "Safari",
            version: nil,
            isSystemApp: true
        )
        #expect(app.isSystemApp == true)
    }

    @Test func isSystemApp_false() {
        let app = AppInfo(
            url: URL(filePath: "/Applications/Slack.app"),
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            name: "Slack",
            version: nil,
            isSystemApp: false
        )
        #expect(app.isSystemApp == false)
    }
}
