import Foundation

/// Single-row response from `admin_dashboard_summary()` — the wide
/// snapshot the Admin Home header renders in one shot.
struct AdminDashboardSummary: Codable, Hashable, Sendable {
    let totalBranches: Int
    let totalActiveEmployees: Int
    let totalEmployees: Int
    let onTimeToday: Int
    let lateToday: Int
    let flaggedToday: Int
    let absentToday: Int
    let presentToday: Int
    let checkInsToday: Int
    let checkOutsToday: Int
    let pendingFlags: Int
    let pendingLeaves: Int
    let pendingCorrections: Int
    let onTimeRate: Double   // 0.0 … 1.0

    enum CodingKeys: String, CodingKey {
        case totalBranches = "total_branches"
        case totalActiveEmployees = "total_active_employees"
        case totalEmployees = "total_employees"
        case onTimeToday = "on_time_today"
        case lateToday = "late_today"
        case flaggedToday = "flagged_today"
        case absentToday = "absent_today"
        case presentToday = "present_today"
        case checkInsToday = "check_ins_today"
        case checkOutsToday = "check_outs_today"
        case pendingFlags = "pending_flags"
        case pendingLeaves = "pending_leaves"
        case pendingCorrections = "pending_corrections"
        case onTimeRate = "on_time_rate"
    }

    /// PostgREST emits `numeric` as a JSON string. Accept both string and
    /// number forms so we don't blow up if the server ever changes shape.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.totalBranches = try c.decode(Int.self, forKey: .totalBranches)
        self.totalActiveEmployees = try c.decode(Int.self, forKey: .totalActiveEmployees)
        self.totalEmployees = try c.decode(Int.self, forKey: .totalEmployees)
        self.onTimeToday = try c.decode(Int.self, forKey: .onTimeToday)
        self.lateToday = try c.decode(Int.self, forKey: .lateToday)
        self.flaggedToday = try c.decode(Int.self, forKey: .flaggedToday)
        self.absentToday = try c.decode(Int.self, forKey: .absentToday)
        self.presentToday = try c.decode(Int.self, forKey: .presentToday)
        self.checkInsToday = try c.decode(Int.self, forKey: .checkInsToday)
        self.checkOutsToday = try c.decode(Int.self, forKey: .checkOutsToday)
        self.pendingFlags = try c.decode(Int.self, forKey: .pendingFlags)
        self.pendingLeaves = try c.decode(Int.self, forKey: .pendingLeaves)
        self.pendingCorrections = try c.decode(Int.self, forKey: .pendingCorrections)
        if let d = try? c.decode(Double.self, forKey: .onTimeRate) {
            self.onTimeRate = d
        } else {
            let s = try c.decode(String.self, forKey: .onTimeRate)
            self.onTimeRate = Double(s) ?? 0
        }
    }
}

/// Row from `admin_recent_events` — a single check-in/out with joined
/// employee + branch names for the live activity feed.
struct AdminRecentEvent: Codable, Identifiable, Hashable, Sendable {
    let eventId: UUID
    let employeeId: UUID
    let employeeName: String
    let branchId: UUID
    let branchName: String
    let eventType: AttendanceEventType
    let status: AttendanceEventStatus
    let serverTs: String
    let flaggedReason: String?

    var id: UUID { eventId }

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case employeeId = "employee_id"
        case employeeName = "employee_name"
        case branchId = "branch_id"
        case branchName = "branch_name"
        case eventType = "event_type"
        case status
        case serverTs = "server_ts"
        case flaggedReason = "flagged_reason"
    }
}
