import SwiftUI
import Supabase

/// Sheet-presented form that POSTs to the `create-user` Edge Function.
/// 2xx → dismiss and report success upstream. 409 (email_exists) surfaces
/// inline under the email field; other errors become an alert.
struct InviteUserView: View {
    let branches: [BranchWithGeo]
    let departments: [Department]
    /// Invoked on successful invite so the parent can reload and toast.
    var onInvited: (InviteUserResponse) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var email: String = ""
    @State private var fullName: String = ""
    @State private var role: UserRole = .employee
    @State private var branchId: UUID?
    @State private var deptId: UUID?

    @State private var isSubmitting = false
    @State private var emailError: String?
    @State private var generalError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Email") {
                    TextField("name@example.com", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.emailAddress)
                    if let emailError {
                        Text(emailError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Identity") {
                    TextField("Full name", text: $fullName)
                        .textInputAutocapitalization(.words)
                        .textContentType(.name)
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
                    if role != .admin, branchId == nil {
                        Text("Branch is required for managers and employees.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let generalError {
                    Section {
                        Text(generalError)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Invite user")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("Send invite").fontWeight(.semibold)
                        }
                    }
                    .disabled(!canSubmit || isSubmitting)
                }
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
                Text(branchLabel)
                    .foregroundStyle(.secondary)
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
                Text(deptLabel)
                    .foregroundStyle(.secondary)
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

    private var canSubmit: Bool {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !e.isEmpty, e.contains("@"), !n.isEmpty else { return false }
        if role != .admin, branchId == nil { return false }
        return true
    }

    // MARK: - Networking

    private func submit() async {
        guard canSubmit, !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        emailError = nil
        generalError = nil

        let body = InviteUserBody(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
            role: role.rawValue,
            branchId: branchId,
            deptId: deptId
        )

        do {
            let response: InviteUserResponse = try await SupabaseManager.shared.client
                .functions
                .invoke(
                    "create-user",
                    options: FunctionInvokeOptions(body: body)
                )
            dismiss()
            await onInvited(response)
        } catch let FunctionsError.httpError(code, data) where code == 409 {
            if let decoded = try? JSONDecoder().decode(InviteUserErrorResponse.self, from: data),
               decoded.error == "email_exists" {
                emailError = "Email already in use."
            } else {
                emailError = "Email already in use."
            }
        } catch let FunctionsError.httpError(code, _) where code == 403 {
            generalError = "You don't have permission to invite users."
        } catch {
            generalError = error.localizedDescription
        }
    }
}
