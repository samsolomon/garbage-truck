import AppKit

@MainActor
struct RunningAppDetector {
    func isRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    func terminate(bundleIdentifier: String) -> Bool {
        sendSignal(bundleIdentifier: bundleIdentifier) { $0.terminate() }
    }

    func forceTerminate(bundleIdentifier: String) -> Bool {
        sendSignal(bundleIdentifier: bundleIdentifier) { $0.forceTerminate() }
    }

    private func sendSignal(bundleIdentifier: String, action: (NSRunningApplication) -> Bool) -> Bool {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        return apps.allSatisfy(action)
    }
}
