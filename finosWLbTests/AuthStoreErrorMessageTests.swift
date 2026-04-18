import Foundation
import Testing
@testable import finosWLb

/// Pure-function tests for `AuthStore.friendlyAuthMessage(_:)`. Verifies the
/// Vietnamese copy we show in the sign-in/up error banner for each Supabase
/// auth failure pattern we match against.
@Suite("AuthStore.friendlyAuthMessage")
struct AuthStoreErrorMessageTests {

    // MARK: - Credentials

    @Test("Invalid login credentials")
    func invalidLogin() {
        let msg = AuthStore.friendlyAuthMessage(MockError("Invalid login credentials"))
        #expect(msg == "Email hoặc mật khẩu không đúng.")
    }

    @Test("Invalid credentials alternate phrasing")
    func invalidCredentials() {
        let msg = AuthStore.friendlyAuthMessage(MockError("invalid_credentials"))
        #expect(msg == "Email hoặc mật khẩu không đúng.")
    }

    @Test("Invalid grant maps to credentials error")
    func invalidGrant() {
        let msg = AuthStore.friendlyAuthMessage(MockError("invalid grant"))
        #expect(msg == "Email hoặc mật khẩu không đúng.")
    }

    // MARK: - Email confirmation

    @Test("Email not confirmed")
    func emailNotConfirmed() {
        let msg = AuthStore.friendlyAuthMessage(MockError("Email not confirmed"))
        #expect(msg == "Vui lòng xác nhận email, sau đó thử lại.")
    }

    // MARK: - Signup collisions

    @Test("User already registered")
    func userAlreadyRegistered() {
        let msg = AuthStore.friendlyAuthMessage(MockError("User already registered"))
        #expect(msg == "Email này đã được đăng ký.")
    }

    @Test("Weak password")
    func weakPassword() {
        let msg = AuthStore.friendlyAuthMessage(MockError("Password should be at least 6 characters"))
        #expect(msg == "Mật khẩu quá yếu. Vui lòng dùng ít nhất 6 ký tự.")
    }

    // MARK: - Transport

    @Test("Rate limit")
    func rateLimit() {
        let msg = AuthStore.friendlyAuthMessage(MockError("rate limit exceeded"))
        #expect(msg == "Quá nhiều lần thử. Vui lòng chờ một chút rồi thử lại.")
    }

    @Test("Offline / network")
    func network() {
        let msg = AuthStore.friendlyAuthMessage(MockError("The Internet connection appears to be offline."))
        #expect(msg == "Bạn đang ngoại tuyến. Kiểm tra kết nối và thử lại.")
    }

    @Test("Timeout")
    func timeout() {
        let msg = AuthStore.friendlyAuthMessage(MockError("The request timed out"))
        #expect(msg == "Yêu cầu đã hết thời gian. Vui lòng thử lại.")
    }

    @Test("403 unauthorized")
    func unauthorized() {
        let msg = AuthStore.friendlyAuthMessage(MockError("403 Forbidden: unauthorized"))
        #expect(msg == "Không thể xác minh thông tin đăng nhập. Vui lòng thử lại.")
    }

    @Test("500 server")
    func serverError() {
        let msg = AuthStore.friendlyAuthMessage(MockError("500 Internal Server Error"))
        #expect(msg == "Máy chủ đang gặp sự cố. Vui lòng thử lại sau giây lát.")
    }

    @Test("Unknown error falls back to generic")
    func generic() {
        let msg = AuthStore.friendlyAuthMessage(MockError("kaboom"))
        #expect(msg == "Đã có lỗi xảy ra. Vui lòng thử lại.")
    }
}

/// Lightweight `Error` that surfaces a chosen `localizedDescription` so we can
/// trigger each branch of `friendlyAuthMessage` without touching Supabase.
private struct MockError: LocalizedError {
    let description: String
    init(_ description: String) { self.description = description }
    var errorDescription: String? { description }
}
