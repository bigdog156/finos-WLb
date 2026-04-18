import Foundation
import OSLog
import Supabase

@MainActor
final class SupabaseManager {
    static let shared = SupabaseManager()
    let client: SupabaseClient

    private init() {
        guard let url = URL(string: Secrets.supabaseURL) else {
            fatalError("Invalid Supabase URL in Secrets.swift")
        }
        // Opt into the next-major auth behaviour — the locally stored session
        // is emitted immediately as the initial session, silencing the
        // deprecation warning. Do NOT pass `accessToken:` here: that closure
        // disables the SDK's built-in auth module (`client.auth` becomes
        // inaccessible), which breaks sign-in/sign-out. The SDK already
        // propagates the user's JWT to Functions and PostgREST on every auth
        // state change via `handleTokenChanged`.
        let authOptions = SupabaseClientOptions.AuthOptions(
            emitLocalSessionAsInitialSession: true
        )
        self.client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: Secrets.supabaseAnonKey,
            options: SupabaseClientOptions(auth: authOptions)
        )
    }
}

// MARK: - Authenticated function invocation

/// Errors thrown by the authenticated Edge Function helper.
enum InvokeError: Error, LocalizedError {
    /// User has no valid session — caller should prompt re-login.
    case noSession
    /// Edge Function returned a non-2xx status. `detail` is the EF's
    /// `{error, detail}` payload if decodable, otherwise the raw body.
    case edgeFunctionError(statusCode: Int, code: String?, detail: String?)

    var errorDescription: String? {
        switch self {
        case .noSession:
            return "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại."
        case .edgeFunctionError(_, _, let detail):
            return detail ?? "Máy chủ trả về lỗi."
        }
    }
}

extension SupabaseClient {
    /// Invokes an Edge Function with the current user's access token pinned
    /// into the `Authorization` header.
    ///
    /// - `auth.session` already auto-refreshes a near-expiry access token
    ///   before returning it — we don't need a manual retry on 401.
    /// - Setting `Authorization` explicitly in `options.headers` overrides
    ///   the SDK's default header (which otherwise falls back to the project
    ///   anon key and trips the function's `extractSub` check).
    /// - A 401 from the EF is surfaced verbatim (with the server's `detail`
    ///   string) so callers can show actionable diagnostic text instead of
    ///   a canned "session expired" message that might hide the real cause.
    func invokeFunction<Response: Decodable>(
        _ name: String,
        body: some Encodable
    ) async throws -> Response {
        let start = Date()
        let accessToken: String
        do {
            accessToken = try await auth.session.accessToken
        } catch {
            AppLog.network.error("EF \(name, privacy: .public) aborted — no session: \(logMessage(for: error), privacy: .public)")
            throw InvokeError.noSession
        }

        // Log only the token prefix/role so Console has signal without
        // leaking the full JWT. The middle payload segment carries `role`.
        AppLog.network.debug("EF \(name, privacy: .public) invoking with token prefix \(Self.tokenPrefix(accessToken), privacy: .public)")

        do {
            let response: Response = try await functions.invoke(
                name,
                options: FunctionInvokeOptions(
                    headers: ["Authorization": "Bearer \(accessToken)"],
                    body: body
                )
            )
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            AppLog.network.info("EF \(name, privacy: .public) succeeded in \(ms, privacy: .public) ms")
            return response
        } catch let FunctionsError.httpError(status, data) {
            let code = Self.decodeEFErrorCode(from: data)
            let detail = Self.decodeEFErrorDetail(from: data)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            AppLog.network.error("EF \(name, privacy: .public) failed \(status, privacy: .public) in \(ms, privacy: .public) ms — code=\(code ?? "?", privacy: .public) detail=\(detail ?? "?", privacy: .public)")
            throw InvokeError.edgeFunctionError(
                statusCode: status,
                code: code,
                detail: detail
            )
        } catch {
            AppLog.network.error("EF \(name, privacy: .public) threw \(type(of: error), privacy: .public): \(logMessage(for: error), privacy: .public)")
            throw error
        }
    }

    /// Returns the first 8 chars of the payload section plus the role, e.g.
    /// `payload=eyJpc3Mi… role=authenticated`, so logs show at a glance
    /// whether we're sending the anon key or a real user token — without
    /// ever emitting the signature.
    private static func tokenPrefix(_ jwt: String) -> String {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return "invalid(parts=\(parts.count))" }
        let payloadPrefix = String(parts[1].prefix(10))
        var role = "?"
        var payload = String(parts[1])
        payload = payload.replacingOccurrences(of: "-", with: "+")
                         .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - payload.count % 4) % 4
        payload += String(repeating: "=", count: padding)
        if let data = Data(base64Encoded: payload),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let r = obj["role"] as? String {
            role = r
        }
        return "payload=\(payloadPrefix)… role=\(role)"
    }

    private static func decodeEFErrorCode(from data: Data) -> String? {
        struct Err: Decodable { let error: String? }
        return (try? JSONDecoder().decode(Err.self, from: data))?.error
    }

    private static func decodeEFErrorDetail(from data: Data) -> String? {
        struct Err: Decodable { let error: String?; let detail: String? }
        let decoded = try? JSONDecoder().decode(Err.self, from: data)
        if let detail = decoded?.detail, !detail.isEmpty {
            if let code = decoded?.error, !code.isEmpty {
                return "\(code): \(detail)"
            }
            return detail
        }
        return decoded?.error
    }
}
