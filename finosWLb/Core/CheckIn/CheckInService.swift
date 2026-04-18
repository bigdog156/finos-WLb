import Foundation
import CoreLocation
import OSLog
internal import PostgREST
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
        AppLog.checkin.info("submit \(type.rawValue, privacy: .public) requested (note=\(note != nil, privacy: .public))")
        isWorking = true
        defer { isWorking = false }

        let location: CLLocation
        do {
            location = try await locationService.requestLocation()
        } catch {
            AppLog.checkin.error("submit — location failed: \(logMessage(for: error), privacy: .public)")
            throw CheckInError.locationFailed(error.localizedDescription)
        }
        AppLog.checkin.debug("submit — location acquired, accuracy=\(location.horizontalAccuracy, privacy: .public)m")

        // Best-effort Wi-Fi read. Never fail the submission on a nil here — the
        // backend handles missing bssid/ssid gracefully.
        let wifi = await wifiService.currentNetwork()
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteValue = (trimmedNote?.isEmpty == false) ? trimmedNote : nil

        let clientTs = Date()
        let params = CheckInRPCParams(
            p_type: type.rawValue,
            p_client_ts: ISO8601DateFormatter.supabase.string(from: clientTs),
            p_lat: location.coordinate.latitude,
            p_lng: location.coordinate.longitude,
            p_accuracy_m: location.horizontalAccuracy,
            p_bssid: wifi?.bssid,
            p_ssid: wifi?.ssid,
            p_note: noteValue
        )

        do {
            // Direct DB call via SECURITY DEFINER RPC — bypasses the Deno
            // Edge Function runtime entirely. The JWT travels in the
            // PostgREST Authorization header as usual; `auth.uid()` inside
            // the function resolves to the signed-in user.
            let response: CheckInRPCResponse = try await client
                .rpc("check_in_rpc", params: params)
                .execute()
                .value
            AppLog.checkin.info("submit succeeded — status=\(response.event.status.rawValue, privacy: .public) distance=\(response.distanceM, privacy: .public)m rejected=\(response.rejected, privacy: .public)")

            if response.rejected {
                // The rejection reason was stored in flagged_reason by the
                // RPC. Surface it so the user sees why.
                throw CheckInError.rejected(
                    response.event.flaggedReason ?? "Chấm công bị từ chối."
                )
            }

            return CheckInOutcome(
                event: response.event,
                distanceM: response.distanceM,
                radiusM: response.radiusM
            )
        } catch let error as CheckInError {
            throw error
        } catch let error as PostgrestError {
            // RPC raised an exception: profile_inactive, no_branch_assigned,
            // forbidden, etc. Surface the Postgres message — it's already
            // short + actionable + matches the EF error code names.
            AppLog.checkin.error("check_in_rpc failed: \(error.message, privacy: .public) code=\(error.code ?? "?", privacy: .public)")
            let message = Self.friendlyMessageFromPostgres(error.message)
            throw CheckInError.rejected(message)
        } catch {
            AppLog.checkin.error("submit — network error, queuing: \(logMessage(for: error), privacy: .public)")
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

    /// Maps known Postgres exception messages raised by `check_in_rpc` onto
    /// the Vietnamese copy the old Edge Function path used.
    private static func friendlyMessageFromPostgres(_ raw: String) -> String {
        let lowered = raw.lowercased()
        if lowered.contains("profile_inactive") {
            return CheckInServerError.profileInactive.userMessage
        }
        if lowered.contains("no_branch_assigned") {
            return CheckInServerError.noBranchAssigned.userMessage
        }
        if lowered.contains("profile_not_found") {
            return CheckInServerError.profileNotFound.userMessage
        }
        if lowered.contains("branch_not_found") {
            return CheckInServerError.branchNotFound.userMessage
        }
        if lowered.contains("unauthorized") {
            return CheckInServerError.unauthorized.userMessage
        }
        return raw
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
        AppLog.checkin.info("flushQueue — \(items.count, privacy: .public) pending items")

        for item in items {
            // Replay the Wi-Fi that was captured at queue time — that's what
            // proves presence-at-branch, not the network we happen to be on
            // now (which may be home/cellular).
            let params = CheckInRPCParams(
                p_type: item.type,
                p_client_ts: ISO8601DateFormatter.supabase.string(from: item.clientTs),
                p_lat: item.lat,
                p_lng: item.lng,
                p_accuracy_m: item.accuracyM,
                p_bssid: item.bssid,
                p_ssid: item.ssid,
                p_note: item.note
            )
            do {
                let _: CheckInRPCResponse = try await client
                    .rpc("check_in_rpc", params: params)
                    .execute()
                    .value
                modelContext.delete(item)
                try? modelContext.save()
            } catch let error as PostgrestError {
                // Deterministic failure (e.g., profile_inactive, no_branch)
                // — replay won't succeed until an admin acts, so drop.
                let msg = error.message.lowercased()
                let isUserActionable = msg.contains("profile_inactive")
                    || msg.contains("no_branch_assigned")
                    || msg.contains("profile_not_found")
                    || msg.contains("branch_not_found")
                    || msg.contains("unauthorized")
                if isUserActionable {
                    modelContext.delete(item)
                    try? modelContext.save()
                } else {
                    item.attemptCount += 1
                    item.lastError = error.message
                    try? modelContext.save()
                    break
                }
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
