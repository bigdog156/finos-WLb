import Foundation

struct Department: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
}
