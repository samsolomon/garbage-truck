import SwiftUI
import UniformTypeIdentifiers

private let fdaSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
private let hasShownFDAPromptKey = "hasShownFDAPrompt"

struct MainView: View {
    @Environment(AppState.self) private var appState
    @State private var showFDASheet = false
    @State private var selectedAppID: URL?

    private enum FocusField { case search, list }
    @FocusState private var focusedField: FocusField?

    var body: some View {
        @Bindable var appState = appState

        NavigationStack(path: $appState.navigationPath) {
            List(appState.filteredApps, selection: $selectedAppID) { app in
                AppRowView(app: app)
                    .tag(app.id)
                    .onTapGesture { navigate(to: app) }
            }
            .focused($focusedField, equals: .list)
            .onKeyPress(.return) {
                guard let selectedAppID,
                      let app = appState.filteredApps.first(where: { $0.id == selectedAppID })
                else { return .ignored }
                navigate(to: app)
                return .handled
            }
            .onKeyPress(.upArrow) {
                guard let selectedAppID,
                      appState.filteredApps.first?.id == selectedAppID
                else { return .ignored }
                focusedField = .search
                return .handled
            }
            .listStyle(.inset)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Find apps to delete...", text: $appState.searchText)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .search)
                        .onKeyPress(.downArrow) {
                            guard let firstID = appState.filteredApps.first?.id else { return .ignored }
                            selectedAppID = firstID
                            focusedField = .list
                            return .handled
                        }
                        .onKeyPress(.return) {
                            guard let app = appState.filteredApps.first else { return .ignored }
                            navigate(to: app)
                            return .handled
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                )
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if appState.skippedDirectoryCount > 0 {
                    VStack(spacing: 0) {
                        Divider()
                        Button {
                            NSWorkspace.shared.open(fdaSettingsURL)
                        } label: {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.yellow)
                                Text("\(appState.skippedDirectoryCount) directories could not be scanned — grant Full Disk Access")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                    .background(.ultraThinMaterial)
                }
            }
            .navigationTitle("Garbage Truck")
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .navigationDestination(for: AppInfo.self) { app in
                Group {
                    if let scan = appState.currentScan, scan.app == app, !appState.isScanning {
                        ScanResultView(scanResult: scan)
                    } else {
                        ProgressView("Scanning...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .navigationTitle("Garbage Truck")
                .navigationBarBackButtonHidden()
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .task {
                    await appState.scanApp(app)
                }
            }
        }
        .onAppear { focusedField = .search }
        .onChange(of: appState.navigationPath) {
            if appState.navigationPath.isEmpty {
                appState.searchText = ""
                selectedAppID = nil
                focusedField = .search
            }
        }
        .onChange(of: appState.searchText) {
            let newID = appState.filteredApps.first?.id
            if selectedAppID != newID { selectedAppID = newID }
        }
        .task {
            await appState.loadApps()
            if appState.skippedDirectoryCount > 0 && !UserDefaults.standard.bool(forKey: hasShownFDAPromptKey) {
                showFDASheet = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.recheckPermissions()
        }
        .sheet(isPresented: $showFDASheet, onDismiss: {
            UserDefaults.standard.set(true, forKey: hasShownFDAPromptKey)
        }) {
            FDAOnboardingSheet(isPresented: $showFDASheet)
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

    private func navigate(to app: AppInfo) {
        appState.navigationPath = [app]
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

private struct FDAOnboardingSheet: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Full Disk Access Required")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Garbage Truck needs Full Disk Access to scan ~/Library/ and find files associated with your apps. Without it, some directories will be skipped.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                Button("Open System Settings") {
                    NSWorkspace.shared.open(fdaSettingsURL)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)

                Button("Later") {
                    isPresented = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
        .padding(32)
        .frame(width: 380)
    }
}
