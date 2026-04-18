import SwiftUI

/// Admin home. Folds the former per-feature tabs into a Settings-style list
/// under a single "Admin" tab, keeping "Profile" on its own tab since it's
/// cross-cutting and every role has it.
struct AdminRootView: View {
    let profile: Profile

    var body: some View {
        TabView {
            NavigationStack { AdminSettingsList() }
                .tabItem { Label("Quản trị", systemImage: "gearshape") }

            NavigationStack { ProfileTabView(profile: profile) }
                .tabItem { Label("Hồ sơ", systemImage: "person.crop.circle") }
        }
    }
}

/// The Settings.app-style root for admin tooling. Each row pushes a
/// dedicated feature screen. The top section hosts an "at-a-glance"
/// quick-stats card so the admin sees today's critical numbers without
/// tapping into the full dashboard.
private struct AdminSettingsList: View {
    var body: some View {
        List {
            Section {
                AdminQuickStatsCard()
                    .listRowInsets(.init(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                    )
                    .listRowSeparator(.hidden)
            }

            Section {
                NavigationLink {
                    BranchesListView()
                } label: {
                    SettingsRow(
                        title: "Chi nhánh",
                        systemImage: "building.2",
                        tint: .blue
                    )
                }
                NavigationLink {
                    AdminUsersView()
                } label: {
                    SettingsRow(
                        title: "Người dùng",
                        systemImage: "person.3",
                        tint: .indigo
                    )
                }
                NavigationLink {
                    DepartmentsView()
                } label: {
                    SettingsRow(
                        title: "Phòng ban",
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
                        title: "Báo cáo",
                        systemImage: "doc.text.magnifyingglass",
                        tint: .purple
                    )
                }
                NavigationLink {
                    AuditLogView()
                } label: {
                    SettingsRow(
                        title: "Nhật ký kiểm toán",
                        systemImage: "doc.text.magnifyingglass",
                        tint: .gray
                    )
                }
                NavigationLink {
                    AdminDashboardView()
                } label: {
                    SettingsRow(
                        title: "Tổng quan",
                        systemImage: "chart.pie",
                        tint: .orange
                    )
                }
            }
        }
        .navigationTitle("Quản trị")
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
