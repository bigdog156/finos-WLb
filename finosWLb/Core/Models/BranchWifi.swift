import Foundation

/// Mirror of a row in the `branch_wifi` table. One row per approved BSSID for a
/// given branch — the check-in function uses these to boost confidence that the
/// device is physically at the branch.
///
/// The table has a composite PK (branch_id, bssid) — there is no surrogate `id`
/// column. `Identifiable` is satisfied by a synthetic `id` computed from the two
/// PK columns so SwiftUI `ForEach` works correctly.
struct BranchWifi: Codable, Identifiable, Hashable, Sendable {
    let branchId: UUID
    let bssid: String
    let ssid: String?

    /// Synthetic `Identifiable` key — stable across re-fetches for the same row.
    var id: String { "\(branchId.uuidString):\(bssid)" }

    enum CodingKeys: String, CodingKey {
        case bssid, ssid
        case branchId = "branch_id"
    }
}

/// Write-side payload for inserting a new `branch_wifi` row.
struct NewBranchWifi: Codable, Sendable {
    let branchId: UUID
    let bssid: String
    let ssid: String?

    enum CodingKeys: String, CodingKey {
        case bssid, ssid
        case branchId = "branch_id"
    }
}
