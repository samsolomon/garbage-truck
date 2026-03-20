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

                Text(file.id.deletingLastPathComponent().path())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer()

            ConfidenceBadge(confidence: file.confidence)

            SizeLabel(sizeBytes: file.sizeBytes)
                .frame(width: 70, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }
}
