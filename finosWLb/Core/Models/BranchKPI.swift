import Foundation

/// Row returned by the `dashboard_today_by_branch` RPC — one record per branch
/// visible to the caller. The admin dashboard's breakdown table is driven by
/// these rows.
struct BranchKPI: Codable, Identifiable, Hashable, Sendable {
    let branchId: UUID
    let branchName: String
    let total: Int
    let present: Int
    let absent: Int
    let late: Int
    let flagged: Int

    var id: UUID { branchId }

    enum CodingKeys: String, CodingKey {
        case branchId = "branch_id"
        case branchName = "branch_name"
        case total, present, absent, late, flagged
    }
}
