import SwiftUI

struct FileRowView: View {
    let file: MatchedFile
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { isSelected },
                set: { _ in onToggle() }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()

            Image(systemName: file.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(file.id.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(file.matchReason.description)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            ConfidenceBadge(confidence: file.confidence)

            SizeLabel(sizeBytes: file.sizeBytes)
                .frame(width: 70, alignment: .trailing)

            Button {
                NSWorkspace.shared.selectFile(file.id.path(), inFileViewerRootedAtPath: "")
            } label: {
                Image(systemName: "arrow.right.circle")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(file.id.path(), inFileViewerRootedAtPath: "")
            }
        }
    }
}
