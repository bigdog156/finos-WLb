import Foundation
import SwiftData

@Model
final class PendingCheckIn {
    @Attribute(.unique) var id: UUID
    var type: String
    var clientTs: Date
    var lat: Double
    var lng: Double
    var accuracyM: Double
    var bssid: String?
    var ssid: String?
    var createdAt: Date
    var attemptCount: Int
    var lastError: String?

    init(
        id: UUID = UUID(),
        type: String,
        clientTs: Date,
        lat: Double,
        lng: Double,
        accuracyM: Double,
        bssid: String? = nil,
        ssid: String? = nil
    ) {
        self.id = id
        self.type = type
        self.clientTs = clientTs
        self.lat = lat
        self.lng = lng
        self.accuracyM = accuracyM
        self.bssid = bssid
        self.ssid = ssid
        self.createdAt = Date()
        self.attemptCount = 0
        self.lastError = nil
    }
}
