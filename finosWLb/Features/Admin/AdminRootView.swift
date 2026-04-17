import SwiftUI

/// Admin home. Folds the former per-feature tabs into a Settings-style list
/// under a single "Admin" tab, keeping "Profile" on its own tab since it's
/// cross-cutting and every role has it.
struct AdminRootView: View {
    let profile: Profile

    var body: some View {
        TabView {
            NavigationStack { AdminSettingsList() }
                .tabItem { Label("Admin", systemImage: "gearshape") }

            NavigationStack { ProfileTabView(profile: profile) }
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}

/// The Settings.app-style root for admin tooling. Each row pushes a
/// dedicated feature screen.
private struct AdminSettingsList: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    BranchesListView()
                } label: {
                    SettingsRow(
                        title: "Branches",
                        systemImage: "building.2",
                        tint: .blue
                    )
                }
                NavigationLink {
                    AdminUsersView()
                } label: {
                    SettingsRow(
                        title: "Users",
                        systemImage: "person.3",
                        tint: .indigo
                    )
                }
                NavigationLink {
                    DepartmentsView()
                } label: {
                    SettingsRow(
                        title: "Departments",
                        systemImage: "rectangle.3.group",
                        tint: .teal
                    )
                }
            }

            Section {
                NavigationLink {
                    AdminReportsView()
                } label: {
                    SettingsRow(
                        title: "Reports",
                        systemImage: "doc.text.magnifyingglass",
                        tint: .purple
                    )
                }
                NavigationLink {
                    AuditLogView()
                } label: {
                    SettingsRow(
                        title: "Audit Log",
                        systemImage: "doc.text.magnifyingglass",
                        tint: .gray
                    )
                }
                NavigationLink {
                    AdminDashboardView()
                } label: {
                    SettingsRow(
                        title: "Dashboard",
                        systemImage: "chart.pie",
                        tint: .orange
                    )
                }
            }
        }
        .navigationTitle("Admin")
    }
}

/// Tinted-square + label row mimicking iOS Settings.
private struct SettingsRow: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tint)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)
            Text(title)
        }
    }
}
