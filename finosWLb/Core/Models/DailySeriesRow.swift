import Foundation

/// Row returned by the `daily_series` RPC. Server emits `date` as a plain
/// `"YYYY-MM-DD"` string (not timestamptz); view layer parses with a
/// UTC-anchored `DateFormatter` so ticks align with calendar days.
struct DailySeriesRow: Codable, Identifiable, Hashable, Sendable {
    let date: String
    let onTime: Int
    let late: Int
    let flagged: Int
    let absent: Int

    var id: String { date }

    enum CodingKeys: String, CodingKey {
        case date
        case onTime = "on_time"
        case late, flagged, absent
    }

    /// Shared parser for the server's `YYYY-MM-DD` payload. UTC-anchored so
    /// two clients in different timezones produce the same `Date` for a given
    /// string — the chart's x-axis should not drift with the user's tz.
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var parsedDate: Date? {
        Self.dateFormatter.date(from: date)
    }

    /// Active-employee denominator for the day. Useful for computing an on-time
    /// rate when the server doesn't pre-compute it.
    var total: Int { onTime + late + flagged + absent }
}

/// Params for `.rpc("daily_series", params: ...)`. Property names are
/// already snake_case so no `CodingKeys` needed — see the supabase patterns
/// memory in the project.
struct DailySeriesParams: Encodable, Sendable {
    let p_from: String
    let p_to: String
    let p_branch_id: UUID?
    let p_dept_id: UUID?
}
