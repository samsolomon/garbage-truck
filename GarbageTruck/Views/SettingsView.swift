import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showAppPicker = false

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { newValue in
                try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            }
        )
    }

    var body: some View {
        @Bindable var appState = appState
        let appsByBundleID = Dictionary(appState.allApps.map { ($0.bundleIdentifier, $0) }, uniquingKeysWith: { first, _ in first })

        Form {
            Section("Smart delete") {
                Toggle("Enable smart delete", isOn: $appState.isSmartDeleteEnabled)
                Toggle("Automatically show cleanup view", isOn: $appState.isAutoNavigateEnabled)
                    .disabled(!appState.isSmartDeleteEnabled)
            }

            Section("Protected apps") {
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
            }

            Section("General") {
                Toggle("Launch at login", isOn: launchAtLogin)
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
