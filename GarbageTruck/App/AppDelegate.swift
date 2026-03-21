import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?

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
}
