import Foundation

/// Work shift attached to a branch. `start_local` / `end_local` are Postgres
/// `time` columns so we model them as `"HH:mm:ss"` strings on the wire and
/// surface a `Date`-valued helper for iOS date pickers.
struct Shift: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let branchId: UUID
    var name: String
    var startLocal: String
    var endLocal: String
    var graceMin: Int
    var isDefault: Bool
    var daysOfWeek: [Int]

    enum CodingKeys: String, CodingKey {
        case id, name
        case branchId = "branch_id"
        case startLocal = "start_local"
        case endLocal = "end_local"
        case graceMin = "grace_min"
        case isDefault = "is_default"
        case daysOfWeek = "days_of_week"
    }

    static let selectColumns = "id, branch_id, name, start_local, end_local, grace_min, is_default, days_of_week"

    /// Parses "HH:mm[:ss]" into a Date whose calendar components are the
    /// hour + minute. Year/month/day are today's — only hour/minute matter.
    static func time(from string: String) -> Date? {
        // Accept both "HH:mm" and "HH:mm:ss".
        let parts = string.split(separator: ":").prefix(2)
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1])
        else { return nil }
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps)
    }

    /// Formats a Date as `HH:mm:ss` for Postgres `time` storage.
    static func timeString(from date: Date) -> String {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = comps.hour ?? 0
        let minute = comps.minute ?? 0
        return String(format: "%02d:%02d:00", hour, minute)
    }
}

/// Insert payload. `id` and server-generated columns are omitted.
struct ShiftInsertPayload: Encodable, Sendable {
    let branchId: UUID
    let name: String
    let startLocal: String
    let endLocal: String
    let graceMin: Int
    let isDefault: Bool
    let daysOfWeek: [Int]

    enum CodingKeys: String, CodingKey {
        case name
        case branchId = "branch_id"
        case startLocal = "start_local"
        case endLocal = "end_local"
        case graceMin = "grace_min"
        case isDefault = "is_default"
        case daysOfWeek = "days_of_week"
    }
}

/// Partial update: only the fields admins can change from the editor.
struct ShiftUpdatePayload: Encodable, Sendable {
    let name: String
    let startLocal: String
    let endLocal: String
    let graceMin: Int
    let daysOfWeek: [Int]

    enum CodingKeys: String, CodingKey {
        case name
        case startLocal = "start_local"
        case endLocal = "end_local"
        case graceMin = "grace_min"
        case daysOfWeek = "days_of_week"
    }
}

enum Weekday: Int, CaseIterable, Hashable, Sendable, Identifiable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    var id: Int { rawValue }

    /// Short Vietnamese label (T2–T7, CN).
    var shortLabel: String {
        switch self {
        case .monday:    "T2"
        case .tuesday:   "T3"
        case .wednesday: "T4"
        case .thursday:  "T5"
        case .friday:    "T6"
        case .saturday:  "T7"
        case .sunday:    "CN"
        }
    }

    /// Full Vietnamese label.
    var fullLabel: String {
        switch self {
        case .monday:    "Thứ hai"
        case .tuesday:   "Thứ ba"
        case .wednesday: "Thứ tư"
        case .thursday:  "Thứ năm"
        case .friday:    "Thứ sáu"
        case .saturday:  "Thứ bảy"
        case .sunday:    "Chủ nhật"
        }
    }
}

extension Array where Element == Int {
    /// Renders a `days_of_week` array as a compact Vietnamese summary.
    /// Examples: `[1,2,3,4,5]` → "T2–T6"; `[1,2,3,4,5,6,7]` → "Hàng ngày";
    /// `[1,3,5]` → "T2, T4, T6".
    var weekdaySummary: String {
        let sorted = Set(self).sorted()
        guard !sorted.isEmpty else { return "—" }
        if sorted == [1, 2, 3, 4, 5, 6, 7] { return "Hàng ngày" }
        if sorted == [1, 2, 3, 4, 5] { return "T2–T6" }
        if sorted == [1, 2, 3, 4, 5, 6] { return "T2–T7" }
        if sorted == [6, 7] { return "Cuối tuần" }
        return sorted.compactMap { Weekday(rawValue: $0)?.shortLabel }.joined(separator: ", ")
    }
}
