import SwiftUI
import MapKit
import CoreLocation
internal import PostgREST
import Supabase

/// Create/edit screen for a branch. The map is a center-pin design: the pin
/// stays centered on screen, the map slides underneath, and we commit lat/lng
/// from `context.region.center` at the end of each pan/zoom gesture.
struct BranchEditorView: View {
    enum Mode: Hashable {
        case create
        case edit(BranchWithGeo)

        var existing: BranchWithGeo? {
            if case .edit(let b) = self { return b }
            return nil
        }
    }

    let mode: Mode
    /// Callback fired on successful save or delete. Receives the saved branch
    /// (nil on delete) so parents can reload their lists.
    var onCompletion: ((BranchWithGeo?) async -> Void)? = nil

    // MARK: - Form state
    @State private var name: String
    @State private var tz: String
    @State private var address: String
    @State private var lat: Double
    @State private var lng: Double
    @State private var radiusMDouble: Double
    @State private var defaultShiftId: UUID?

    // MARK: - Map
    @State private var cameraPosition: MapCameraPosition

    // MARK: - UI state
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var showingDeleteConfirm = false
    @State private var assignedEmployeeCount: Int?
    @State private var shifts: [BranchEditorView.ShiftRow] = []
    @State private var locationService = LocationService()
    @State private var isFetchingLocation = false
    @Environment(\.dismiss) private var dismiss

    init(mode: Mode, onCompletion: ((BranchWithGeo?) async -> Void)? = nil) {
        self.mode = mode
        self.onCompletion = onCompletion

        switch mode {
        case .create:
            let defaultLat = 10.7769
            let defaultLng = 106.7009
            _name = State(initialValue: "")
            _tz = State(initialValue: TimeZone.current.identifier)
            _address = State(initialValue: "")
            _lat = State(initialValue: defaultLat)
            _lng = State(initialValue: defaultLng)
            _radiusMDouble = State(initialValue: 100)
            _defaultShiftId = State(initialValue: nil)
            _cameraPosition = State(initialValue: .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: defaultLat, longitude: defaultLng),
                    latitudinalMeters: 600,
                    longitudinalMeters: 600
                )
            ))
        case .edit(let branch):
            _name = State(initialValue: branch.name)
            _tz = State(initialValue: branch.tz)
            _address = State(initialValue: branch.address ?? "")
            _lat = State(initialValue: branch.lat)
            _lng = State(initialValue: branch.lng)
            _radiusMDouble = State(initialValue: Double(branch.radiusM))
            _defaultShiftId = State(initialValue: branch.defaultShiftId)
            _cameraPosition = State(initialValue: .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: branch.lat, longitude: branch.lng),
                    latitudinalMeters: max(300, Double(branch.radiusM) * 6),
                    longitudinalMeters: max(300, Double(branch.radiusM) * 6)
                )
            ))
        }
    }

    var body: some View {
        Form {
            detailsSection
            locationSection
            shiftSection
            wifiSection
            dangerZoneSection

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save").fontWeight(.semibold)
                    }
                }
                .disabled(!isValid || isSaving)
            }
            if case .create = mode {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            if case .edit(let branch) = mode {
                await loadEmployeeCount(branchId: branch.id)
                await loadShifts(branchId: branch.id)
            }
        }
        .confirmationDialog(
            "Delete branch?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await deleteBranch() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let count = assignedEmployeeCount ?? 0
            Text("This will delete the branch. \(count) employee\(count == 1 ? "" : "s") assigned to it will become unassigned. Continue?")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var detailsSection: some View {
        Section("Details") {
            TextField("Name", text: $name)
                .textInputAutocapitalization(.words)

            NavigationLink {
                TimezonePickerView(selection: $tz)
            } label: {
                HStack {
                    Text("Time zone")
                    Spacer()
                    Text(tz)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            TextField("Address (optional)", text: $address, axis: .vertical)
                .lineLimit(1...3)
        }
    }

    @ViewBuilder
    private var locationSection: some View {
        Section("Location") {
            ZStack {
                Map(position: $cameraPosition) {
                    // No Marker here — the committed location is represented
                    // by the screen-centered pin overlay below. Adding a
                    // Marker would cause two pins to separate during pan and
                    // snap back on release.
                    MapCircle(
                        center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                        radius: CLLocationDistance(radiusM)
                    )
                    .foregroundStyle(.tint.opacity(0.15))
                    .stroke(.tint, lineWidth: 1)
                }
                .mapStyle(.standard)
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onMapCameraChange(frequency: .onEnd) { context in
                    let c = context.region.center
                    lat = c.latitude
                    lng = c.longitude
                }

                // Center pin marker on top — visual affordance for the
                // "drag map, pin stays centered" interaction.
                Image(systemName: "mappin")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
            .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))

            Text(String(format: "Lat: %.6f  Lng: %.6f", lat, lng))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Radius")
                    Spacer()
                    Text("\(radiusM) m")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $radiusMDouble, in: 20...1000, step: 10)
            }

            Button {
                Task { await useCurrentLocation() }
            } label: {
                HStack {
                    Label("Use my current location", systemImage: "location")
                    Spacer()
                    if isFetchingLocation { ProgressView() }
                }
            }
            .disabled(isFetchingLocation)
        }
    }

    @ViewBuilder
    private var shiftSection: some View {
        Section("Default shift") {
            switch mode {
            case .create:
                Text("Choose after creating")
                    .foregroundStyle(.secondary)
            case .edit:
                if shifts.isEmpty {
                    Text("No shifts defined for this branch yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Shift", selection: $defaultShiftId) {
                        Text("None").tag(UUID?.none)
                        ForEach(shifts) { shift in
                            Text(shift.label).tag(UUID?.some(shift.id))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var wifiSection: some View {
        if case .edit(let branch) = mode {
            Section("Wi-Fi allowlist") {
                NavigationLink {
                    BranchWifiView(branch: Branch(branch))
                } label: {
                    Label("Approved networks", systemImage: "wifi")
                }
            }
        }
    }

    @ViewBuilder
    private var dangerZoneSection: some View {
        if case .edit = mode {
            Section {
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    HStack {
                        if isDeleting {
                            ProgressView()
                        } else {
                            Text("Delete branch")
                        }
                        Spacer()
                        if let count = assignedEmployeeCount {
                            Text("\(count) employee\(count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(isDeleting)
            } header: {
                Text("Danger zone")
            } footer: {
                Text("Employees assigned to this branch will become unassigned.")
            }
        }
    }

    // MARK: - Derived

    private var navTitle: String {
        switch mode {
        case .create: return "New branch"
        case .edit(let b): return b.name
        }
    }

    private var radiusM: Int { Int(radiusMDouble.rounded()) }

    private var isValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !tz.isEmpty else { return false }
        guard lat.isFinite, lng.isFinite else { return false }
        return true
    }

    // MARK: - Networking

    private func save() async {
        guard isValid, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let addressValue: String? = trimmedAddress.isEmpty ? nil : trimmedAddress

        do {
            switch mode {
            case .create:
                let params = CreateBranchParams(
                    p_name: trimmedName,
                    p_tz: tz,
                    p_address: addressValue,
                    p_lat: lat,
                    p_lng: lng,
                    p_radius_m: radiusM
                )
                try await SupabaseManager.shared.client
                    .rpc("create_branch", params: params)
                    .execute()
                dismiss()
                await onCompletion?(nil)

            case .edit(let existing):
                let params = UpdateBranchParams(
                    p_id: existing.id,
                    p_name: trimmedName,
                    p_tz: tz,
                    p_address: addressValue,
                    p_lat: lat,
                    p_lng: lng,
                    p_radius_m: radiusM
                )
                try await SupabaseManager.shared.client
                    .rpc("update_branch", params: params)
                    .execute()

                // Persist the default_shift_id separately — the RPC contract
                // doesn't include it, but we still want admins to be able to
                // assign it from this editor.
                if defaultShiftId != existing.defaultShiftId {
                    let payload = BranchShiftUpdate(defaultShiftId: defaultShiftId)
                    try await SupabaseManager.shared.client
                        .from("branches")
                        .update(payload)
                        .eq("id", value: existing.id.uuidString)
                        .execute()
                }

                let updated = BranchWithGeo(
                    id: existing.id,
                    name: trimmedName,
                    tz: tz,
                    address: addressValue,
                    radiusM: radiusM,
                    lat: lat,
                    lng: lng,
                    defaultShiftId: defaultShiftId
                )
                dismiss()
                await onCompletion?(updated)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteBranch() async {
        guard case .edit(let existing) = mode else { return }
        isDeleting = true
        defer { isDeleting = false }
        errorMessage = nil

        do {
            try await SupabaseManager.shared.client
                .from("branches")
                .delete()
                .eq("id", value: existing.id.uuidString)
                .execute()
            dismiss()
            await onCompletion?(nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadEmployeeCount(branchId: UUID) async {
        do {
            let response = try await SupabaseManager.shared.client
                .from("profiles")
                .select("id", head: true, count: .exact)
                .eq("branch_id", value: branchId.uuidString)
                .execute()
            assignedEmployeeCount = response.count ?? 0
        } catch {
            // Non-fatal: the confirmation dialog just falls back to "0".
            assignedEmployeeCount = 0
        }
    }

    private func loadShifts(branchId: UUID) async {
        do {
            shifts = try await SupabaseManager.shared.client
                .from("shifts")
                .select("id, name, start_local, end_local")
                .eq("branch_id", value: branchId.uuidString)
                .order("start_local")
                .execute()
                .value
        } catch {
            shifts = []
        }
    }

    private func useCurrentLocation() async {
        isFetchingLocation = true
        defer { isFetchingLocation = false }
        do {
            let loc = try await locationService.requestLocation()
            lat = loc.coordinate.latitude
            lng = loc.coordinate.longitude
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: loc.coordinate,
                    latitudinalMeters: max(300, Double(radiusM) * 6),
                    longitudinalMeters: max(300, Double(radiusM) * 6)
                )
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - RPC param DTOs

/// Matches `.rpc("create_branch", params: ...)` — the Supabase SDK encodes
/// a Codable struct straight into the JSON-RPC body, so the property names
/// must match the SQL arg names (we use `p_*` so there's no snake-case
/// ambiguity and no CodingKeys needed).
private struct CreateBranchParams: Encodable, Sendable {
    let p_name: String
    let p_tz: String
    let p_address: String?
    let p_lat: Double
    let p_lng: Double
    let p_radius_m: Int
}

private struct UpdateBranchParams: Encodable, Sendable {
    let p_id: UUID
    let p_name: String
    let p_tz: String
    let p_address: String?
    let p_lat: Double
    let p_lng: Double
    let p_radius_m: Int
}

private struct BranchShiftUpdate: Encodable, Sendable {
    let defaultShiftId: UUID?

    enum CodingKeys: String, CodingKey {
        case defaultShiftId = "default_shift_id"
    }
}

// MARK: - Shift row DTO

extension BranchEditorView {
    struct ShiftRow: Codable, Identifiable, Hashable, Sendable {
        let id: UUID
        let name: String?
        let startLocal: String?
        let endLocal: String?

        var label: String {
            let title = (name?.isEmpty == false) ? name! : "Shift"
            let start = startLocal ?? "?"
            let end = endLocal ?? "?"
            return "\(title) (\(start)–\(end))"
        }

        enum CodingKeys: String, CodingKey {
            case id, name
            case startLocal = "start_local"
            case endLocal = "end_local"
        }
    }
}
