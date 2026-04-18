import Foundation

/// Machine-readable error identifiers returned by the `check-in` Edge Function
/// in the JSON body of non-200 / non-422 responses (`{ "error": "<code>", "detail"?: "..." }`).
///
/// Keep in sync with the Edge Function source. Each case maps to a single HTTP
/// status code per the EF contract, but the enum is purely about the `error`
/// string — callers should combine with the HTTP status when they need both.
enum CheckInServerError: String, Sendable {

    // MARK: - Client-side configuration (400)
    /// `profiles.branch_id` is null — admin must assign a branch.
    case noBranchAssigned   = "no_branch_assigned"
    /// Request body failed schema validation in the EF (see `detail`).
    case badRequest         = "bad_request"

    // MARK: - Auth (401 / 403)
    /// Missing / invalid / expired Authorization header.
    case unauthorized       = "unauthorized"
    /// `profiles.active = false` — admin must activate the user.
    case profileInactive    = "profile_inactive"

    // MARK: - Not found (404)
    /// No row in `profiles` matches `auth.uid()`.
    case profileNotFound    = "profile_not_found"
    /// The assigned branch row was deleted or is otherwise unreachable.
    case branchNotFound     = "branch_not_found"

    // MARK: - Transport (405)
    case methodNotAllowed   = "method_not_allowed"

    // MARK: - Internal (500)
    case distanceCalcFailed = "distance_calc_failed"
    case travelCheckFailed  = "travel_check_failed"
    case insertFailed       = "insert_failed"

    /// Human-readable, user-facing message. Keep short and actionable — these
    /// land in an inline error banner, not a log.
    var userMessage: String {
        switch self {
        case .noBranchAssigned:
            "Bạn chưa được gán vào chi nhánh nào. Vui lòng liên hệ quản trị viên để được gán."
        case .badRequest:
            "Yêu cầu chấm công không hợp lệ. Vui lòng thử lại."
        case .unauthorized:
            "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại."
        case .profileInactive:
            "Tài khoản của bạn chưa được kích hoạt. Vui lòng liên hệ quản trị viên để kích hoạt."
        case .profileNotFound:
            "Không tìm thấy hồ sơ. Vui lòng đăng xuất rồi đăng nhập lại."
        case .branchNotFound:
            "Không tìm thấy chi nhánh đã gán."
        case .methodNotAllowed:
            "Máy chủ từ chối yêu cầu. Vui lòng thử lại sau."
        case .distanceCalcFailed:
            "Không thể tính khoảng cách từ chi nhánh. Vui lòng thử lại."
        case .travelCheckFailed:
            "Không thể xác minh lịch sử vị trí. Vui lòng thử lại."
        case .insertFailed:
            "Không thể ghi nhận chấm công. Vui lòng thử lại."
        }
    }

    /// True when a retry cannot succeed until an admin or user takes action
    /// outside the app (assigning a branch, activating the account, etc.).
    /// The offline queue uses this to drop entries instead of replaying them.
    var isUserActionable: Bool {
        switch self {
        case .noBranchAssigned, .profileInactive, .profileNotFound,
             .branchNotFound, .unauthorized, .badRequest, .methodNotAllowed:
            true
        case .distanceCalcFailed, .travelCheckFailed, .insertFailed:
            false
        }
    }
}
