import SwiftUI

struct SizeLabel: View {
    let sizeBytes: Int64?

    var body: some View {
        if let sizeBytes {
            Text(ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        } else {
            Text("...")
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
    }
}
