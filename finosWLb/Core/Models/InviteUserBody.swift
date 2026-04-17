import Foundation

/// Request body for the `create-user` Edge Function. Kept as a dedicated
/// Codable struct so `client.functions.invoke(_:options:)` can encode it
/// directly via `FunctionInvokeOptions(body:)`.
struct InviteUserBody: Codable, Sendable {
    let email: String
    let fullName: String
    let role: String
    let branchId: UUID?
    let deptId: UUID?

    enum CodingKeys: String, CodingKey {
        case email, role
        case fullName = "full_name"
        case branchId = "branch_id"
        case deptId = "dept_id"
    }
}

/// Happy-path response from `create-user`. 201 on success.
struct InviteUserResponse: Codable, Sendable {
    let userId: UUID
    let email: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case email
    }
}

/// 409 response shape: `{ "error": "email_exists" }`.
struct InviteUserErrorResponse: Codable, Sendable {
    let error: String
}
