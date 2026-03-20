import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first, url.pathExtension == "app" else { return }
        guard let appState else { return }
        Task { @MainActor in
            await appState.scanAppByURL(url)
        }
    }
}
