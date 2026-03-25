import SwiftUI

private let fdaSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showAppPicker = false

    var body: some View {
        @Bindable var appState = appState
        let appsByBundleID = Dictionary(appState.allApps.map { ($0.bundleIdentifier, $0) }, uniquingKeysWith: { first, _ in first })

        Form {
            Section("Updates") {
                let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"

                switch appState.updateState {
                case .needsRestart:
                    LabeledContent {
                        Button("Restart") {
                            appState.relaunch()
                        }
                        .buttonStyle(.borderedProminent)
                    } label: {
                        Text("Update installed")
                        Text("Restart to finish updating.")
                    }
                case .installing:
                    LabeledContent {
                        ProgressView()
                            .controlSize(.small)
                    } label: {
                        Text("Installing update\u{2026}")
                    }
                case .available(let release):
                    LabeledContent {
                        Button("Download & Install") {
                            Task { await appState.installUpdate() }
                        }
                        .buttonStyle(.borderedProminent)
                    } label: {
                        Text("\(release.version) available")
                        Text("You have \(currentVersion).")
                    }
                case .checking:
                    LabeledContent {
                        ProgressView()
                            .controlSize(.small)
                    } label: {
                        Text("Checking for updates\u{2026}")
                    }
                case .idle:
                    LabeledContent {
                        Button("Check for Updates") {
                            Task { await appState.checkForUpdate() }
                        }
                    } label: {
                        Text("Version \(currentVersion)")
                        Text("Up to date.")
                    }
                case .failed(let error):
                    LabeledContent {
                        Button("Check for Updates") {
                            Task { await appState.checkForUpdate() }
                        }
                    } label: {
                        Text("Version \(currentVersion)")
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section("Permissions") {
                if appState.skippedDirectoryCount == 0 {
                    LabeledContent {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } label: {
                        Text("Full disk access")
                        Text("All directories can be scanned.")
                    }
                } else {
                    LabeledContent {
                        Button("Grant access\u{2026}") {
                            NSWorkspace.shared.open(fdaSettingsURL)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text("Full disk access")
                        }
                        Text("\(appState.skippedDirectoryCount) directories could not be scanned.")
                    }
                }
            }

            Section("Appearance") {
                Toggle(isOn: $appState.showInDock) {
                    Text("Show in Dock")
                    Text("Display the app icon in the Dock.")
                }
                .onChange(of: appState.showInDock) { _, newValue in
                    NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                }
                Toggle(isOn: $appState.showInMenuBar) {
                    Text("Show in menu bar")
                    Text("Add a menu bar icon for quick access.")
                }
            }

            Section("Smart delete") {
                Toggle(isOn: $appState.isSmartDeleteEnabled) {
                    Text("Enable smart delete")
                    Text("Detect when apps are removed and find leftover files.")
                }
                Toggle(isOn: $appState.isAutoNavigateEnabled) {
                    Text("Automatically show cleanup view")
                    Text("Open the cleanup view when leftover files are found.")
                }
                .disabled(!appState.isSmartDeleteEnabled)
                Toggle(isOn: $appState.launchAtLogin) {
                    Text("Launch at login")
                    Text("Start automatically when you log in.")
                }
            }

            Section {
                if appState.protectedAppBundleIDs.isEmpty {
                    Text("No protected apps.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.protectedAppBundleIDs.sorted(), id: \.self) { bundleID in
                        HStack {
                            if let app = appsByBundleID[bundleID] {
                                AppIconView(url: app.id)
                                Text(app.name)
                                Spacer()
                                Text(bundleID)
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            } else {
                                Text(bundleID)
                                    .font(.body.monospaced())
                                Spacer()
                            }
                            Button {
                                appState.removeProtectedApp(bundleID)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button("Add app...") {
                    showAppPicker = true
                }
            } header: {
                Text("Protected apps")
            } footer: {
                Text("Smart delete will skip these apps and leave their files untouched.")
            }
        }
        .formStyle(.grouped)
        .scenePadding()
        .frame(width: 450)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(isPresented: $showAppPicker) {
            ProtectedAppPicker()
        }
    }
}

private struct AppIconView: View {
    let url: URL

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path()))
            .resizable()
            .frame(width: 20, height: 20)
    }
}

private struct ProtectedAppPicker: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            Text("Add protected app")
                .font(.headline)
                .padding()

            TextField("Search apps...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 8)

            List(filteredApps) { app in
                Button {
                    appState.addProtectedApp(app.bundleIdentifier)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        AppIconView(url: app.id)
                        VStack(alignment: .leading) {
                            Text(app.name)
                            Text(app.bundleIdentifier)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if appState.protectedAppBundleIDs.contains(app.bundleIdentifier) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(height: 300)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 400)
    }

    private var filteredApps: [AppInfo] {
        let apps = appState.allApps.filter { !$0.isSystemApp }
        if searchText.isEmpty { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }
}
