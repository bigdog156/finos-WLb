import Foundation
import Supabase

@Observable
@MainActor
final class AuthStore {
    enum State: Equatable {
        case unknown
        case signedOut
        case signedIn(Profile)
        case error(String)
    }

    private(set) var state: State = .unknown

    private var client: SupabaseClient { SupabaseManager.shared.client }

    func bootstrap() async {
        do {
            let session = try await client.auth.session
            try await loadProfile(userId: session.user.id)
        } catch {
            state = .signedOut
        }
    }

    func signIn(email: String, password: String) async {
        state = .unknown
        do {
            let session = try await client.auth.signIn(email: email, password: password)
            try await loadProfile(userId: session.user.id)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func signOut() async {
        try? await client.auth.signOut()
        state = .signedOut
    }

    private func loadProfile(userId: UUID) async throws {
        let profile: Profile = try await client
            .from("profiles")
            .select("id, full_name, role, branch_id, dept_id, active")
            .eq("id", value: userId)
            .single()
            .execute()
            .value
        state = .signedIn(profile)
    }
}
