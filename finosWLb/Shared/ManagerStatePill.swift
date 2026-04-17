import SwiftUI

/// Pill used by the manager Branch list. Parallels `StatusBadge` but keyed to
/// the derived per-employee state instead of an individual event's status.
struct ManagerStatePill: View {
    let state: BranchEmployeeToday.DerivedState

    var body: some View {
        Text(state.label)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch state {
        case .flagged: .yellow
        case .late:    .orange
        case .absent:  .secondary
        case .present: .green
        case .out:     .blue
        }
    }
}
