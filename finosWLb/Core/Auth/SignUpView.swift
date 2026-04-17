import SwiftUI

struct SignUpView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var outcome: AuthStore.SignUpOutcome?

    var body: some View {
        Form {
            if let outcome {
                outcomeSection(outcome)
            } else {
                formSections
            }
        }
        .navigationTitle("Create account")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var formSections: some View {
        Section("Your name") {
            TextField("Full name", text: $fullName)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
        }
        Section("Credentials") {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password (min. 6 characters)", text: $password)
                .textContentType(.newPassword)
            SecureField("Confirm password", text: $confirmPassword)
                .textContentType(.newPassword)
            if !confirmPassword.isEmpty, password != confirmPassword {
                Text("Passwords don't match.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }

        if let errorMessage {
            Section {
                Text(errorMessage).foregroundStyle(.red)
            }
        }

        Section {
            Button {
                Task { await submit() }
            } label: {
                HStack {
                    Text("Create account")
                    if isSubmitting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(!canSubmit || isSubmitting)
        } footer: {
            Text("New accounts are created as employees and remain inactive until an administrator activates them.")
        }
    }

    @ViewBuilder
    private func outcomeSection(_ outcome: AuthStore.SignUpOutcome) -> some View {
        Section {
            switch outcome {
            case .pendingEmailConfirmation:
                VStack(alignment: .leading, spacing: 8) {
                    Label("Check your email", systemImage: "envelope.badge")
                        .font(.headline)
                    Text("We sent a confirmation link to \(email). Confirm it, then wait for an administrator to activate your account before signing in.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            case .pendingAdminActivation:
                VStack(alignment: .leading, spacing: 8) {
                    Label("Account created", systemImage: "checkmark.circle")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text("An administrator will review and activate your account. You'll be able to sign in once it's active.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        Section {
            Button("Back to sign in") { dismiss() }
        }
    }

    private var canSubmit: Bool {
        let name = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let mail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty
            && mail.contains("@")
            && password.count >= 6
            && password == confirmPassword
    }

    private func submit() async {
        guard canSubmit, !isSubmitting else { return }
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
            errorMessage = error.localizedDescription
        }
    }
}
