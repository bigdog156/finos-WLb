import SwiftUI

struct ManagerRootView: View {
    let profile: Profile

    var body: some View {
        TabView {
            NavigationStack { ManagerBranchView() }
                .tabItem { Label("Chi nhánh", systemImage: "building.2") }

            NavigationStack { ManagerReviewQueue() }
                .tabItem { Label("Duyệt", systemImage: "checkmark.shield") }

            NavigationStack { ManagerLeaveReviewView() }
                .tabItem { Label("Nghỉ phép", systemImage: "sun.max.circle") }

            NavigationStack { ManagerReportsView() }
                .tabItem { Label("Báo cáo", systemImage: "chart.bar") }

            NavigationStack { ProfileTabView(profile: profile) }
                .tabItem { Label("Hồ sơ", systemImage: "person.crop.circle") }
        }
    }
}
