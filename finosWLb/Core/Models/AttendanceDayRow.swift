import Foundation

/// Row from the `attendance_days` table. This is the aggregated per-day record
/// populated by a server-side trigger in Phase 6; reports read from it rather
/// than re-aggregating raw events on the client. RLS scopes by branch/role.
///
/// `date` is a calendar date (`YYYY-MM-DD`, no tz); `firstIn`/`lastOut` are
/// timestamptz ISO strings. Reuse the existing `ISO8601DateFormatter.supabase`
/// helper for the timestamptz columns.
struct AttendanceDayRow: Codable, Identifiable, Hashable, Sendable {
    let employeeId: UUID
    let date: String
    let branchId: UUID?
    let firstIn: String?
    let lastOut: String?
    let workedMin: Int?
    let overtimeMin: Int?
    let status: AttendanceEventStatus

    /// Composite identity: `attendance_days` is a (employee_id, date) tuple.
    var id: String { "\(employeeId.uuidString)-\(date)" }

    enum CodingKeys: String, CodingKey {
        case employeeId = "employee_id"
        case date
        case branchId = "branch_id"
        case firstIn = "first_in"
        case lastOut = "last_out"
        case workedMin = "worked_min"
        case overtimeMin = "overtime_min"
        case status
    }

    var parsedDate: Date? {
        DailySeriesRow.dateFormatter.date(from: date)
    }
}
