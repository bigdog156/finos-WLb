import Foundation

enum AttendanceEventType: String, Codable, Hashable, Sendable, CaseIterable {
    case checkIn = "check_in"
    case checkOut = "check_out"

    var label: String {
        switch self {
        case .checkIn:  "Chấm công vào"
        case .checkOut: "Chấm công ra"
        }
    }
}

enum AttendanceEventStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case onTime   = "on_time"
    case late
    case absent
    case flagged
    case rejected

    var label: String {
        switch self {
        case .onTime:   "Đúng giờ"
        case .late:     "Trễ"
        case .absent:   "Vắng"
        case .flagged:  "Gắn cờ"
        case .rejected: "Bị từ chối"
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
    let note: String?

    enum CodingKeys: String, CodingKey {
        case id, type, status, note
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
    let note: String?

    enum CodingKeys: String, CodingKey {
        case type, lat, lng, bssid, ssid, note
        case clientTs = "client_ts"
        case accuracyM = "accuracy_m"
    }
}

/// Params for the `check_in_rpc` Postgres function. Property names match
/// the `p_*` argument names because PostgREST's RPC call encodes the
/// Encodable struct as the JSON body and looks up args by name.
struct CheckInRPCParams: Encodable, Sendable {
    let p_type: String
    let p_client_ts: String
    let p_lat: Double
    let p_lng: Double
    let p_accuracy_m: Double
    let p_bssid: String?
    let p_ssid: String?
    let p_note: String?
}

/// Params for the `review_event_rpc` Postgres function.
struct ReviewEventRPCParams: Encodable, Sendable {
    let p_event_id: UUID
    let p_new_status: String
    let p_note: String?
}

/// Wrapper response for RPCs that return `{ "event": {...} }`.
struct EventRPCResponse: Decodable, Sendable {
    let event: AttendanceEvent
}

/// Shape returned by `check_in_rpc`. `rejected` mirrors the old 422
/// semantics — the row still gets written but with status=rejected so the
/// audit trail stays complete.
struct CheckInRPCResponse: Codable, Sendable {
    let event: AttendanceEvent
    let distanceM: Int
    let radiusM: Int
    let rejected: Bool

    enum CodingKeys: String, CodingKey {
        case event, rejected
        case distanceM = "distance_m"
        case radiusM = "radius_m"
    }
}

/// Shape of the `check-in` Edge Function's non-422 error responses, e.g.
/// `{ "error": "no_branch_assigned" }` or
/// `{ "error": "bad_request", "detail": "invalid accuracy_m" }`.
struct CheckInErrorPayload: Decodable, Sendable {
    let error: String
    let detail: String?
}
