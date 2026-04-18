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
            state = .error(Self.friendlyAuthMessage(error))
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

    /// Translates Supabase/Auth errors into user-facing copy. Never exposes
    /// raw HTTP status codes or SDK jargon — the caller lands in the error
    /// banner on the sign-in/up screen.
    static func friendlyAuthMessage(_ error: Error) -> String {
        let raw = error.localizedDescription.lowercased()

        if raw.contains("invalid login") || raw.contains("invalid_credentials") || raw.contains("invalid grant") {
            return "Email hoặc mật khẩu không đúng."
        }
        if raw.contains("email not confirmed") || raw.contains("email_not_confirmed") {
            return "Vui lòng xác nhận email, sau đó thử lại."
        }
        if raw.contains("user already registered") || raw.contains("email_exists") || raw.contains("already been registered") {
            return "Email này đã được đăng ký."
        }
        if raw.contains("password should be") || raw.contains("weak_password") {
            return "Mật khẩu quá yếu. Vui lòng dùng ít nhất 6 ký tự."
        }
        if raw.contains("rate limit") || raw.contains("too many requests") {
            return "Quá nhiều lần thử. Vui lòng chờ một chút rồi thử lại."
        }
        if raw.contains("network") || raw.contains("offline") || raw.contains("internet") {
            return "Bạn đang ngoại tuyến. Kiểm tra kết nối và thử lại."
        }
        if raw.contains("timed out") || raw.contains("timeout") {
            return "Yêu cầu đã hết thời gian. Vui lòng thử lại."
        }
        if raw.contains("403") || raw.contains("401") || raw.contains("unauthor") {
            return "Không thể xác minh thông tin đăng nhập. Vui lòng thử lại."
        }
        if raw.contains("500") || raw.contains("502") || raw.contains("503") || raw.contains("504") {
            return "Máy chủ đang gặp sự cố. Vui lòng thử lại sau giây lát."
        }
        return "Đã có lỗi xảy ra. Vui lòng thử lại."
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
