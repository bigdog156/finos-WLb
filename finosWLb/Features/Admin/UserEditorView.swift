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
            Section("Identity") {
                TextField("Full name", text: $fullName)
                    .textInputAutocapitalization(.words)
            }

            Section {
                Picker("Role", selection: $role) {
                    ForEach(UserRole.allCases, id: \.self) { r in
                        Text(r.rawValue.capitalized).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isSelfEdit)
            } header: {
                Text("Role")
            } footer: {
                if isSelfEdit {
                    Text("You can't change your own role.")
                }
            }

            Section {
                branchMenu
                departmentMenu
            } header: {
                Text("Assignment")
            } footer: {
                if role != .admin && branchId == nil {
                    Text("Managers and employees must be assigned to a branch.")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Toggle("Active", isOn: $active)
                    .disabled(isSelfEdit)
            } header: {
                Text("Status")
            } footer: {
                if isSelfEdit {
                    Text("You can't deactivate your own account.")
                }
            }

            if active && !isSelfEdit {
                Section {
                    Button(role: .destructive) {
                        active = false
                        Task { await save() }
                    } label: {
                        Text("Deactivate user")
                    }
                    .disabled(isSaving)
                } header: {
                    Text("Danger zone")
                } footer: {
                    Text("Deactivated users can no longer sign in. Reactivate them anytime.")
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
                        Text("Save").fontWeight(.semibold)
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
                Label("None", systemImage: branchId == nil ? "checkmark" : "")
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
                Text("Branch")
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
                Label("None", systemImage: deptId == nil ? "checkmark" : "")
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
                Text("Department")
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
        return "None"
    }

    private var deptLabel: String {
        if let id = deptId, let d = departments.first(where: { $0.id == id }) {
            return d.name
        }
        return "None"
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
                    errorMessage = "You can't deactivate or demote the last active admin."
                    return
                }
            } catch {
                errorMessage = "Couldn't verify admin count: \(error.localizedDescription)"
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
