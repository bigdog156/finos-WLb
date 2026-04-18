import Foundation
import LocalAuthentication
import SwiftUI

/// Orchestrates Face ID / Touch ID / device passcode to gate the app. The
/// `AppStorage` preference lives outside this type so SwiftUI views can bind
/// to it directly; this observable just owns the "is currently unlocked"
/// transient state and the authenticate entry point.
@Observable
@MainActor
final class BiometricLock {
    enum Availability: Equatable {
        case faceID, touchID, opticID, passcodeOnly, unavailable(String)

        var label: String {
            switch self {
            case .faceID:        "Face ID"
            case .touchID:       "Touch ID"
            case .opticID:       "Optic ID"
            case .passcodeOnly:  "Mã bảo vệ"
            case .unavailable:   "Không khả dụng"
            }
        }

        var systemImage: String {
            switch self {
            case .faceID:       "faceid"
            case .touchID:      "touchid"
            case .opticID:      "opticid"
            case .passcodeOnly: "lock.fill"
            case .unavailable:  "lock.slash"
            }
        }
    }

    private(set) var isUnlocked: Bool = false
    private(set) var lastError: String?

    var availability: Availability {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .unavailable(error?.localizedDescription ?? "Thiết bị chưa cài đặt mã bảo vệ.")
        }
        switch context.biometryType {
        case .faceID:   return .faceID
        case .touchID:  return .touchID
        case .opticID:  return .opticID
        case .none:     return .passcodeOnly
        @unknown default: return .passcodeOnly
        }
    }

    /// Prompts biometrics (falls back to device passcode). Mutates `isUnlocked`
    /// on success; captures a user-readable reason on failure.
    func authenticate(reason: String = "Xác thực để mở ứng dụng") async {
        let context = LAContext()
        context.localizedFallbackTitle = "Dùng mã bảo vệ"
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            lastError = policyError?.localizedDescription ?? "Thiết bị chưa cài đặt mã bảo vệ."
            return
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            isUnlocked = ok
            lastError = ok ? nil : "Xác thực không thành công."
        } catch let error as LAError where error.code == .userCancel {
            lastError = nil
        } catch let error as LAError where error.code == .appCancel || error.code == .systemCancel {
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func lock() {
        isUnlocked = false
    }
}
