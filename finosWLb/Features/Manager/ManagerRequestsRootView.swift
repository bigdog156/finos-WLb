import SwiftUI

/// Hosts the two manager-facing request queues (leave + attendance
/// correction) behind a segmented picker. Kept as its own tab so the
/// manager's TabView stays under iOS's 5-tab limit.
struct ManagerRequestsRootView: View {
    enum Tab: String, Hashable, CaseIterable {
        case leave, correction

        var label: String {
            switch self {
            case .leave:      "Nghỉ phép"
            case .correction: "Bổ sung công"
            }
        }

        var systemImage: String {
            switch self {
            case .leave:      "sun.max"
            case .correction: "calendar.badge.plus"
            }
        }
    }

    @State private var selected: Tab = .leave

    var body: some View {
        VStack(spacing: 0) {
            Picker("Loại đơn", selection: $selected) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Label(tab.label, systemImage: tab.systemImage).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            switch selected {
            case .leave:
                ManagerLeaveReviewView()
            case .correction:
                ManagerCorrectionReviewView()
            }
        }
        .navigationTitle("Đơn từ")
        .navigationBarTitleDisplayMode(.inline)
    }
}
