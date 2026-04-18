import Foundation

enum UserRole: String, Codable, Hashable, Sendable, CaseIterable {
    case admin
    case manager
    case employee

    /// User-facing Vietnamese label for the role.
    var label: String {
        switch self {
        case .admin:    "Quản trị viên"
        case .manager:  "Quản lý"
        case .employee: "Nhân viên"
        }
    }
}
