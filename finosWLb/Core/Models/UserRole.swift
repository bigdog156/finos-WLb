import Foundation

enum UserRole: String, Codable, Hashable, Sendable, CaseIterable {
    case admin
    case manager
    case employee
}
