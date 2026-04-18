import Foundation
import Testing
@testable import finosWLb

@Suite("Model labels and rawValues")
struct ModelLabelTests {

    @Test("AttendanceEventType labels")
    func attendanceTypes() {
        #expect(AttendanceEventType.checkIn.label == "Chấm công vào")
        #expect(AttendanceEventType.checkOut.label == "Chấm công ra")
        #expect(AttendanceEventType.checkIn.rawValue == "check_in")
        #expect(AttendanceEventType.checkOut.rawValue == "check_out")
    }

    @Test("AttendanceEventStatus labels cover every case")
    func attendanceStatuses() {
        let expected: [AttendanceEventStatus: String] = [
            .onTime:   "Đúng giờ",
            .late:     "Trễ",
            .absent:   "Vắng",
            .flagged:  "Gắn cờ",
            .rejected: "Bị từ chối",
        ]
        for c in AttendanceEventStatus.allCases {
            #expect(c.label == expected[c], "Missing or wrong label for \(c)")
            #expect(!c.rawValue.isEmpty)
        }
    }

    @Test("UserRole labels")
    func userRoles() {
        #expect(UserRole.admin.label == "Quản trị viên")
        #expect(UserRole.manager.label == "Quản lý")
        #expect(UserRole.employee.label == "Nhân viên")
    }

    @Test("LeaveKind labels + raw values")
    func leaveKinds() {
        #expect(LeaveKind.annual.label == "Nghỉ phép năm")
        #expect(LeaveKind.sick.label == "Nghỉ ốm")
        #expect(LeaveKind.unpaid.label == "Nghỉ không lương")
        #expect(LeaveKind.other.label == "Khác")
        // rawValue must match the Postgres enum.
        #expect(LeaveKind.annual.rawValue == "annual")
        #expect(LeaveKind.sick.rawValue == "sick")
        #expect(LeaveKind.unpaid.rawValue == "unpaid")
        #expect(LeaveKind.other.rawValue == "other")
    }

    @Test("LeaveStatus labels + raw values")
    func leaveStatuses() {
        #expect(LeaveStatus.pending.rawValue == "pending")
        #expect(LeaveStatus.approved.rawValue == "approved")
        #expect(LeaveStatus.rejected.rawValue == "rejected")
        #expect(LeaveStatus.cancelled.rawValue == "cancelled")
        for c in LeaveStatus.allCases {
            #expect(!c.label.isEmpty)
            #expect(!c.systemImage.isEmpty)
        }
    }
}
