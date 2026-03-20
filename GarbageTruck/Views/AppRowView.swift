import SwiftUI

struct AppRowView: View {
    let app: AppInfo

    @State private var deletableSizeBytes: Int64?

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.id.path()))
                .resizable()
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(app.id.path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            SizeLabel(sizeBytes: deletableSizeBytes)
                .font(.callout)
        }
        .padding(.vertical, 2)
        .task(id: app.id) {
            let scanner = FileScanner()
            deletableSizeBytes = await scanner.totalDeletableSize(for: app)
        }
    }
}
