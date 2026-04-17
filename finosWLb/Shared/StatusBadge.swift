import SwiftUI

struct StatusBadge: View {
    let status: AttendanceEventStatus

    var body: some View {
        Text(status.label)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case .onTime:   .green
        case .late:     .orange
        case .flagged:  .yellow
        case .rejected: .red
        case .absent:   .secondary
        }
    }
}
