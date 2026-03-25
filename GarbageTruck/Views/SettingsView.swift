import SwiftUI

private let fdaSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showAppPicker = false

    var body: some View {
        @Bindable var appState = appState
        let appsByBundleID = Dictionary(appState.allApps.map { ($0.bundleIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        let menuBarBinding = Binding(
            get: { appState.wantsMenuBarExtra },
            set: { appState.setMenuBarExtraEnabled($0) }
        )
        let dockBinding = Binding(
            get: { appState.wantsDockIcon },
            set: { appState.setDockIconVisible($0) }
        )

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
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                    } label: {
                        VStack(alignment: .leading) {
                            Text("Update installed")
                            Text("Restart to finish updating.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
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
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                    } label: {
                        VStack(alignment: .leading) {
                            Text("\(release.version) available")
                            Text("You have \(currentVersion).")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
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
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                    } label: {
                        VStack(alignment: .leading) {
                            Text("Version \(currentVersion)")
                            Text("Up to date.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                    }
                case .failed(let error):
                    LabeledContent {
                        Button("Check for Updates") {
                            Task { await appState.checkForUpdate() }
                        }
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                    } label: {
                        VStack(alignment: .leading) {
                            Text("Version \(currentVersion)")
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                    }
                }
                LabeledContent {
                    Toggle("", isOn: $appState.autoCheckForUpdates)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                } label: {
                    VStack(alignment: .leading) {
                        Text("Check automatically")
                        Text("Check for updates when the app launches.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                }
            }

            Section("Permissions") {
                if appState.skippedDirectoryCount == 0 {
                    LabeledContent {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                    } label: {
                        VStack(alignment: .leading) {
                            Text("Full disk access")
                            Text("All directories can be scanned.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                    }
                } else {
                    LabeledContent {
                        Button("Grant access\u{2026}") {
                            NSWorkspace.shared.open(fdaSettingsURL)
                        }
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                    } label: {
                        VStack(alignment: .leading) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                                Text("Full disk access")
                            }
                            Text("\(appState.skippedDirectoryCount) directories could not be scanned.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                    }
                }
            }

            Section("Appearance") {
                LabeledContent {
                    Toggle("", isOn: menuBarBinding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                } label: {
                    VStack(alignment: .leading) {
                        Text("Show in menu bar")
                        Text("Adds a menu bar icon while keeping the app visible in the Dock.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                }
                LabeledContent {
                    Toggle("", isOn: dockBinding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                } label: {
                    VStack(alignment: .leading) {
                        Text("Show in Dock")
                        Text("You can hide the Dock icon only while menu bar access stays enabled.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                }
            }

            Section("Smart delete") {
                LabeledContent {
                    Toggle("", isOn: $appState.isSmartDeleteEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                } label: {
                    VStack(alignment: .leading) {
                        Text("Enable smart delete")
                        Text("Detect when apps are removed and find leftover files.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                }
                LabeledContent {
                    Toggle("", isOn: $appState.isAutoNavigateEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                } label: {
                    VStack(alignment: .leading) {
                        Text("Automatically show cleanup view")
                        Text("Open the cleanup view when leftover files are found.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                }
                .disabled(!appState.isSmartDeleteEnabled)
                LabeledContent {
                    Toggle("", isOn: $appState.launchAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                } label: {
                    VStack(alignment: .leading) {
                        Text("Launch at login")
                        Text("Start automatically when you log in.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
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
