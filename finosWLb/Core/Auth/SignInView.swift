import SwiftUI

struct SignInView: View {
    @Environment(AuthStore.self) private var auth

    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var isPasswordVisible = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case email, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                fieldStack
                errorBanner
                primaryButton
                orDivider
                createAccountLink
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
            .padding(.bottom, 32)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 18) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.accentColor.gradient)
                .frame(width: 82, height: 82)
                .overlay {
                    Image(systemName: "clock.badge.checkmark.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: .accentColor.opacity(0.35), radius: 14, y: 8)

            VStack(spacing: 6) {
                Text("Chào mừng trở lại")
                    .font(.largeTitle.bold())
                Text("Đăng nhập để tiếp tục")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Fields

    private var fieldStack: some View {
        VStack(spacing: 12) {
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
                            TextField("Mật khẩu", text: $password)
                        } else {
                            SecureField("Mật khẩu", text: $password)
                        }
                    }
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.go)
                    .focused($focusedField, equals: .password)
                    .onSubmit { Task { await submit() } }

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

    // MARK: - Error banner

    @ViewBuilder
    private var errorBanner: some View {
        if case .error(let message) = auth.state {
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
    }

    // MARK: - Primary button

    private var primaryButton: some View {
        Button {
            Task { await submit() }
        } label: {
            ZStack {
                if isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Text("Đăng nhập")
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

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(.separator).frame(height: 1)
            Text("HOẶC")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            Rectangle().fill(.separator).frame(height: 1)
        }
    }

    private var createAccountLink: some View {
        NavigationLink {
            SignUpView()
        } label: {
            HStack(spacing: 4) {
                Text("Chưa có tài khoản?")
                    .foregroundStyle(.secondary)
                Text("Tạo tài khoản")
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
            }
            .font(.callout)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Derived

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && !isSubmitting
    }

    // MARK: - Actions

    private func submit() async {
        guard canSubmit else { return }
        focusedField = nil
        isSubmitting = true
        await auth.signIn(
            email: email.trimmingCharacters(in: .whitespaces),
            password: password
        )
        isSubmitting = false
    }
}
