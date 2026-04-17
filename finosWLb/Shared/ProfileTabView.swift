import SwiftUI

struct ProfileTabView: View {
    let profile: Profile
    @Environment(AuthStore.self) private var auth

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Name", value: profile.fullName)
                LabeledContent("Role", value: profile.role.rawValue.capitalized)
            }
            Section {
                Button("Sign Out", role: .destructive) {
                    Task { await auth.signOut() }
                }
            }
        }
        .navigationTitle("Profile")
    }
}
