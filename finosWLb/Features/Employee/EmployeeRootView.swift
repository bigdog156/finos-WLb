import SwiftUI

struct EmployeeRootView: View {
    let profile: Profile

    var body: some View {
        TabView {
            NavigationStack { TodayView() }
                .tabItem { Label("Today", systemImage: "clock.badge.checkmark") }

            NavigationStack { EmployeeHistoryView() }
                .tabItem { Label("History", systemImage: "list.bullet.rectangle") }

            NavigationStack { ProfileTabView(profile: profile) }
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}
