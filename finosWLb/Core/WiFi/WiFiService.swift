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

    /// Returns the current Wi-Fi network's BSSID (lowercased, colon-separated,
    /// with each octet zero-padded to two hex digits) and SSID, or `nil` if
    /// nothing usable can be read.
    func currentNetwork() async -> (bssid: String, ssid: String)? {
        guard let network = await NEHotspotNetwork.fetchCurrent() else {
            return nil
        }

        let ssid = network.ssid
        guard let bssid = Self.normalizeBssid(network.bssid), !ssid.isEmpty else {
            // fetchCurrent occasionally returns blank fields when the device
            // is mid-association — treat as "no wifi" so the caller falls
            // back to the optional-WiFi code path.
            return nil
        }

        return (bssid: bssid, ssid: ssid)
    }

    /// Normalises an Apple-supplied BSSID string into the canonical
    /// `aa:bb:cc:dd:ee:ff` form. `NEHotspotNetwork.bssid` strips leading
    /// zeros on each octet (`"26:b:2a:c7:68:a"`), which trips our regex
    /// validation and the server's CHECK constraint. Returns `nil` if the
    /// input doesn't have exactly six colon-separated hex octets of 1–2
    /// characters each.
    ///
    /// `nonisolated` because the function is pure — tests and background
    /// actors call it without routing through the MainActor.
    nonisolated static func normalizeBssid(_ raw: String) -> String? {
        let lowered = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !lowered.isEmpty else { return nil }

        let parts = lowered.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 6 else { return nil }

        var normalized: [String] = []
        normalized.reserveCapacity(6)
        let hex = Set("0123456789abcdef")
        for part in parts {
            guard !part.isEmpty, part.count <= 2, part.allSatisfy({ hex.contains($0) }) else {
                return nil
            }
            if part.count == 2 {
                normalized.append(String(part))
            } else {
                normalized.append("0" + part)
            }
        }
        return normalized.joined(separator: ":")
    }
}
