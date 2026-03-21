import SwiftUI

struct ScanResultView: View {
    let scanResult: ScanResult
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showForceQuitAlert = false

    private var allSelected: Bool {
        appState.selectedFileIDs.count == scanResult.files.count
    }

    var body: some View {
        @Bindable var appState = appState

        Group {
            if scanResult.files.isEmpty {
                ContentUnavailableView(
                    "No files found",
                    systemImage: "checkmark.circle",
                    description: Text("No leftover files were found for \(scanResult.app.name).")
                )
            } else {
                List {
                    ForEach(scanResult.files) { file in
                        FileRowView(
                            file: file,
                            isSelected: appState.selectedFileIDs.contains(file.id),
                            onToggle: { toggleFile(file) }
                        )
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                header
                    .padding()
                Divider()
            }
            .background(.ultraThinMaterial)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !scanResult.files.isEmpty {
                VStack(spacing: 0) {
                    Divider()
                    footer
                        .padding()
                }
                .background(.ultraThinMaterial)
            }
        }
        .task(id: scanResult.app.id) {
            await computeAllSizes()
        }
        .background {
            Button("") { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])
                .hidden()
        }
        .alert("Force quit?", isPresented: $showForceQuitAlert) {
            Button("Force quit", role: .destructive) {
                appState.forceTerminateApp(scanResult.app)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(scanResult.app.name) didn't respond to the quit request. Force quit?")
        }
        .alert("Confirm deletion", isPresented: $appState.showDeleteConfirmation) {
            Button("Move to trash", role: .destructive) {
                appState.deleteSelectedFiles()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Move \(appState.selectedFileIDs.count) files (\(formatSize(appState.selectedTotalSize))) to Trash?")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)

            Image(nsImage: NSWorkspace.shared.icon(forFile: scanResult.app.id.path()))
                .resizable()
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(scanResult.app.name)
                        .font(.title2)
                        .fontWeight(.semibold)

                    if appState.isAppRunning(scanResult.app) {
                        Button {
                            Task {
                                let terminated = await appState.terminateApp(scanResult.app)
                                if !terminated {
                                    showForceQuitAlert = true
                                }
                            }
                        } label: {
                            Text("Running")
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.orange.opacity(0.2))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(scanResult.app.id.path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer()

            Text(formatSize(scanResult.totalSizeBytes))
                .font(.title2)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("\(appState.selectedFileIDs.count) of \(scanResult.files.count) files selected")
                    .font(.callout)
                SizeLabel(sizeBytes: appState.selectedTotalSize)
            }

            Spacer()

            HStack(spacing: 12) {
                Button("Recommended only") {
                    let highIDs = Set(scanResult.files
                        .filter { $0.confidence == .high }
                        .map(\.id))
                    if appState.selectedFileIDs == highIDs {
                        appState.selectedFileIDs.removeAll()
                    } else {
                        appState.selectedFileIDs = highIDs
                    }
                }
                .buttonStyle(.bordered)

                Button(allSelected ? "Deselect all" : "Select all") {
                    if allSelected {
                        appState.selectedFileIDs.removeAll()
                    } else {
                        appState.selectedFileIDs = Set(scanResult.files.map(\.id))
                    }
                }
                .buttonStyle(.bordered)

                Button("Move to trash") {
                    appState.showDeleteConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(appState.selectedFileIDs.isEmpty)
            }
        }
    }

    private func toggleFile(_ file: MatchedFile) {
        if appState.selectedFileIDs.contains(file.id) {
            appState.selectedFileIDs.remove(file.id)
        } else {
            appState.selectedFileIDs.insert(file.id)
        }
    }

    private func computeAllSizes() async {
        let files = scanResult.files
        let batchSize = 10

        for startIndex in stride(from: 0, to: files.count, by: batchSize) {
            try? await Task.sleep(for: .zero) // yield for cancellation check
            if Task.isCancelled { return }

            let endIndex = min(startIndex + batchSize, files.count)
            let batch = files[startIndex..<endIndex]

            let updates: [(url: URL, size: Int64)] = await withTaskGroup(
                of: (URL, Int64).self
            ) { group in
                for file in batch {
                    group.addTask {
                        (file.id, FileScanner.computeSize(for: file.id))
                    }
                }
                var results: [(URL, Int64)] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }

            appState.batchUpdateSizes(updates)
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
