import Foundation

/// Request body for the `export-report` Edge Function. Backend auto-scopes
/// manager requests to their branch; `branchId`/`deptId` are advisory filters
/// for admins.
struct ExportReportBody: Encodable, Sendable {
    let reportType: String       // "daily" | "weekly" | "monthly" | "employee"
    let from: String             // "YYYY-MM-DD"
    let to: String               // "YYYY-MM-DD"
    let branchId: UUID?
    let deptId: UUID?

    enum CodingKeys: String, CodingKey {
        case reportType = "report_type"
        case from, to
        case branchId = "branch_id"
        case deptId = "dept_id"
    }
}

/// Response from the `export-report` Edge Function. `signedUrl` is a
/// 1-hour Supabase Storage URL; download it immediately and hand the local
/// file URL to a `ShareLink`.
struct ExportReportResponse: Decodable, Sendable {
    let signedUrl: String
    let filename: String
    let rowCount: Int
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case signedUrl = "signed_url"
        case filename
        case rowCount = "row_count"
        case expiresAt = "expires_at"
    }
}
