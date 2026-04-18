import Foundation
import CoreLocation
import SwiftData
import Supabase

enum CheckInError: Error, LocalizedError {
    case rejected(String)
    case networkQueued
    case locationFailed(String)
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .rejected(let reason):
            reason
        case .networkQueued:
            "Không có kết nối — đã lưu để tự động gửi lại."
        case .locationFailed(let reason):
            reason
        case .unexpected(let message):
            message
        }
    }
}

struct CheckInOutcome: Sendable {
    let event: AttendanceEvent
    let distanceM: Int
    let radiusM: Int
}

@Observable
@MainActor
final class CheckInService {
    private let locationService: LocationService
    private let wifiService: WiFiService
    private let modelContext: ModelContext
    private var client: SupabaseClient { SupabaseManager.shared.client }

    private(set) var isWorking = false

    init(
        locationService: LocationService,
        wifiService: WiFiService,
        modelContext: ModelContext
    ) {
        self.locationService = locationService
        self.wifiService = wifiService
        self.modelContext = modelContext
    }

    func submit(type: AttendanceEventType, note: String? = nil) async throws -> CheckInOutcome {
        isWorking = true
        defer { isWorking = false }

        let location: CLLocation
        do {
            location = try await locationService.requestLocation()
        } catch {
            throw CheckInError.locationFailed(error.localizedDescription)
        }

        // Best-effort Wi-Fi read. Never fail the submission on a nil here — the
        // backend handles missing bssid/ssid gracefully.
        let wifi = await wifiService.currentNetwork()
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteValue = (trimmedNote?.isEmpty == false) ? trimmedNote : nil

        let clientTs = Date()
        let body = CheckInBody(
            type: type.rawValue,
            clientTs: ISO8601DateFormatter.supabase.string(from: clientTs),
            lat: location.coordinate.latitude,
            lng: location.coordinate.longitude,
            accuracyM: location.horizontalAccuracy,
            bssid: wifi?.bssid,
            ssid: wifi?.ssid,
            note: noteValue
        )

        do {
            let response: CheckInResponse = try await client.functions.invoke(
                "check-in",
                options: FunctionInvokeOptions(body: body)
            )
            return CheckInOutcome(
                event: response.event,
                distanceM: response.distanceM,
                radiusM: response.radiusM
            )
        } catch let FunctionsError.httpError(code, data) where code == 422 {
            // Server wrote a `rejected` row and returned it with a reason.
            let rejection = (try? JSONDecoder().decode(CheckInResponse.self, from: data))?
                .event.flaggedReason ?? "Bị từ chối"
            throw CheckInError.rejected(rejection)
        } catch let FunctionsError.httpError(code, data) where (400..<500).contains(code) {
            // 400/403/404 etc. are validation failures the user needs to act on
            // (inactive profile, no branch, signed out). Never queue these — the
            // server would reject the replay with the same error.
            throw CheckInError.rejected(Self.friendlyMessage(from: data, status: code))
        } catch {
            queueOffline(
                type: type,
                clientTs: clientTs,
                location: location,
                wifi: wifi,
                note: noteValue
            )
            throw CheckInError.networkQueued
        }
    }

    /// Maps the EF's `{error, detail}` shape to a user-facing message.
    /// Falls back to a status-based friendly message when the body doesn't
    /// decode or the error code is unknown — the user never sees raw HTTP
    /// codes. Add new EF error codes to `CheckInServerError`.
    static func friendlyMessage(from data: Data, status: Int) -> String {
        let payload = try? JSONDecoder().decode(CheckInErrorPayload.self, from: data)
        if let code = payload?.error, let known = CheckInServerError(rawValue: code) {
            if known == .badRequest, let detail = payload?.detail, !detail.isEmpty {
                return "\(known.userMessage) (\(detail))"
            }
            return known.userMessage
        }
        return fallbackMessage(forStatus: status)
    }

    /// User-facing copy for HTTP failures that don't carry a recognizable EF
    /// error code (e.g., gateway 401 before the EF runs, timeouts, 5xx).
    static func fallbackMessage(forStatus status: Int) -> String {
        switch status {
        case 401:
            return "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại."
        case 403:
            return "Bạn không có quyền thực hiện thao tác này."
        case 404:
            return "Không tìm thấy tài nguyên yêu cầu."
        case 408, 504:
            return "Yêu cầu đã hết thời gian. Kiểm tra kết nối và thử lại."
        case 429:
            return "Quá nhiều lần thử. Vui lòng chờ một chút rồi thử lại."
        case 500..<600:
            return "Máy chủ đang gặp sự cố. Vui lòng thử lại sau giây lát."
        default:
            return "Đã có lỗi xảy ra. Vui lòng thử lại."
        }
    }

    private func queueOffline(
        type: AttendanceEventType,
        clientTs: Date,
        location: CLLocation,
        wifi: (bssid: String, ssid: String)?,
        note: String?
    ) {
        let pending = PendingCheckIn(
            type: type.rawValue,
            clientTs: clientTs,
            lat: location.coordinate.latitude,
            lng: location.coordinate.longitude,
            accuracyM: location.horizontalAccuracy,
            bssid: wifi?.bssid,
            ssid: wifi?.ssid,
            note: note
        )
        modelContext.insert(pending)
        try? modelContext.save()
    }

    func flushQueue() async {
        let descriptor = FetchDescriptor<PendingCheckIn>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        guard let items = try? modelContext.fetch(descriptor), !items.isEmpty else { return }

        for item in items {
            // Replay the Wi-Fi that was captured at queue time — that's what
            // proves presence-at-branch, not the network we happen to be on
            // now (which may be home/cellular).
            let body = CheckInBody(
                type: item.type,
                clientTs: ISO8601DateFormatter.supabase.string(from: item.clientTs),
                lat: item.lat,
                lng: item.lng,
                accuracyM: item.accuracyM,
                bssid: item.bssid,
                ssid: item.ssid,
                note: item.note
            )
            do {
                let _: CheckInResponse = try await client.functions.invoke(
                    "check-in",
                    options: FunctionInvokeOptions(body: body)
                )
                modelContext.delete(item)
                try? modelContext.save()
            } catch FunctionsError.httpError(let code, _) where (400..<500).contains(code) {
                // Server rejected with a 4xx — either it's a hard reject (422)
                // or a validation failure that will never succeed on replay
                // (inactive user, no branch, expired session). Drop the entry.
                modelContext.delete(item)
                try? modelContext.save()
            } catch {
                item.attemptCount += 1
                item.lastError = error.localizedDescription
                try? modelContext.save()
                break
            }
        }
    }

    func pendingCount() -> Int {
        (try? modelContext.fetchCount(FetchDescriptor<PendingCheckIn>())) ?? 0
    }
}

extension ISO8601DateFormatter {
    static let supabase: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
