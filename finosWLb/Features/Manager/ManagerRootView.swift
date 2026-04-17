import SwiftUI

struct ManagerRootView: View {
    let profile: Profile

    var body: some View {
        TabView {
            NavigationStack { ManagerBranchView() }
                .tabItem { Label("Branch", systemImage: "building.2") }

            NavigationStack { ManagerReviewQueue() }
                .tabItem { Label("Review", systemImage: "checkmark.shield") }

            NavigationStack { ManagerReportsView() }
                .tabItem { Label("Reports", systemImage: "chart.bar") }

            NavigationStack { ProfileTabView(profile: profile) }
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}
