import Foundation

struct Profile: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let fullName: String
    let role: UserRole
    let branchId: UUID?
    let deptId: UUID?
    let active: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case role
        case branchId = "branch_id"
        case deptId = "dept_id"
        case active
    }
}
