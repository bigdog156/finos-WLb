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
                    TextField("ten@vidu.com", text: $email)
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

                Section("Danh tính") {
                    TextField("Họ và tên", text: $fullName)
                        .textInputAutocapitalization(.words)
                        .textContentType(.name)
                }

                Section("Vai trò") {
                    Picker("Vai trò", selection: $role) {
                        ForEach(UserRole.allCases, id: \.self) { r in
                            Text(roleLabel(r)).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Phân công") {
                    branchMenu
                    departmentMenu
                    if role != .admin, branchId == nil {
                        Text("Chi nhánh là bắt buộc đối với quản lý và nhân viên.")
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
            .navigationTitle("Mời người dùng")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("Gửi lời mời").fontWeight(.semibold)
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
                .invokeFunction("create-user", body: body)
            dismiss()
            await onInvited(response)
        } catch let InvokeError.edgeFunctionError(status, code, detail) where status == 409 {
            if code == "email_exists" {
                emailError = "Email đã được sử dụng."
            } else {
                emailError = detail ?? "Email đã được sử dụng."
            }
        } catch let InvokeError.edgeFunctionError(status, _, _) where status == 403 {
            generalError = "Bạn không có quyền mời người dùng."
        } catch let InvokeError.edgeFunctionError(status, code, detail) {
            generalError = detail ?? code ?? "HTTP \(status)"
        } catch InvokeError.noSession {
            generalError = "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại."
        } catch {
            generalError = error.localizedDescription
        }
    }
}
