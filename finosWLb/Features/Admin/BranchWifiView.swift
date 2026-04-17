import SwiftUI
internal import PostgREST
import Supabase

/// Admin CRUD screen for the `branch_wifi` table, scoped to a single branch.
/// Admin RLS policies already permit insert/delete, so this talks to Postgres
/// directly via PostgREST — no Edge Function needed.
struct BranchWifiView: View {
    let branch: Branch

    @State private var rows: [BranchWifi] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var newBssid: String = ""
    @State private var newSsid: String = ""
    @State private var isAdding = false
    @State private var isReadingWifi = false

    @State private var wifiService = WiFiService()

    var body: some View {
        List {
            Section("Add BSSID") {
                TextField("aa:bb:cc:dd:ee:ff", text: $newBssid)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.none)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: newBssid) { _, newValue in
                        let lowered = newValue.lowercased()
                        if lowered != newValue { newBssid = lowered }
                    }

                TextField("SSID (optional)", text: $newSsid)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    Task { await useCurrentWifi() }
                } label: {
                    HStack {
                        Label("Use current Wi-Fi", systemImage: "wifi")
                        Spacer()
                        if isReadingWifi { ProgressView() }
                    }
                }
                .disabled(isReadingWifi)

                Button {
                    Task { await addRow() }
                } label: {
                    HStack {
                        Text("Add")
                        Spacer()
                        if isAdding { ProgressView() }
                    }
                }
                .disabled(!canAdd || isAdding)
            }

            Section("Approved networks") {
                if rows.isEmpty && !isLoading {
                    Text("No BSSIDs yet.")
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
        let trimmed = newBssid.trimmingCharacters(in: .whitespaces)
        return isValidBssid(trimmed)
    }

    /// Minimal sanity check: six lowercase hex pairs separated by colons.
    /// Postgres has its own constraint; this just prevents obvious typos
    /// from hitting the network.
    private func isValidBssid(_ value: String) -> Bool {
        let pattern = #"^[0-9a-f]{2}(:[0-9a-f]{2}){5}$"#
        return value.range(of: pattern, options: .regularExpression) != nil
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
        let bssid = newBssid.trimmingCharacters(in: .whitespaces).lowercased()
        let ssidTrimmed = newSsid.trimmingCharacters(in: .whitespaces)
        let ssid: String? = ssidTrimmed.isEmpty ? nil : ssidTrimmed

        guard isValidBssid(bssid) else {
            errorMessage = "BSSID must look like aa:bb:cc:dd:ee:ff."
            return
        }

        isAdding = true
        defer { isAdding = false }

        let payload = NewBranchWifi(branchId: branch.id, bssid: bssid, ssid: ssid)

        do {
            try await SupabaseManager.shared.client
                .from("branch_wifi")
                .insert(payload)
                .execute()
            newBssid = ""
            newSsid = ""
            errorMessage = nil
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
            errorMessage = "Couldn't read current Wi-Fi. Make sure you're connected and the app has the Access WiFi Information capability."
            return
        }
        newBssid = network.bssid
        newSsid = network.ssid
        errorMessage = nil
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
