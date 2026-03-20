import SwiftUI

struct ConfidenceBadge: View {
    let confidence: Confidence

    var body: some View {
        Text(confidence.label)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor.opacity(0.15))
            .foregroundStyle(backgroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch confidence {
        case .high: .green
        case .medium: .orange
        }
    }
}
