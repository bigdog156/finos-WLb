import Foundation

enum AttendanceEventType: String, Codable, Hashable, Sendable, CaseIterable {
    case checkIn = "check_in"
    case checkOut = "check_out"

    var label: String {
        switch self {
        case .checkIn:  "Check In"
        case .checkOut: "Check Out"
        }
    }
}

enum AttendanceEventStatus: String, Codable, Hashable, Sendable {
    case onTime   = "on_time"
    case late
    case absent
    case flagged
    case rejected

    var label: String {
        switch self {
        case .onTime:   "On time"
        case .late:     "Late"
        case .absent:   "Absent"
        case .flagged:  "Flagged"
        case .rejected: "Rejected"
        }
    }
}

struct AttendanceEvent: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let type: AttendanceEventType
    let serverTs: String
    let clientTs: String?
    let status: AttendanceEventStatus
    let flaggedReason: String?
    let branchId: UUID?
    let accuracyM: Double?

    enum CodingKeys: String, CodingKey {
        case id, type, status
        case serverTs = "server_ts"
        case clientTs = "client_ts"
        case flaggedReason = "flagged_reason"
        case branchId = "branch_id"
        case accuracyM = "accuracy_m"
    }
}

struct CheckInResponse: Codable, Sendable {
    let event: AttendanceEvent
    let distanceM: Int
    let radiusM: Int

    enum CodingKeys: String, CodingKey {
        case event
        case distanceM = "distance_m"
        case radiusM = "radius_m"
    }
}

struct CheckInBody: Codable, Sendable {
    let type: String
    let clientTs: String
    let lat: Double
    let lng: Double
    let accuracyM: Double
    let bssid: String?
    let ssid: String?

    enum CodingKeys: String, CodingKey {
        case type, lat, lng, bssid, ssid
        case clientTs = "client_ts"
        case accuracyM = "accuracy_m"
    }
}

/// Shape of the `check-in` Edge Function's non-422 error responses, e.g.
/// `{ "error": "no_branch_assigned" }` or
/// `{ "error": "bad_request", "detail": "invalid accuracy_m" }`.
struct CheckInErrorPayload: Decodable, Sendable {
    let error: String
    let detail: String?
}
