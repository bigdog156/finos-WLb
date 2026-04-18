import SwiftUI

struct SignUpView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isSubmitting = false
    @State private var isPasswordVisible = false
    @State private var errorMessage: String?
    @State private var outcome: AuthStore.SignUpOutcome?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case name, email, password, confirm }

    var body: some View {
        ScrollView {
            Group {
                if let outcome {
                    outcomeView(outcome)
                } else {
                    formBody
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Form body

    private var formBody: some View {
        VStack(spacing: 24) {
            header
            fieldStack
            if !passwordMismatch && errorMessage == nil {
                footnote
            }
            inlineValidation
            primaryButton
            bottomLink
        }
    }

    private var header: some View {
        VStack(spacing: 18) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.accentColor.gradient)
                .frame(width: 82, height: 82)
                .overlay {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: .accentColor.opacity(0.35), radius: 14, y: 8)
            VStack(spacing: 6) {
                Text("Tạo tài khoản")
                    .font(.largeTitle.bold())
                Text("Tham gia cùng nhóm của bạn trong vài giây")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var fieldStack: some View {
        VStack(spacing: 12) {
            fieldRow(icon: "person") {
                TextField("Họ và tên", text: $fullName)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .name)
                    .onSubmit { focusedField = .email }
            }

            fieldRow(icon: "envelope") {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focusedField, equals: .email)
                    .onSubmit { focusedField = .password }
            }

            fieldRow(icon: "lock") {
                HStack(spacing: 8) {
                    Group {
                        if isPasswordVisible {
                            TextField("Mật khẩu (tối thiểu 6 ký tự)", text: $password)
                        } else {
                            SecureField("Mật khẩu (tối thiểu 6 ký tự)", text: $password)
                        }
                    }
                    .textContentType(.newPassword)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .password)
                    .onSubmit { focusedField = .confirm }

                    Button {
                        isPasswordVisible.toggle()
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPasswordVisible ? "Ẩn mật khẩu" : "Hiện mật khẩu")
                }
            }

            fieldRow(icon: "lock.rotation") {
                Group {
                    if isPasswordVisible {
                        TextField("Xác nhận mật khẩu", text: $confirmPassword)
                    } else {
                        SecureField("Xác nhận mật khẩu", text: $confirmPassword)
                    }
                }
                .textContentType(.newPassword)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.go)
                .focused($focusedField, equals: .confirm)
                .onSubmit { Task { await submit() } }
            }
        }
    }

    @ViewBuilder
    private func fieldRow<Content: View>(
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            content()
                .font(.body)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.separator.opacity(0.6), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var footnote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.tint)
            Text("Tài khoản mới tham gia với vai trò nhân viên và chưa được kích hoạt cho đến khi quản trị viên gán chi nhánh và kích hoạt.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.tint.opacity(0.08))
        )
    }

    @ViewBuilder
    private var inlineValidation: some View {
        if passwordMismatch {
            validationRow("Mật khẩu không khớp.")
        }
        if let errorMessage {
            validationRow(errorMessage)
        }
    }

    private func validationRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.red.opacity(0.1))
        )
    }

    private var primaryButton: some View {
        Button {
            Task { await submit() }
        } label: {
            ZStack {
                if isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Text("Tạo tài khoản")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .controlSize(.large)
        .disabled(!canSubmit)
    }

    private var bottomLink: some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: 4) {
                Text("Đã có tài khoản?")
                    .foregroundStyle(.secondary)
                Text("Đăng nhập")
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
            }
            .font(.callout)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Outcome view

    @ViewBuilder
    private func outcomeView(_ outcome: AuthStore.SignUpOutcome) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 16)

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(outcome.tintColor.gradient)
                .frame(width: 96, height: 96)
                .overlay {
                    Image(systemName: outcome.iconName)
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: outcome.tintColor.opacity(0.35), radius: 16, y: 8)

            VStack(spacing: 8) {
                Text(outcome.title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(outcomeMessage(outcome))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            Button {
                dismiss()
            } label: {
                Text("Quay lại đăng nhập")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .controlSize(.large)
            .padding(.top, 8)
        }
    }

    private func outcomeMessage(_ outcome: AuthStore.SignUpOutcome) -> String {
        switch outcome {
        case .pendingEmailConfirmation:
            "Chúng tôi đã gửi liên kết xác nhận đến \(email). Vui lòng xác nhận, sau đó chờ quản trị viên kích hoạt tài khoản."
        case .pendingAdminActivation:
            "Quản trị viên sẽ xem xét và kích hoạt tài khoản. Bạn có thể đăng nhập sau khi tài khoản được kích hoạt."
        }
    }

    // MARK: - Derived

    private var passwordMismatch: Bool {
        !confirmPassword.isEmpty && password != confirmPassword
    }

    private var canSubmit: Bool {
        let name = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let mail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty
            && mail.contains("@")
            && password.count >= 6
            && password == confirmPassword
            && !isSubmitting
    }

    // MARK: - Actions

    private func submit() async {
        guard canSubmit else { return }
        focusedField = nil
        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil
        do {
            outcome = try await auth.signUp(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch {
            errorMessage = AuthStore.friendlyAuthMessage(error)
        }
    }
}

// MARK: - Outcome visuals

private extension AuthStore.SignUpOutcome {
    var iconName: String {
        switch self {
        case .pendingEmailConfirmation: "envelope.badge.fill"
        case .pendingAdminActivation:   "checkmark.seal.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .pendingEmailConfirmation: .blue
        case .pendingAdminActivation:   .green
        }
    }

    var title: String {
        switch self {
        case .pendingEmailConfirmation: "Kiểm tra email"
        case .pendingAdminActivation:   "Đã tạo tài khoản"
        }
    }
}
