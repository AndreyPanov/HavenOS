import SwiftUI

struct StatusBadgeView: View {
    let status: ServiceStatus

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.systemImage)
                .font(.caption2)
            Text(status.rawValue)
                .font(.caption)
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(status.color.opacity(0.1))
        .clipShape(Capsule())
    }
}

#Preview {
    VStack(spacing: 12) {
        StatusBadgeView(status: .running)
        StatusBadgeView(status: .stopped)
        StatusBadgeView(status: .failed)
        StatusBadgeView(status: .installing)
    }
    .padding()
}
