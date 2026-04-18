import Foundation
import CoreLocation

@MainActor
final class LocationService: NSObject {
    enum LocationError: Error, LocalizedError {
        case permissionDenied
        case locationUnavailable(String)
        case timeout

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                "Cần cấp quyền truy cập vị trí. Vui lòng bật trong Cài đặt."
            case .locationUnavailable(let reason):
                "Không thể lấy vị trí: \(reason)"
            case .timeout:
                "Không thể xác định vị trí chính xác. Hãy thử di chuyển đến gần cửa sổ."
            }
        }
    }

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    func requestLocation(timeout: Duration = .seconds(15)) async throws -> CLLocation {
        if manager.authorizationStatus == .notDetermined {
            _ = await requestAuthorization()
        }

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            break
        case .denied, .restricted, .notDetermined:
            throw LocationError.permissionDenied
        @unknown default:
            throw LocationError.permissionDenied
        }

        if let pending = locationContinuation {
            locationContinuation = nil
            pending.resume(throwing: LocationError.locationUnavailable("superseded"))
        }
        timeoutTask?.cancel()

        return try await withCheckedThrowingContinuation { cont in
            self.locationContinuation = cont
            manager.requestLocation()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                await self?.fireTimeout()
            }
        }
    }

    private func fireTimeout() {
        guard let cont = locationContinuation else { return }
        locationContinuation = nil
        cont.resume(throwing: LocationError.timeout)
    }

    private func requestAuthorization() async -> CLAuthorizationStatus {
        await withCheckedContinuation { cont in
            self.authContinuation = cont
            manager.requestWhenInUseAuthorization()
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if let cont = self.authContinuation {
                self.authContinuation = nil
                cont.resume(returning: status)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            guard let cont = self.locationContinuation else { return }
            self.locationContinuation = nil
            self.timeoutTask?.cancel()
            cont.resume(returning: loc)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            guard let cont = self.locationContinuation else { return }
            self.locationContinuation = nil
            self.timeoutTask?.cancel()
            cont.resume(throwing: LocationError.locationUnavailable(message))
        }
    }
}
