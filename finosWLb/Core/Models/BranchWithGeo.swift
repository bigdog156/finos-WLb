import Foundation

/// DTO matching the `branches_with_geo` view. Unlike the bare `Branch` DTO,
/// this one carries the decoded lat/lng and the default_shift_id so admin
/// editors can render the map and shift dropdown without an extra round-trip.
struct BranchWithGeo: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let tz: String
    let address: String?
    let radiusM: Int
    let lat: Double
    let lng: Double
    let defaultShiftId: UUID?

    enum CodingKeys: String, CodingKey {
        case id, name, tz, address, lat, lng
        case radiusM = "radius_m"
        case defaultShiftId = "default_shift_id"
    }
}

extension Branch {
    /// Adapter: BranchWifiView takes a plain Branch — this lets the editor
    /// push into it without duplicating the Wi-Fi CRUD screen.
    init(_ geo: BranchWithGeo) {
        self.init(
            id: geo.id,
            name: geo.name,
            tz: geo.tz,
            address: geo.address,
            radiusM: geo.radiusM
        )
    }
}
