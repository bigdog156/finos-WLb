import Foundation

/// Row returned by the `dashboard_today` RPC — today's top-of-funnel KPIs
/// across every active employee (RLS-scoped: admins see all, managers see
/// their branch).
struct DashboardToday: Codable, Hashable, Sendable {
    let totalEmployees: Int
    let present: Int
    let absent: Int
    let late: Int
    let flagged: Int

    enum CodingKeys: String, CodingKey {
        case totalEmployees = "total_employees"
        case present, absent, late, flagged
    }
}
