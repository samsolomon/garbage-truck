import SwiftUI

struct ScanResultView: View {
    let scanResult: ScanResult
    @Environment(AppState.self) private var appState

    private var groupedFiles: [(FileCategory, [MatchedFile])] {
        let grouped = Dictionary(grouping: scanResult.files, by: \.category)
        return FileCategory.allCases.compactMap { category in
            guard let files = grouped[category], !files.isEmpty else { return nil }
            return (category, files)
        }
    }

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            header
                .padding()

            Divider()

            if scanResult.files.isEmpty {
                ContentUnavailableView(
                    "No Files Found",
                    systemImage: "checkmark.circle",
                    description: Text("No leftover files were found for \(scanResult.app.name).")
                )
            } else {
                List {
                    ForEach(groupedFiles, id: \.0) { category, files in
                        Section(category.rawValue) {
                            ForEach(files) { file in
                                FileRowView(
                                    file: file,
                                    isSelected: appState.selectedFileIDs.contains(file.id),
                                    onToggle: { toggleFile(file) }
                                )
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))

                Divider()

                footer
                    .padding()
            }

            if !scanResult.skippedDirectories.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.yellow)
                    Text("\(scanResult.skippedDirectories.count) directories could not be scanned (Full Disk Access may be required)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .task(id: scanResult.app.id) {
            await computeAllSizes()
        }
        .alert("Confirm Deletion", isPresented: $appState.showDeleteConfirmation) {
            Button("Move to Trash", role: .destructive) {
                appState.deleteSelectedFiles()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Move \(appState.selectedFileIDs.count) files (\(formatSize(appState.selectedTotalSize))) to Trash?")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: scanResult.app.id.path()))
                .resizable()
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(scanResult.app.name)
                        .font(.title2)
                        .fontWeight(.semibold)

                    if appState.runningAppDetector.isRunning(bundleIdentifier: scanResult.app.bundleIdentifier) {
                        Text("Running")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 8) {
                    if let version = scanResult.app.version {
                        Text("v\(version)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(scanResult.app.bundleIdentifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text("\(scanResult.files.count) files found")
                    .font(.callout)
                Text("Scanned in \(formatDuration(scanResult.scanDuration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
                Button("Select All High") {
                    let highIDs = scanResult.files
                        .filter { $0.confidence == .high }
                        .map(\.id)
                    appState.selectedFileIDs = Set(highIDs)
                }
                .buttonStyle(.bordered)

                Button("Select All") {
                    appState.selectedFileIDs = Set(scanResult.files.map(\.id))
                }
                .buttonStyle(.bordered)

                Button("Move to Trash") {
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

    private func formatDuration(_ duration: Duration) -> String {
        let ms = duration.components.attoseconds / 1_000_000_000_000_000
        let totalMs = Int(duration.components.seconds) * 1000 + Int(ms)
        if totalMs < 1000 {
            return "\(totalMs)ms"
        } else {
            return String(format: "%.1fs", Double(totalMs) / 1000.0)
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
