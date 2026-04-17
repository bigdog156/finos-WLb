import Foundation

/// Mirror of a row in the `branch_wifi` table. One row per approved BSSID for a
/// given branch — the check-in function uses these to boost confidence that the
/// device is physically at the branch.
struct BranchWifi: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let branchId: UUID
    let bssid: String
    let ssid: String?

    enum CodingKeys: String, CodingKey {
        case id, bssid, ssid
        case branchId = "branch_id"
    }
}

/// Write-side payload for inserting a new `branch_wifi` row. The DB populates
/// `id` for us, so it's omitted here.
struct NewBranchWifi: Codable, Sendable {
    let branchId: UUID
    let bssid: String
    let ssid: String?

    enum CodingKeys: String, CodingKey {
        case bssid, ssid
        case branchId = "branch_id"
    }
}
