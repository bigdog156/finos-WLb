import SwiftUI
internal import PostgREST
import Supabase

/// Admin users screen. Fetches profiles, branches and departments up-front so
/// every row can resolve labels without extra queries, then filters client-side.
struct AdminUsersView: View {
    enum RoleFilter: String, Hashable, CaseIterable {
        case all, admin, manager, employee

        var label: String {
            switch self {
            case .all: return "Tất cả"
            case .admin: return "Quản trị viên"
            case .manager: return "Quản lý"
            case .employee: return "Nhân viên"
            }
        }
    }

    @State private var profiles: [Profile] = []
    @State private var branches: [BranchWithGeo] = []
    @State private var departments: [Department] = []

    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var roleFilter: RoleFilter = .all
    @State private var branchFilter: UUID?           // nil == All
    @State private var showInactive: Bool = false
    @State private var search: String = ""

    @State private var showingSetup = false
    @State private var banner: String?

    var body: some View {
        List {
            Section {
                Picker("Vai trò", selection: $roleFilter) {
                    ForEach(RoleFilter.allCases, id: \.self) { r in
                        Text(r.label).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if let banner {
                Section {
                    Label(banner, systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                }
            }

            ForEach(filtered) { profile in
                NavigationLink {
                    UserEditorView(
                        profile: profile,
                        branches: branches,
                        departments: departments
                    ) { _ in
                        await load()
                    }
                } label: {
                    row(profile)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        Task { await toggleActive(profile) }
                    } label: {
                        if profile.active {
                            Label("Vô hiệu hóa", systemImage: "pause.circle")
                        } else {
                            Label("Kích hoạt lại", systemImage: "play.circle")
                        }
                    }
                    .tint(profile.active ? .orange : .green)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
        .overlay { overlay }
        .navigationTitle("Người dùng")
        .searchable(text: $search, prompt: "Tìm theo tên")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSetup = true
                } label: {
                    Image(systemName: "person.crop.circle.badge.plus")
                }
                .accessibilityLabel("Thiết lập người dùng đang chờ")
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Section("Chi nhánh") {
                        Button {
                            branchFilter = nil
                        } label: {
                            Label("Tất cả chi nhánh", systemImage: branchFilter == nil ? "checkmark" : "")
                        }
                        ForEach(branches) { b in
                            Button {
                                branchFilter = b.id
                            } label: {
                                Label(b.name, systemImage: branchFilter == b.id ? "checkmark" : "")
                            }
                        }
                    }
                    Divider()
                    Toggle("Hiển thị người ngừng hoạt động", isOn: $showInactive)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Bộ lọc")
            }
        }
        .sheet(isPresented: $showingSetup) {
            SetupPendingUserView(
                branches: branches,
                departments: departments
            ) { updated in
                // Reload first (which clears banner), then set the success
                // message so it survives until the next explicit reload.
                await load()
                banner = "Đã cập nhật"
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Row

    private func row(_ profile: Profile) -> some View {
        HStack(spacing: 12) {
            avatar(for: profile.fullName, tint: roleTint(profile.role))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(profile.fullName).font(.headline)
                    rolePill(profile.role)
                }
                Text(subtitle(for: profile))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if !profile.active {
                Text("Ngừng hoạt động")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.15), in: Capsule())
            }
        }
        .padding(.vertical, 4)
        .opacity(profile.active ? 1 : 0.5)
    }

    private func avatar(for name: String, tint: Color) -> some View {
        Circle()
            .fill(tint.opacity(0.18))
            .frame(width: 40, height: 40)
            .overlay {
                Text(initials(from: name))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            }
    }

    private func rolePill(_ role: UserRole) -> some View {
        let tint = roleTint(role)
        return Text(roleLabel(role))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(tint)
            .background(tint.opacity(0.15), in: Capsule())
    }

    private func roleTint(_ role: UserRole) -> Color {
        switch role {
        case .admin:    .purple
        case .manager:  .blue
        case .employee: .teal
        }
    }

    private func subtitle(for profile: Profile) -> String {
        var parts: [String] = []
        if let id = profile.branchId, let b = branches.first(where: { $0.id == id }) {
            parts.append(b.name)
        }
        if let id = profile.deptId, let d = departments.first(where: { $0.id == id }) {
            parts.append(d.name)
        }
        if parts.isEmpty { return "Chưa phân công" }
        return parts.joined(separator: " · ")
    }

    private func roleLabel(_ role: UserRole) -> String {
        switch role {
        case .admin: return "Quản trị viên"
        case .manager: return "Quản lý"
        case .employee: return "Nhân viên"
        }
    }

    private func initials(from name: String) -> String {
        let parts = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        return parts.compactMap(\.first).map { String($0).uppercased() }.joined()
    }

    // MARK: - Overlay

    @ViewBuilder
    private var overlay: some View {
        if isLoading && profiles.isEmpty {
            ProgressView()
        } else if let errorMessage, profiles.isEmpty {
            ContentUnavailableView(
                "Không thể tải người dùng",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
        } else if profiles.isEmpty {
            ContentUnavailableView(
                "Chưa có người dùng",
                systemImage: "person.3",
                description: Text("Nhấn + để mời người dùng đầu tiên.")
            )
        } else if filtered.isEmpty {
            ContentUnavailableView.search(text: search)
        }
    }

    // MARK: - Derived

    private var filtered: [Profile] {
        var out = profiles

        if !showInactive {
            out = out.filter(\.active)
        }

        switch roleFilter {
        case .all: break
        case .admin: out = out.filter { $0.role == .admin }
        case .manager: out = out.filter { $0.role == .manager }
        case .employee: out = out.filter { $0.role == .employee }
        }

        if let branchFilter {
            out = out.filter { $0.branchId == branchFilter }
        }

        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            out = out.filter { $0.fullName.localizedCaseInsensitiveContains(q) }
        }

        return out.sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
    }

    // MARK: - Networking

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        // Success banners are per-action; any reload signals the banner's
        // moment has passed.
        banner = nil

        async let profilesTask: [Profile] = SupabaseManager.shared.client
            .from("profiles")
            .select("id, full_name, role, branch_id, dept_id, active")
            .order("full_name")
            .execute()
            .value

        async let branchesTask: [BranchWithGeo] = SupabaseManager.shared.client
            .from("branches_with_geo")
            .select()
            .order("name")
            .execute()
            .value

        async let departmentsTask: [Department] = SupabaseManager.shared.client
            .from("departments")
            .select("id, name")
            .order("name")
            .execute()
            .value

        do {
            let (p, b, d) = try await (profilesTask, branchesTask, departmentsTask)
            profiles = p
            branches = b
            departments = d
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleActive(_ profile: Profile) async {
        let next = !profile.active
        do {
            let payload = ActiveTogglePayload(active: next)
            try await SupabaseManager.shared.client
                .from("profiles")
                .update(payload)
                .eq("id", value: profile.id.uuidString)
                .execute()
            if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[idx] = Profile(
                    id: profile.id,
                    fullName: profile.fullName,
                    role: profile.role,
                    branchId: profile.branchId,
                    deptId: profile.deptId,
                    active: next
                )
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Tiny update DTO

private struct ActiveTogglePayload: Encodable, Sendable {
    let active: Bool
}
