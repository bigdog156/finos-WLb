import SwiftUI
import CoreLocation
internal import PostgREST
import Supabase

/// Admin CRUD screen for the `branch_wifi` table, scoped to a single branch.
/// Admin RLS policies already permit insert/delete, so this talks to Postgres
/// directly via PostgREST — no Edge Function needed.
///
/// Anti-spoofing guards applied on the Add flow:
///   1. Reject multicast / locally-administered / broadcast / all-zero MACs
///      — these can be spoofed trivially by any phone with a software AP.
///   2. Confirm the admin is physically inside the branch radius using the
///      `distance_to_branch` RPC against their current GPS. Rejects an
///      admin who tries to register their home Wi-Fi.
///   3. Warn (non-blocking) if the typed BSSID does not match the device's
///      currently-joined network — mismatch is usually a copy-paste typo,
///      but sometimes intentional.
///   4. The server enforces the same MAC shape via a CHECK constraint and
///      audits every insert/delete via a trigger (see migration
///      `branch_wifi_antispoof`).
struct BranchWifiView: View {
    let branch: Branch

    @State private var rows: [BranchWifi] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var warningMessage: String?

    @State private var newBssid: String = ""
    @State private var newSsid: String = ""
    @State private var isAdding = false
    @State private var isReadingWifi = false

    @State private var wifiService = WiFiService()
    @State private var locationService = LocationService()

    /// BSSID the device is currently connected to. Populated by
    /// `useCurrentWifi()`; used to flag mismatches when the admin also
    /// types a BSSID manually.
    @State private var currentDeviceBssid: String?

    var body: some View {
        List {
            Section("Thêm BSSID") {
                TextField("aa:bb:cc:dd:ee:ff", text: $newBssid)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.none)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: newBssid) { _, newValue in
                        let lowered = newValue.lowercased()
                        if lowered != newValue { newBssid = lowered }
                    }

                TextField("SSID (tùy chọn)", text: $newSsid)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    Task { await useCurrentWifi() }
                } label: {
                    HStack {
                        Label("Dùng WiFi hiện tại", systemImage: "wifi")
                        Spacer()
                        if isReadingWifi { ProgressView() }
                    }
                }
                .disabled(isReadingWifi)

                Button {
                    Task { await addRow() }
                } label: {
                    HStack {
                        Text("Thêm")
                        Spacer()
                        if isAdding { ProgressView() }
                    }
                }
                .disabled(!canAdd || isAdding)
            }

            Section("Mạng đã duyệt") {
                if rows.isEmpty && !isLoading {
                    Text("Chưa có BSSID nào.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.bssid)
                                .font(.system(.body, design: .monospaced))
                            if let ssid = row.ssid, !ssid.isEmpty {
                                Text(ssid)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: deleteRows)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            if let warningMessage {
                Section {
                    Label(warningMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
        .overlay {
            if isLoading && rows.isEmpty {
                ProgressView()
            }
        }
        .navigationTitle(branch.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Derived

    private var canAdd: Bool {
        let trimmed = newBssid.trimmingCharacters(in: .whitespaces).lowercased()
        return validateBssid(trimmed) == .valid
    }

    enum BssidCheck: Equatable {
        case valid
        case badShape
        case placeholder          // all-zeros or broadcast
        case multicast            // first-byte LSB set
        case locallyAdministered  // first-byte bit 1 set (software AP / randomised)

        var userMessage: String {
            switch self {
            case .valid:
                "BSSID hợp lệ."
            case .badShape:
                "BSSID phải có dạng aa:bb:cc:dd:ee:ff."
            case .placeholder:
                "BSSID này không phải là thiết bị thật (mặc định hệ thống)."
            case .multicast:
                "Đây là địa chỉ multicast, không thể là BSSID router."
            case .locallyAdministered:
                "BSSID này là địa chỉ phát tự (software AP / MAC ngẫu nhiên) — không thể dùng cho chi nhánh."
            }
        }
    }

    /// Strict BSSID validation. Rejects multicast, locally-administered,
    /// broadcast, and all-zero MACs — same rules as the DB CHECK constraint
    /// so the client can tell the admin *why* the value isn't allowed
    /// before hitting the network.
    func validateBssid(_ value: String) -> BssidCheck {
        let pattern = #"^[0-9a-f]{2}(:[0-9a-f]{2}){5}$"#
        guard value.range(of: pattern, options: .regularExpression) != nil else {
            return .badShape
        }
        if value == "00:00:00:00:00:00" || value == "ff:ff:ff:ff:ff:ff" {
            return .placeholder
        }
        // Parse the first octet's low nibble. Valid unicast OUI-assigned
        // MACs have bits 0 and 1 of byte 0 clear → low nibble ∈ {0,4,8,c}.
        guard
            let firstByte = UInt8(value.prefix(2), radix: 16)
        else { return .badShape }
        if firstByte & 0b0000_0001 != 0 { return .multicast }
        if firstByte & 0b0000_0010 != 0 { return .locallyAdministered }
        return .valid
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            rows = try await SupabaseManager.shared.client
                .from("branch_wifi")
                .select("branch_id, bssid, ssid")
                .eq("branch_id", value: branch.id.uuidString)
                .order("bssid")
                .execute()
                .value
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addRow() async {
        let raw = newBssid.trimmingCharacters(in: .whitespaces).lowercased()
        // Apple's Wi-Fi API (and copy-pasted router UIs) often emit
        // unpadded MACs like "26:b:2a:c7:68:a" — normalise to the
        // canonical 6-pair form before validating.
        let bssid = WiFiService.normalizeBssid(raw) ?? raw
        let ssidTrimmed = newSsid.trimmingCharacters(in: .whitespaces)
        let ssid: String? = ssidTrimmed.isEmpty ? nil : ssidTrimmed

        let check = validateBssid(bssid)
        guard check == .valid else {
            errorMessage = check.userMessage
            return
        }

        isAdding = true
        defer { isAdding = false }
        errorMessage = nil
        warningMessage = nil

        // Anti-spoof gate: require the admin to be physically inside the
        // branch radius. Running the check via the existing
        // `distance_to_branch(branch, lat, lng)` RPC avoids shipping the
        // branch coordinates back to the client.
        let location: CLLocation
        do {
            location = try await locationService.requestLocation()
        } catch {
            errorMessage = "Không đọc được vị trí để xác minh. Bật quyền định vị trong Cài đặt rồi thử lại."
            return
        }

        do {
            let distanceRows: [DistanceRow] = try await SupabaseManager.shared.client
                .rpc("distance_to_branch", params: DistanceParams(
                    p_branch: branch.id,
                    p_lat: location.coordinate.latitude,
                    p_lng: location.coordinate.longitude
                ))
                .execute()
                .value
            let distance = distanceRows.first?.value ?? .infinity
            // Slight 20% buffer above radius so fringe-of-geofence admins
            // (standing just outside the front door) aren't locked out.
            let limit = Double(branch.radiusM) * 1.2
            if distance > limit {
                errorMessage = "Bạn đang cách chi nhánh khoảng \(Int(distance.rounded())) m — phải đứng tại chi nhánh mới có thể thêm WiFi."
                return
            }
        } catch {
            errorMessage = "Không xác minh được khoảng cách tới chi nhánh: \(error.localizedDescription)"
            return
        }

        // Warn (but don't block) if the typed BSSID isn't the one the
        // device is currently connected to. Admin may be rotating two APs.
        if let current = currentDeviceBssid, current != bssid {
            warningMessage = "BSSID bạn đang kết nối là \(current) — khác với giá trị vừa nhập. Xác nhận trước khi lưu."
        }

        let payload = NewBranchWifi(branchId: branch.id, bssid: bssid, ssid: ssid)

        do {
            try await SupabaseManager.shared.client
                .from("branch_wifi")
                .insert(payload)
                .execute()
            newBssid = ""
            newSsid = ""
            errorMessage = nil
            warningMessage = nil
            currentDeviceBssid = nil
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteRows(at offsets: IndexSet) {
        let targets = offsets.map { rows[$0] }
        Task { await delete(targets) }
    }

    private func delete(_ targets: [BranchWifi]) async {
        for target in targets {
            do {
                try await SupabaseManager.shared.client
                    .from("branch_wifi")
                    .delete()
                    .eq("branch_id", value: target.branchId.uuidString)
                    .eq("bssid", value: target.bssid)
                    .execute()
                rows.removeAll { $0.branchId == target.branchId && $0.bssid == target.bssid }
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
    }

    private func useCurrentWifi() async {
        isReadingWifi = true
        defer { isReadingWifi = false }

        guard let network = await wifiService.currentNetwork() else {
            errorMessage = "Không thể đọc WiFi hiện tại. Hãy đảm bảo bạn đang kết nối và ứng dụng có quyền Access WiFi Information."
            return
        }
        let bssid = network.bssid.lowercased()
        newBssid = bssid
        newSsid = network.ssid
        currentDeviceBssid = bssid
        errorMessage = nil
        warningMessage = nil

        // Pre-emptively warn if the device itself is on a MAC we wouldn't
        // accept — better to say so now than to fail validation on tap.
        let check = validateBssid(bssid)
        if check != .valid {
            warningMessage = check.userMessage
        }
    }
}

// MARK: - RPC DTOs

private struct DistanceParams: Encodable, Sendable {
    let p_branch: UUID
    let p_lat: Double
    let p_lng: Double
}

/// `distance_to_branch` returns a single `double precision` value.
/// PostgREST wraps scalar RPC results as `[{"<functionName>": <value>}]`
/// by default, but current clients decode as a plain array of scalars —
/// we use a tiny wrapper so the decode is explicit either way.
private struct DistanceRow: Decodable {
    let value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try container.decode(Double.self)
    }
}

#Preview {
    NavigationStack {
        BranchWifiView(
            branch: Branch(
                id: UUID(),
                name: "HQ",
                tz: "Asia/Ho_Chi_Minh",
                address: "123 Example St.",
                radiusM: 120
            )
        )
    }
}
