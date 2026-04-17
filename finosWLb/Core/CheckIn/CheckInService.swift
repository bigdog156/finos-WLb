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
            "No connection — saved for automatic retry."
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

    func submit(type: AttendanceEventType) async throws -> CheckInOutcome {
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

        let clientTs = Date()
        let body = CheckInBody(
            type: type.rawValue,
            clientTs: ISO8601DateFormatter.supabase.string(from: clientTs),
            lat: location.coordinate.latitude,
            lng: location.coordinate.longitude,
            accuracyM: location.horizontalAccuracy,
            bssid: wifi?.bssid,
            ssid: wifi?.ssid
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
            let rejection = (try? JSONDecoder().decode(CheckInResponse.self, from: data))?
                .event.flaggedReason ?? "Rejected"
            throw CheckInError.rejected(rejection)
        } catch {
            queueOffline(
                type: type,
                clientTs: clientTs,
                location: location,
                wifi: wifi
            )
            throw CheckInError.networkQueued
        }
    }

    private func queueOffline(
        type: AttendanceEventType,
        clientTs: Date,
        location: CLLocation,
        wifi: (bssid: String, ssid: String)?
    ) {
        let pending = PendingCheckIn(
            type: type.rawValue,
            clientTs: clientTs,
            lat: location.coordinate.latitude,
            lng: location.coordinate.longitude,
            accuracyM: location.horizontalAccuracy,
            bssid: wifi?.bssid,
            ssid: wifi?.ssid
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
                ssid: item.ssid
            )
            do {
                let _: CheckInResponse = try await client.functions.invoke(
                    "check-in",
                    options: FunctionInvokeOptions(body: body)
                )
                modelContext.delete(item)
                try? modelContext.save()
            } catch FunctionsError.httpError(let code, _) where code == 422 {
                // Server rejected — don't retry this one forever.
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
