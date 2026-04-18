import Foundation
import Testing
@testable import finosWLb

@Suite("LeaveRequest")
struct LeaveRequestTests {

    // MARK: - durationDays

    @Test("Same-day request counts as 1 day")
    func sameDay() {
        let req = makeRequest(start: "2026-04-17", end: "2026-04-17")
        #expect(req.durationDays == 1)
    }

    @Test("Three-day range (inclusive on both ends) counts as 3 days")
    func threeDayRange() {
        let req = makeRequest(start: "2026-04-15", end: "2026-04-17")
        #expect(req.durationDays == 3)
    }

    @Test("Week-long request")
    func weekRange() {
        let req = makeRequest(start: "2026-04-13", end: "2026-04-19")
        #expect(req.durationDays == 7)
    }

    @Test("Malformed dates clamp to at least 1 day")
    func malformedDatesClamp() {
        let req = makeRequest(start: "not-a-date", end: "also-bad")
        #expect(req.durationDays == 1)
    }

    @Test("Invalid range (end before start) clamps to 1 day")
    func invertedRange() {
        // Guard path — the server/RLS already blocks this, but the computed
        // property shouldn't crash or go negative if a bad row ever arrives.
        let req = makeRequest(start: "2026-04-18", end: "2026-04-15")
        #expect(req.durationDays == 1)
    }

    // MARK: - format(_:)

    @Test("format returns yyyy-MM-dd in UTC regardless of locale")
    func formatStable() throws {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 4
        comps.day = 17
        comps.hour = 12
        comps.timeZone = TimeZone(identifier: "UTC")
        let cal = Calendar(identifier: .gregorian)
        let date = try #require(cal.date(from: comps))
        #expect(LeaveRequest.format(date) == "2026-04-17")
    }

    // MARK: - Codable round-trip

    @Test("Decodes a realistic PostgREST row")
    func decodesRow() throws {
        let json = #"""
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "employee_id": "22222222-2222-2222-2222-222222222222",
          "branch_id": "33333333-3333-3333-3333-333333333333",
          "kind": "annual",
          "start_date": "2026-04-15",
          "end_date": "2026-04-17",
          "reason": "Về quê",
          "status": "pending",
          "reviewed_by": null,
          "reviewed_at": null,
          "review_note": null,
          "created_at": "2026-04-10T09:15:00Z"
        }
        """#.data(using: .utf8)!
        let req = try JSONDecoder().decode(LeaveRequest.self, from: json)
        #expect(req.kind == .annual)
        #expect(req.status == .pending)
        #expect(req.reason == "Về quê")
        #expect(req.branchId != nil)
        #expect(req.durationDays == 3)
    }

    // MARK: - Helpers

    private func makeRequest(start: String, end: String) -> LeaveRequest {
        LeaveRequest(
            id: UUID(),
            employeeId: UUID(),
            branchId: UUID(),
            kind: .annual,
            startDate: start,
            endDate: end,
            reason: nil,
            status: .pending,
            reviewedBy: nil,
            reviewedAt: nil,
            reviewNote: nil,
            createdAt: "2026-01-01T00:00:00Z"
        )
    }
}
