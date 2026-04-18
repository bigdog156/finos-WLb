import Foundation
import OSLog
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
    private var listenerTask: Task<Void, Never>?
    /// `bootstrap()` is the canonical cold-start loader. Once it's run, the
    /// listener skips its own `.initialSession` handler so we don't issue
    /// two identical profile queries on launch.
    private var didBootstrap = false

    /// Kicks off the initial session load and starts the auth state listener.
    /// Safe to call multiple times — the listener is rebound each time.
    func bootstrap() async {
        AppLog.auth.info("bootstrap started")
        startListening()

        do {
            let session = try await client.auth.session
            AppLog.auth.info("bootstrap — session found for user \(session.user.id.uuidString, privacy: .public)")
            try await loadProfile(userId: session.user.id)
            AppLog.auth.info("bootstrap — signedIn (role, active loaded)")
        } catch {
            AppLog.auth.info("bootstrap — no valid session: \(logMessage(for: error), privacy: .public)")
            state = .signedOut
        }
        didBootstrap = true
    }

    func signIn(email: String, password: String) async {
        AppLog.auth.info("signIn requested")
        state = .unknown
        do {
            let session = try await client.auth.signIn(email: email, password: password)
            AppLog.auth.info("signIn succeeded for user \(session.user.id.uuidString, privacy: .public)")
            try await loadProfile(userId: session.user.id)
            AppLog.auth.info("signIn — profile loaded, signedIn")
        } catch {
            AppLog.auth.error("signIn failed: \(logMessage(for: error), privacy: .public)")
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
            // The auth user exists and we have a session to use for the
            // self-profile insert. If the insert fails (network / RLS),
            // sign the user out so they don't end up in a signed-in-but-
            // profileless limbo that bootstrap() would have to untangle.
            do {
                try await upsertSelfProfile(userId: response.user.id, fullName: fullName)
            } catch {
                try? await client.auth.signOut()
                state = .signedOut
                throw error
            }
            try? await client.auth.signOut()
            state = .signedOut
            return .pendingAdminActivation
        } else {
            return .pendingEmailConfirmation
        }
    }

    func signOut() async {
        AppLog.auth.info("signOut requested")
        try? await client.auth.signOut()
        state = .signedOut
    }

    /// Exposed so views that hit a 401 on a critical operation can drop the
    /// user back to the sign-in screen with a clear banner.
    func forceSignOut(reason: String) async {
        try? await client.auth.signOut()
        state = .error(reason)
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

    // MARK: - Auth state listener

    /// Subscribes to `auth.authStateChanges` so the UI reacts to background
    /// refreshes, external sign-outs, and MFA events without polling.
    private func startListening() {
        listenerTask?.cancel()
        listenerTask = Task { [weak self] in
            guard let self else { return }
            for await (event, session) in self.client.auth.authStateChanges {
                await self.handle(event: event, session: session)
            }
        }
    }

    private func handle(event: AuthChangeEvent, session: Session?) async {
        AppLog.auth.debug("auth event: \(String(describing: event), privacy: .public) session=\(session != nil, privacy: .public)")
        switch event {
        case .signedIn, .tokenRefreshed, .userUpdated:
            // Session refreshed successfully. Sync profile if the UI hasn't
            // loaded one yet — keeps the app usable across token rotation.
            if let session, case .signedIn = state {
                // Profile already loaded, nothing to do.
                _ = session
            } else if let session {
                try? await loadProfile(userId: session.user.id)
            }
        case .signedOut:
            state = .signedOut
        case .initialSession:
            // `bootstrap()` is the canonical cold-start path. If it's
            // already run, skip this branch to avoid a duplicate profile
            // query. If it hasn't (listener fired first for some reason),
            // seed the state so the UI isn't stuck in `.unknown`.
            guard !didBootstrap else { break }
            if let session {
                try? await loadProfile(userId: session.user.id)
            } else {
                state = .signedOut
            }
        case .passwordRecovery, .mfaChallengeVerified:
            break
        @unknown default:
            break
        }
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
