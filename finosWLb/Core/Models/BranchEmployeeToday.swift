import Foundation

/// Row from the `branch_employee_today` view. RLS scopes rows to the manager's
/// branch (admins see all). Derived states are computed client-side from
/// `firstIn` / `lastOut` / `flaggedCount` / `hasLate`.
struct BranchEmployeeToday: Codable, Identifiable, Hashable, Sendable {
    let employeeId: UUID
    let fullName: String
    let branchId: UUID
    let deptId: UUID?
    let firstIn: String?     // ISO8601 timestamptz
    let lastOut: String?     // ISO8601 timestamptz
    let flaggedCount: Int
    let hasLate: Bool

    var id: UUID { employeeId }

    enum CodingKeys: String, CodingKey {
        case employeeId = "employee_id"
        case fullName = "full_name"
        case branchId = "branch_id"
        case deptId = "dept_id"
        case firstIn = "first_in"
        case lastOut = "last_out"
        case flaggedCount = "flagged_count"
        case hasLate = "has_late"
    }

    /// Display-level state. Ordering in `ManagerBranchView.sections` is display
    /// precedence: Flagged → Late → Absent → Present → Out.
    enum DerivedState: String, Hashable, CaseIterable {
        case flagged
        case late
        case absent
        case present
        case out

        var label: String {
            switch self {
            case .flagged: "Flagged"
            case .late:    "Late"
            case .absent:  "Absent"
            case .present: "Present"
            case .out:     "Out"
            }
        }
    }

    var derivedState: DerivedState {
        if flaggedCount > 0 { return .flagged }
        if hasLate { return .late }
        if firstIn == nil && lastOut == nil { return .absent }
        if firstIn != nil && lastOut == nil { return .present }
        return .out
    }
}
