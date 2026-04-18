import Foundation
import SwiftUI

/// Employee-submitted request to add or correct an attendance event.
/// Reuses the `leave_status` enum for lifecycle (`pending` → `approved` /
/// `rejected` / `cancelled`).
struct AttendanceCorrection: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let employeeId: UUID
    let branchId: UUID?
    /// Date the correction applies to (`yyyy-MM-dd`).
    let targetDate: String
    /// Which event the employee forgot — `check_in` or `check_out`.
    let targetType: AttendanceEventType
    /// Full timestamp the employee says they were actually at the branch.
    let requestedTs: String
    let reason: String
    let status: LeaveStatus
    let reviewedBy: UUID?
    let reviewedAt: String?
    let reviewNote: String?
    let resultingEventId: UUID?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, reason, status
        case employeeId = "employee_id"
        case branchId = "branch_id"
        case targetDate = "target_date"
        case targetType = "target_type"
        case requestedTs = "requested_ts"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case reviewNote = "review_note"
        case resultingEventId = "resulting_event_id"
        case createdAt = "created_at"
    }

    static let selectColumns = "id, employee_id, branch_id, target_date, target_type, requested_ts, reason, status, reviewed_by, reviewed_at, review_note, resulting_event_id, created_at"
}

struct AttendanceCorrectionInsert: Encodable, Sendable {
    let employeeId: UUID
    let targetDate: String
    let targetType: String
    let requestedTs: String
    let reason: String

    enum CodingKeys: String, CodingKey {
        case employeeId = "employee_id"
        case targetDate = "target_date"
        case targetType = "target_type"
        case requestedTs = "requested_ts"
        case reason
    }
}

struct AttendanceCorrectionCancelPayload: Encodable, Sendable {
    let status = LeaveStatus.cancelled.rawValue
}

struct ReviewCorrectionBody: Encodable, Sendable {
    let requestId: UUID
    let newStatus: String
    let note: String?

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case newStatus = "new_status"
        case note
    }
}

struct ReviewCorrectionResponse: Decodable, Sendable {
    let correction: AttendanceCorrection
}

/// Params for the `review_correction_rpc` Postgres function.
struct ReviewCorrectionRPCParams: Encodable, Sendable {
    let p_request_id: UUID
    let p_new_status: String
    let p_note: String?
}
