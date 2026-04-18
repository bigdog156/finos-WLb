import Foundation
import Testing
@testable import finosWLb

@Suite("CheckInService error mapping")
struct CheckInServiceMessageTests {

    // MARK: - friendlyMessage

    @Test("Decodes known EF error code into user-facing message")
    func knownCodeMapsToUserMessage() {
        let data = Data(#"{"error":"no_branch_assigned"}"#.utf8)
        let msg = CheckInService.friendlyMessage(from: data, status: 400)
        #expect(msg == CheckInServerError.noBranchAssigned.userMessage)
    }

    @Test("Unknown code falls back to status-based copy")
    func unknownCodeFallsBackToStatus() {
        let data = Data(#"{"error":"aliens_ate_my_sandwich"}"#.utf8)
        let msg = CheckInService.friendlyMessage(from: data, status: 500)
        #expect(msg == CheckInService.fallbackMessage(forStatus: 500))
    }

    @Test("Non-JSON body falls back to status-based copy")
    func nonJsonFallsBack() {
        let data = Data("gateway error".utf8)
        let msg = CheckInService.friendlyMessage(from: data, status: 404)
        #expect(msg == CheckInService.fallbackMessage(forStatus: 404))
    }

    @Test("bad_request with detail appends parenthetical")
    func badRequestAppendsDetail() {
        let data = Data(#"{"error":"bad_request","detail":"invalid accuracy_m"}"#.utf8)
        let msg = CheckInService.friendlyMessage(from: data, status: 400)
        #expect(msg.contains(CheckInServerError.badRequest.userMessage))
        #expect(msg.contains("invalid accuracy_m"))
    }

    @Test("bad_request with empty detail uses bare user message")
    func badRequestEmptyDetail() {
        let data = Data(#"{"error":"bad_request","detail":""}"#.utf8)
        let msg = CheckInService.friendlyMessage(from: data, status: 400)
        #expect(msg == CheckInServerError.badRequest.userMessage)
    }

    // MARK: - fallbackMessage

    @Test("Fallback messages cover common HTTP statuses", arguments: [
        (401, "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại."),
        (403, "Bạn không có quyền thực hiện thao tác này."),
        (404, "Không tìm thấy tài nguyên yêu cầu."),
        (408, "Yêu cầu đã hết thời gian. Kiểm tra kết nối và thử lại."),
        (504, "Yêu cầu đã hết thời gian. Kiểm tra kết nối và thử lại."),
        (429, "Quá nhiều lần thử. Vui lòng chờ một chút rồi thử lại."),
    ])
    func fallbackByStatus(status: Int, expected: String) {
        #expect(CheckInService.fallbackMessage(forStatus: status) == expected)
    }

    @Test("5xx range falls into server-trouble copy", arguments: [500, 502, 503])
    func serverRange(status: Int) {
        #expect(CheckInService.fallbackMessage(forStatus: status)
                == "Máy chủ đang gặp sự cố. Vui lòng thử lại sau giây lát.")
    }

    @Test("Unrecognised status uses generic fallback")
    func genericFallback() {
        #expect(CheckInService.fallbackMessage(forStatus: 418)
                == "Đã có lỗi xảy ra. Vui lòng thử lại.")
    }
}
