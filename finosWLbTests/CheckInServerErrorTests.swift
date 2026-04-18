import Foundation
import Testing
@testable import finosWLb

@Suite("CheckInServerError")
struct CheckInServerErrorTests {

    @Test("All raw values round-trip via rawValue init")
    func rawValuesRoundTrip() {
        let cases: [CheckInServerError] = [
            .noBranchAssigned, .badRequest, .unauthorized, .profileInactive,
            .profileNotFound, .branchNotFound, .methodNotAllowed,
            .distanceCalcFailed, .travelCheckFailed, .insertFailed
        ]
        for c in cases {
            #expect(CheckInServerError(rawValue: c.rawValue) == c)
        }
    }

    @Test("Unknown raw value returns nil")
    func unknownReturnsNil() {
        #expect(CheckInServerError(rawValue: "not_a_real_code") == nil)
    }

    @Test("User-facing messages are Vietnamese and non-empty")
    func userMessagesNonEmpty() {
        for code in allCodes {
            let msg = code.userMessage
            #expect(!msg.isEmpty, "userMessage for \(code) must not be empty")
            #expect(msg.count < 200, "userMessage for \(code) too long")
        }
    }

    @Test("isUserActionable — admin-setup codes")
    func userActionableAdminCodes() {
        #expect(CheckInServerError.noBranchAssigned.isUserActionable)
        #expect(CheckInServerError.profileInactive.isUserActionable)
        #expect(CheckInServerError.profileNotFound.isUserActionable)
        #expect(CheckInServerError.branchNotFound.isUserActionable)
        #expect(CheckInServerError.unauthorized.isUserActionable)
        #expect(CheckInServerError.badRequest.isUserActionable)
        #expect(CheckInServerError.methodNotAllowed.isUserActionable)
    }

    @Test("isUserActionable — transient internal codes are replayable")
    func userActionableInternalCodes() {
        #expect(!CheckInServerError.distanceCalcFailed.isUserActionable)
        #expect(!CheckInServerError.travelCheckFailed.isUserActionable)
        #expect(!CheckInServerError.insertFailed.isUserActionable)
    }

    @Test("Specific user-facing strings stay stable")
    func specificCopyStable() {
        #expect(CheckInServerError.noBranchAssigned.userMessage
                == "Bạn chưa được gán vào chi nhánh nào. Vui lòng liên hệ quản trị viên để được gán.")
        #expect(CheckInServerError.profileInactive.userMessage
                == "Tài khoản của bạn chưa được kích hoạt. Vui lòng liên hệ quản trị viên để kích hoạt.")
        #expect(CheckInServerError.unauthorized.userMessage
                == "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.")
    }

    private var allCodes: [CheckInServerError] {
        [.noBranchAssigned, .badRequest, .unauthorized, .profileInactive,
         .profileNotFound, .branchNotFound, .methodNotAllowed,
         .distanceCalcFailed, .travelCheckFailed, .insertFailed]
    }
}
