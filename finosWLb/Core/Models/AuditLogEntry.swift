import Foundation
import Supabase

/// Row projection of the `audit_log` table. RLS guarantees SELECT is
/// admin-only; this DTO is consumed by `AuditLogView`.
///
/// `payload` is kept as the SDK's `AnyJSON` so we can pretty-print it
/// without modelling every action-specific shape. `ts` stays as an ISO8601
/// string and is parsed at render time — matches the existing convention
/// used by `FlaggedEvent` and report DTOs in this project.
struct AuditLogEntry: Codable, Identifiable, Hashable, Sendable {
    let id: Int64
    let actorId: UUID?
    let action: String
    let targetTable: String
    let targetId: String?
    let payload: AnyJSON?
    let ts: String

    enum CodingKeys: String, CodingKey {
        case id, action, ts, payload
        case actorId = "actor_id"
        case targetTable = "target_table"
        case targetId = "target_id"
    }

    static let selectColumns =
        "id, actor_id, action, target_table, target_id, payload, ts"
}
