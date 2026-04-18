import SwiftUI

struct EmployeeRootView: View {
    let profile: Profile

    var body: some View {
        TabView {
            NavigationStack { TodayView() }
                .tabItem { Label("Hôm nay", systemImage: "clock.badge.checkmark") }

            NavigationStack { EmployeeHistoryView() }
                .tabItem { Label("Lịch sử", systemImage: "list.bullet.rectangle") }

            NavigationStack { EmployeeLeavesView(profile: profile) }
                .tabItem { Label("Nghỉ phép", systemImage: "sun.max") }

            NavigationStack { ProfileTabView(profile: profile) }
                .tabItem { Label("Hồ sơ", systemImage: "person.crop.circle") }
        }
    }
}
