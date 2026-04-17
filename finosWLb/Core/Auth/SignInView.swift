import SwiftUI

struct SignInView: View {
    @Environment(AuthStore.self) private var auth
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false

    var body: some View {
        Form {
            Section("Credentials") {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textContentType(.password)
            }

            Section {
                Button {
                    Task {
                        isSubmitting = true
                        await auth.signIn(email: email, password: password)
                        isSubmitting = false
                    }
                } label: {
                    HStack {
                        Text("Sign In")
                        if isSubmitting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(email.isEmpty || password.isEmpty || isSubmitting)
            }

            if case .error(let message) = auth.state {
                Section {
                    Text(message).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Sign In")
    }
}
