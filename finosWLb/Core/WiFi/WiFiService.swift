import Foundation
import NetworkExtension

/// Wraps `NEHotspotNetwork.fetchCurrent()` so callers get a simple `(bssid, ssid)?`
/// tuple and never see a thrown error. Returns `nil` on any failure — no permission,
/// no Wi-Fi, airplane mode, missing entitlement, etc.
///
/// Requires the `com.apple.developer.networking.wifi-info` entitlement and that the
/// "Access WiFi Information" capability is enabled on the App ID in the Apple
/// Developer portal. Without that, `fetchCurrent()` silently resolves to `nil` at
/// runtime.
@MainActor
final class WiFiService {
    init() {}

    /// Returns the current Wi-Fi network's BSSID (lowercased, colon-separated) and
    /// SSID, or `nil` if nothing usable can be read.
    func currentNetwork() async -> (bssid: String, ssid: String)? {
        guard let network = await NEHotspotNetwork.fetchCurrent() else {
            return nil
        }

        let bssid = network.bssid.lowercased()
        let ssid = network.ssid

        // Guard against empty strings — fetchCurrent occasionally returns a
        // network with blank fields when the device is between associations.
        guard !bssid.isEmpty, !ssid.isEmpty else { return nil }

        return (bssid: bssid, ssid: ssid)
    }
}
