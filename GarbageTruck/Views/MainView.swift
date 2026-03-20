import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        NavigationStack(path: $appState.navigationPath) {
            VStack(spacing: 0) {
                DropBanner()
                    .padding()

                List(appState.filteredApps) { app in
                    NavigationLink(value: app) {
                        AppRowView(app: app)
                    }
                }
                .listStyle(.inset)
            }
            .searchable(text: $appState.searchText, prompt: "Search apps...")
            .navigationTitle("Garbage Truck")
            .navigationDestination(for: AppInfo.self) { app in
                Group {
                    if let scan = appState.currentScan, scan.app == app, !appState.isScanning {
                        ScanResultView(scanResult: scan)
                    } else {
                        ProgressView("Scanning...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .navigationTitle(app.name)
                .task {
                    await appState.scanApp(app)
                }
            }
        }
        .task {
            await appState.loadApps()
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .alert("Result", isPresented: .init(
            get: { appState.deletionResultMessage != nil },
            set: { if !$0 { appState.deletionResultMessage = nil } }
        )) {
            Button("OK") { appState.deletionResultMessage = nil }
        } message: {
            if let message = appState.deletionResultMessage {
                Text(message)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
            guard let data = data as? Data,
                  let urlString = String(data: data, encoding: .utf8),
                  let url = URL(string: urlString),
                  url.pathExtension == "app"
            else { return }
            Task { @MainActor in
                await appState.scanAppByURL(url)
            }
        }
        return true
    }
}
