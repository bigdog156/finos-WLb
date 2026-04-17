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

            Section("Role") {
                Picker("Role", selection: $role) {
                    ForEach(UserRole.allCases, id: \.self) { r in
                        Text(r.rawValue.capitalized).tag(r)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Assignment") {
                branchMenu
                departmentMenu
            }

            Section("Status") {
                Toggle("Active", isOn: $active)
            }

            if active {
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

    private var isValid: Bool {
        !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasChanges: Bool {
        fullName.trimmingCharacters(in: .whitespacesAndNewlines) != initialProfile.fullName
            || role != initialProfile.role
            || branchId != initialProfile.branchId
            || deptId != initialProfile.deptId
            || active != initialProfile.active
    }

    // MARK: - Networking

    private func save() async {
        guard isValid, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

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
