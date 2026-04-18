import SwiftUI
internal import PostgREST
import Supabase

/// Push-to editor for an existing profile. Updates go to PostgREST directly
/// (admin RLS allows full updates on `profiles`). Deactivation is the closest
/// thing to a hard delete — `active = false` hides the user everywhere.
struct UserEditorView: View {
    let initialProfile: Profile
    let branches: [BranchWithGeo]
    let departments: [Department]
    var onSaved: (Profile) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var fullName: String
    @State private var role: UserRole
    @State private var branchId: UUID?
    @State private var deptId: UUID?
    @State private var active: Bool

    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var currentUserId: UUID?

    init(
        profile: Profile,
        branches: [BranchWithGeo],
        departments: [Department],
        onSaved: @escaping (Profile) async -> Void
    ) {
        self.initialProfile = profile
        self.branches = branches
        self.departments = departments
        self.onSaved = onSaved
        _fullName = State(initialValue: profile.fullName)
        _role = State(initialValue: profile.role)
        _branchId = State(initialValue: profile.branchId)
        _deptId = State(initialValue: profile.deptId)
        _active = State(initialValue: profile.active)
    }

    var body: some View {
        Form {
            Section("Danh tính") {
                TextField("Họ và tên", text: $fullName)
                    .textInputAutocapitalization(.words)
            }

            Section {
                Picker("Vai trò", selection: $role) {
                    ForEach(UserRole.allCases, id: \.self) { r in
                        Text(roleLabel(r)).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isSelfEdit)
            } header: {
                Text("Vai trò")
            } footer: {
                if isSelfEdit {
                    Text("Bạn không thể thay đổi vai trò của chính mình.")
                }
            }

            Section {
                branchMenu
                departmentMenu
            } header: {
                Text("Phân công")
            } footer: {
                if role != .admin && branchId == nil {
                    Text("Quản lý và nhân viên phải được phân công vào một chi nhánh.")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Toggle("Hoạt động", isOn: $active)
                    .disabled(isSelfEdit)
            } header: {
                Text("Trạng thái")
            } footer: {
                if isSelfEdit {
                    Text("Bạn không thể vô hiệu hóa tài khoản của chính mình.")
                }
            }

            if active && !isSelfEdit {
                Section {
                    Button(role: .destructive) {
                        active = false
                        Task { await save() }
                    } label: {
                        Text("Vô hiệu hóa người dùng")
                    }
                    .disabled(isSaving)
                } header: {
                    Text("Vùng nguy hiểm")
                } footer: {
                    Text("Người dùng bị vô hiệu hóa không thể đăng nhập. Bạn có thể kích hoạt lại bất cứ lúc nào.")
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
        .navigationTitle(initialProfile.fullName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Lưu").fontWeight(.semibold)
                    }
                }
                .disabled(!isValid || !hasChanges || isSaving)
            }
        }
        .task {
            if currentUserId == nil {
                currentUserId = try? await SupabaseManager.shared.client.auth.session.user.id
            }
        }
    }

    // MARK: - Pickers

    private var branchMenu: some View {
        Menu {
            Button {
                branchId = nil
            } label: {
                Label("Không", systemImage: branchId == nil ? "checkmark" : "")
            }
            Divider()
            ForEach(branches) { b in
                Button {
                    branchId = b.id
                } label: {
                    Label(b.name, systemImage: branchId == b.id ? "checkmark" : "")
                }
            }
        } label: {
            HStack {
                Text("Chi nhánh")
                Spacer()
                Text(branchLabel).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
    }

    private var departmentMenu: some View {
        Menu {
            Button {
                deptId = nil
            } label: {
                Label("Không", systemImage: deptId == nil ? "checkmark" : "")
            }
            Divider()
            ForEach(departments) { d in
                Button {
                    deptId = d.id
                } label: {
                    Label(d.name, systemImage: deptId == d.id ? "checkmark" : "")
                }
            }
        } label: {
            HStack {
                Text("Phòng ban")
                Spacer()
                Text(deptLabel).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
    }

    private var branchLabel: String {
        if let id = branchId, let b = branches.first(where: { $0.id == id }) {
            return b.name
        }
        return "Không"
    }

    private var deptLabel: String {
        if let id = deptId, let d = departments.first(where: { $0.id == id }) {
            return d.name
        }
        return "Không"
    }

    private func roleLabel(_ role: UserRole) -> String {
        switch role {
        case .admin: return "Quản trị viên"
        case .manager: return "Quản lý"
        case .employee: return "Nhân viên"
        }
    }

    // MARK: - Derived

    private var isSelfEdit: Bool {
        currentUserId == initialProfile.id
    }

    private var isValid: Bool {
        guard !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if role != .admin && branchId == nil { return false }
        return true
    }

    private var hasChanges: Bool {
        fullName.trimmingCharacters(in: .whitespacesAndNewlines) != initialProfile.fullName
            || role != initialProfile.role
            || branchId != initialProfile.branchId
            || deptId != initialProfile.deptId
            || active != initialProfile.active
    }

    /// True when this save would remove the last active admin — demoting an
    /// active admin or deactivating one. The check is skipped for non-admins
    /// and for no-op saves on admins.
    private var wouldRemoveActiveAdmin: Bool {
        initialProfile.role == .admin
            && initialProfile.active
            && (role != .admin || !active)
    }

    // MARK: - Networking

    private func save() async {
        guard isValid, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        if wouldRemoveActiveAdmin {
            do {
                let remaining = try await countOtherActiveAdmins()
                if remaining == 0 {
                    errorMessage = "Bạn không thể vô hiệu hóa hoặc hạ cấp quản trị viên hoạt động cuối cùng."
                    return
                }
            } catch {
                errorMessage = "Không thể xác minh số quản trị viên: \(error.localizedDescription)"
                return
            }
        }

        let payload = ProfileUpdatePayload(
            fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
            role: role.rawValue,
            branchId: branchId,
            deptId: deptId,
            active: active
        )

        do {
            try await SupabaseManager.shared.client
                .from("profiles")
                .update(payload)
                .eq("id", value: initialProfile.id.uuidString)
                .execute()

            let updated = Profile(
                id: initialProfile.id,
                fullName: payload.fullName,
                role: role,
                branchId: branchId,
                deptId: deptId,
                active: active
            )
            await onSaved(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func countOtherActiveAdmins() async throws -> Int {
        let response = try await SupabaseManager.shared.client
            .from("profiles")
            .select("id", head: true, count: .exact)
            .eq("role", value: UserRole.admin.rawValue)
            .eq("active", value: true)
            .neq("id", value: initialProfile.id.uuidString)
            .execute()
        return response.count ?? 0
    }
}

// MARK: - Update DTO

private struct ProfileUpdatePayload: Encodable, Sendable {
    let fullName: String
    let role: String
    let branchId: UUID?
    let deptId: UUID?
    let active: Bool

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case role
        case branchId = "branch_id"
        case deptId = "dept_id"
        case active
    }
}
