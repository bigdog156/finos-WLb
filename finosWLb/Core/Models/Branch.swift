import Foundation

struct Branch: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let tz: String
    let address: String?
    let radiusM: Int

    enum CodingKeys: String, CodingKey {
        case id, name, tz, address
        case radiusM = "radius_m"
    }
}
