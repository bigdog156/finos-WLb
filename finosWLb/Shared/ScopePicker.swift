import SwiftUI

/// Three-way scope shared by admin/manager reports. Centralised here so the
/// two screens can't drift in labels or ordering.
enum ReportScope: String, CaseIterable, Identifiable, Hashable, Sendable {
    case day, week, month

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day:   "Day"
        case .week:  "Week"
        case .month: "Month"
        }
    }

    /// Matches the `report_type` field the `export-report` EF expects.
    var exportType: String {
        switch self {
        case .day:   "daily"
        case .week:  "weekly"
        case .month: "monthly"
        }
    }
}

/// Segmented `Picker` wrapping `ReportScope`. Purely a styling convention
/// holder; callers bind it like any other `Picker`.
struct ScopePicker: View {
    @Binding var scope: ReportScope

    var body: some View {
        Picker("Scope", selection: $scope) {
            ForEach(ReportScope.allCases) { s in
                Text(s.label).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Report scope")
    }
}

#Preview {
    @Previewable @State var scope: ReportScope = .week
    return ScopePicker(scope: $scope).padding()
}
