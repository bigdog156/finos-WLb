import Foundation
import SwiftUI

enum LeaveKind: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case annual, sick, unpaid, other
    var id: String { rawValue }

    var label: String {
        switch self {
        case .annual: "Nghỉ phép năm"
        case .sick:   "Nghỉ ốm"
        case .unpaid: "Nghỉ không lương"
        case .other:  "Khác"
        }
    }

    var systemImage: String {
        switch self {
        case .annual: "sun.max.fill"
        case .sick:   "cross.case.fill"
        case .unpaid: "dollarsign.circle"
        case .other:  "ellipsis.circle"
        }
    }

    var tint: Color {
        switch self {
        case .annual: .blue
        case .sick:   .red
        case .unpaid: .purple
        case .other:  .gray
        }
    }
}

enum LeaveStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case pending, approved, rejected, cancelled

    var label: String {
        switch self {
        case .pending:   "Đang chờ"
        case .approved:  "Đã duyệt"
        case .rejected:  "Đã từ chối"
        case .cancelled: "Đã hủy"
        }
    }

    var systemImage: String {
        switch self {
        case .pending:   "hourglass"
        case .approved:  "checkmark.seal.fill"
        case .rejected:  "xmark.seal.fill"
        case .cancelled: "slash.circle"
        }
    }

    var tint: Color {
        switch self {
        case .pending:   .orange
        case .approved:  .green
        case .rejected:  .red
        case .cancelled: .secondary
        }
    }
}

struct LeaveRequest: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let employeeId: UUID
    let branchId: UUID?
    let kind: LeaveKind
    let startDate: String   // yyyy-MM-dd
    let endDate: String     // yyyy-MM-dd
    let reason: String?
    let status: LeaveStatus
    let reviewedBy: UUID?
    let reviewedAt: String?
    let reviewNote: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, kind, reason, status
        case employeeId = "employee_id"
        case branchId = "branch_id"
        case startDate = "start_date"
        case endDate = "end_date"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case reviewNote = "review_note"
        case createdAt = "created_at"
    }

    static let selectColumns = "id, employee_id, branch_id, kind, start_date, end_date, reason, status, reviewed_by, reviewed_at, review_note, created_at"

    /// Total whole days inclusive; returns at least 1.
    var durationDays: Int {
        guard let start = Self.dateFormatter.date(from: startDate),
              let end = Self.dateFormatter.date(from: endDate) else { return 1 }
        let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
        return max(1, days + 1)
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static func format(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
}

struct LeaveRequestInsert: Encodable, Sendable {
    let employeeId: UUID
    let kind: String
    let startDate: String
    let endDate: String
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case employeeId = "employee_id"
        case kind
        case startDate = "start_date"
        case endDate = "end_date"
        case reason
    }
}

struct LeaveRequestCancelPayload: Encodable, Sendable {
    let status = LeaveStatus.cancelled.rawValue
}

struct ReviewLeaveBody: Encodable, Sendable {
    let requestId: UUID
    let newStatus: String
    let note: String?

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case newStatus = "new_status"
        case note
    }
}

struct ReviewLeaveResponse: Decodable, Sendable {
    let leave: LeaveRequest
}

struct EditEventBody: Encodable, Sendable {
    let eventId: UUID
    let newStatus: String?
    let newServerTs: String?
    let reason: String

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case newStatus = "new_status"
        case newServerTs = "new_server_ts"
        case reason
    }
}

struct EditEventResponse: Decodable, Sendable {
    let event: AttendanceEvent
}
