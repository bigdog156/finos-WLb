import Foundation

/// Projection of `attendance_events` used by the manager Review Queue.
/// Includes columns the employee-facing `AttendanceEvent` DTO doesn't need
/// (employee_id, risk_score, bssid) so cards can render risk + evidence chips.
struct FlaggedEvent: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let employeeId: UUID
    let type: AttendanceEventType
    let serverTs: String
    let status: AttendanceEventStatus
    let flaggedReason: String?
    let riskScore: Int
    let accuracyM: Double?
    let bssid: String?
    /// Distance from the branch's registered coordinate, in meters. Populated
    /// by the check-in EF v3 for new events; NULL for historical rows.
    let distanceM: Double?

    enum CodingKeys: String, CodingKey {
        case id, type, status, bssid
        case employeeId = "employee_id"
        case serverTs = "server_ts"
        case flaggedReason = "flagged_reason"
        case riskScore = "risk_score"
        case accuracyM = "accuracy_m"
        case distanceM = "distance_m"
    }

    static let selectColumns =
        "id, employee_id, type, server_ts, status, flagged_reason, risk_score, accuracy_m, bssid, distance_m"
}

/// Body sent to the `review-event` Edge Function.
struct ReviewEventBody: Codable, Sendable {
    let eventId: UUID
    let newStatus: String   // on_time | late | rejected
    let note: String?

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case newStatus = "new_status"
        case note
    }
}

struct ReviewEventResponse: Codable, Sendable {
    let event: FlaggedEvent
}
