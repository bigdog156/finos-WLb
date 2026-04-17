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

    enum SignUpOutcome: Equatable {
        case pendingEmailConfirmation
        case pendingAdminActivation
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

    /// Creates an auth user, upserts a pending-activation `profiles` row
    /// (role=employee, active=false) when a session is available, then signs
    /// out so the user lands back on the sign-in screen.
    func signUp(email: String, password: String, fullName: String) async throws -> SignUpOutcome {
        let response = try await client.auth.signUp(
            email: email,
            password: password,
            data: ["full_name": .string(fullName)]
        )

        if response.session != nil {
            try await upsertSelfProfile(userId: response.user.id, fullName: fullName)
            try? await client.auth.signOut()
            state = .signedOut
            return .pendingAdminActivation
        } else {
            return .pendingEmailConfirmation
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

    private func upsertSelfProfile(userId: UUID, fullName: String) async throws {
        try await client
            .from("profiles")
            .upsert(SelfProfileInsert(
                id: userId,
                fullName: fullName,
                role: UserRole.employee.rawValue,
                active: false
            ))
            .execute()
    }
}

private struct SelfProfileInsert: Encodable {
    let id: UUID
    let fullName: String
    let role: String
    let active: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case role
        case active
    }
}
