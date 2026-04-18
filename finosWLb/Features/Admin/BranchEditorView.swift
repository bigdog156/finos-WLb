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

    // MARK: - Create-mode drafts
    @State private var shiftDrafts: [ShiftDraft] = []
    @State private var wifiDrafts: [WifiDraft] = []

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
            _shiftDrafts = State(initialValue: [ShiftDraft.defaultMorning()])
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
                        Text("Lưu").fontWeight(.semibold)
                    }
                }
                .disabled(!isValid || isSaving)
            }
            if case .create = mode {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Hủy") { dismiss() }
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
            "Xóa chi nhánh?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Xóa", role: .destructive) {
                Task { await deleteBranch() }
            }
            Button("Hủy", role: .cancel) {}
        } message: {
            let count = assignedEmployeeCount ?? 0
            Text("Thao tác này sẽ xóa chi nhánh. \(count) nhân viên thuộc chi nhánh sẽ bị bỏ phân công. Tiếp tục?")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var detailsSection: some View {
        Section("Chi tiết") {
            TextField("Tên", text: $name)
                .textInputAutocapitalization(.words)

            NavigationLink {
                TimezonePickerView(selection: $tz)
            } label: {
                HStack {
                    Text("Múi giờ")
                    Spacer()
                    Text(tz)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            TextField("Địa chỉ (tùy chọn)", text: $address, axis: .vertical)
                .lineLimit(1...3)
        }
    }

    @ViewBuilder
    private var locationSection: some View {
        Section("Vị trí") {
            ZStack {
                Map(position: $cameraPosition) {
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

                Image(systemName: "mappin")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
            .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))

            Text(String(format: "Vĩ độ: %.6f  Kinh độ: %.6f", lat, lng))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Bán kính")
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
                    Label("Dùng vị trí hiện tại của tôi", systemImage: "location")
                    Spacer()
                    if isFetchingLocation { ProgressView() }
                }
            }
            .disabled(isFetchingLocation)
        }
    }

    @ViewBuilder
    private var shiftSection: some View {
        switch mode {
        case .create:
            Section {
                ForEach($shiftDrafts) { $draft in
                    ShiftDraftRow(draft: $draft) {
                        remove(shift: draft.id)
                    } setDefault: {
                        setDefaultShift(draft.id)
                    }
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        let newDraft = ShiftDraft.empty()
                        shiftDrafts.append(newDraft)
                        if shiftDrafts.count == 1 {
                            setDefaultShift(newDraft.id)
                        }
                    }
                } label: {
                    Label("Thêm ca làm", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Ca làm")
            } footer: {
                Text("Ít nhất một ca sẽ được đánh dấu là ca mặc định để tính giờ đi trễ.")
                    .font(.footnote)
            }

        case .edit(let branch):
            Section("Ca làm") {
                if shifts.isEmpty {
                    Text("Chưa có ca làm nào cho chi nhánh này.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Ca mặc định", selection: $defaultShiftId) {
                        Text("Không").tag(UUID?.none)
                        ForEach(shifts) { shift in
                            Text(shift.label).tag(UUID?.some(shift.id))
                        }
                    }
                }

                NavigationLink {
                    ShiftsManagementView(branch: branch) {
                        await loadShifts(branchId: branch.id)
                    }
                } label: {
                    Label("Quản lý ca & giờ làm", systemImage: "clock.arrow.circlepath")
                }
            }
        }
    }

    @ViewBuilder
    private var wifiSection: some View {
        switch mode {
        case .create:
            Section {
                ForEach($wifiDrafts) { $draft in
                    WifiDraftRow(draft: $draft) {
                        remove(wifi: draft.id)
                    }
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        wifiDrafts.append(WifiDraft.empty())
                    }
                } label: {
                    Label("Thêm WiFi (tùy chọn)", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("WiFi cho phép")
            } footer: {
                Text("Thêm địa chỉ BSSID (MAC) của router tại chi nhánh để giảm rủi ro chấm công gian lận.")
                    .font(.footnote)
            }

        case .edit(let branch):
            Section("Danh sách WiFi cho phép") {
                NavigationLink {
                    BranchWifiView(branch: Branch(branch))
                } label: {
                    Label("Mạng đã duyệt", systemImage: "wifi")
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
                            Text("Xóa chi nhánh")
                        }
                        Spacer()
                        if let count = assignedEmployeeCount {
                            Text("\(count) nhân viên")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(isDeleting)
            } header: {
                Text("Vùng nguy hiểm")
            } footer: {
                Text("Nhân viên thuộc chi nhánh này sẽ bị bỏ phân công.")
            }
        }
    }

    // MARK: - Draft helpers

    private func remove(shift id: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            shiftDrafts.removeAll { $0.id == id }
            // If we just removed the default, promote the first remaining shift.
            if !shiftDrafts.contains(where: { $0.isDefault }), let first = shiftDrafts.first {
                setDefaultShift(first.id)
            }
        }
    }

    private func setDefaultShift(_ id: UUID) {
        for idx in shiftDrafts.indices {
            shiftDrafts[idx].isDefault = (shiftDrafts[idx].id == id)
        }
    }

    private func remove(wifi id: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            wifiDrafts.removeAll { $0.id == id }
        }
    }

    // MARK: - Derived

    private var navTitle: String {
        switch mode {
        case .create: return "Chi nhánh mới"
        case .edit(let b): return b.name
        }
    }

    private var radiusM: Int { Int(radiusMDouble.rounded()) }

    private var isValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !tz.isEmpty else { return false }
        guard lat.isFinite, lng.isFinite else { return false }

        if case .create = mode {
            // Shifts are optional, but if present they must all be named and
            // apply to at least one weekday.
            for draft in shiftDrafts {
                let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return false }
                guard !draft.daysOfWeek.isEmpty else { return false }
                guard draft.end > draft.start else { return false }
            }
            // WiFi BSSIDs must be non-empty if the row exists.
            for draft in wifiDrafts {
                let b = draft.bssid.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !b.isEmpty else { return false }
            }
        }
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
                // `create_branch` returns a single-row `table (id uuid)` so
                // PostgREST yields `[{"id": "..."}]` — safest shape to decode.
                let rows: [CreateBranchResult] = try await SupabaseManager.shared.client
                    .rpc("create_branch", params: params)
                    .execute()
                    .value
                guard let newBranchId = rows.first?.id else {
                    errorMessage = "Máy chủ không trả về mã chi nhánh."
                    return
                }

                try await persistDrafts(branchId: newBranchId)

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

    /// Inserts shift and wifi rows for a newly created branch. Called only from
    /// the `.create` path. Partial failures are surfaced as the error message;
    /// the branch row itself is already persisted at this point.
    private func persistDrafts(branchId: UUID) async throws {
        // Shifts: insert first so we have IDs for `default_shift_id`.
        var insertedDefaultShiftId: UUID?
        if !shiftDrafts.isEmpty {
            let rows = shiftDrafts.map { draft in
                ShiftInsert(
                    branchId: branchId,
                    name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    startLocal: Self.timeFormatter.string(from: draft.start),
                    endLocal: Self.timeFormatter.string(from: draft.end),
                    graceMin: draft.graceMin,
                    isDefault: draft.isDefault,
                    daysOfWeek: Array(draft.daysOfWeek).sorted()
                )
            }
            // Postgres does NOT guarantee the RETURNING order matches the
            // input order on a bulk INSERT. Return the `is_default` column
            // alongside `id` so we can pick the right row regardless of
            // order. Only one row is marked default (we enforce this in the
            // draft model) so `first(where:)` lands on the right shift.
            let inserted: [ShiftInsertResponse] = try await SupabaseManager.shared.client
                .from("shifts")
                .insert(rows)
                .select("id, is_default")
                .execute()
                .value

            insertedDefaultShiftId = inserted.first(where: { $0.isDefault })?.id
        }

        // WiFi: branch_id + bssid, optional ssid; drop blanks.
        let wifiRows: [BranchWifiInsert] = wifiDrafts.compactMap { draft -> BranchWifiInsert? in
            let bssid = draft.bssid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !bssid.isEmpty else { return nil }
            let ssid = draft.ssid.trimmingCharacters(in: .whitespacesAndNewlines)
            return BranchWifiInsert(
                branchId: branchId,
                bssid: bssid,
                ssid: ssid.isEmpty ? nil : ssid
            )
        }
        if !wifiRows.isEmpty {
            try await SupabaseManager.shared.client
                .from("branch_wifi")
                .insert(wifiRows)
                .execute()
        }

        // Link the chosen default shift back to the branch.
        if let defaultShiftId = insertedDefaultShiftId {
            let payload = BranchShiftUpdate(defaultShiftId: defaultShiftId)
            try await SupabaseManager.shared.client
                .from("branches")
                .update(payload)
                .eq("id", value: branchId.uuidString)
                .execute()
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

    // MARK: - Time formatter

    /// `HH:mm:ss` matches the `time` Postgres type without fractional seconds.
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

// MARK: - Shift draft

struct ShiftDraft: Identifiable, Hashable {
    let id: UUID
    var name: String
    var start: Date
    var end: Date
    var graceMin: Int
    var isDefault: Bool
    var daysOfWeek: Set<Int>

    static func empty() -> ShiftDraft {
        ShiftDraft(
            id: UUID(),
            name: "",
            start: dateAt(hour: 8, minute: 0),
            end: dateAt(hour: 17, minute: 0),
            graceMin: 15,
            isDefault: false,
            daysOfWeek: [1, 2, 3, 4, 5]
        )
    }

    static func defaultMorning() -> ShiftDraft {
        ShiftDraft(
            id: UUID(),
            name: "Ca sáng",
            start: dateAt(hour: 8, minute: 0),
            end: dateAt(hour: 17, minute: 0),
            graceMin: 15,
            isDefault: true,
            daysOfWeek: [1, 2, 3, 4, 5]
        )
    }

    private static func dateAt(hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps) ?? Date()
    }
}

private struct ShiftDraftRow: View {
    @Binding var draft: ShiftDraft
    let onDelete: () -> Void
    let setDefault: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Tên ca (VD: Ca sáng)", text: $draft.name)
                    .textInputAutocapitalization(.sentences)

                Button {
                    setDefault()
                } label: {
                    Image(systemName: draft.isDefault ? "star.fill" : "star")
                        .foregroundStyle(draft.isDefault ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(draft.isDefault ? "Đã là ca mặc định" : "Đặt làm ca mặc định")

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Xóa ca")
            }

            HStack {
                DatePicker("Bắt đầu", selection: $draft.start, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Text("→").foregroundStyle(.secondary)
                DatePicker("Kết thúc", selection: $draft.end, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Spacer()
                Stepper("Trễ \(draft.graceMin)p", value: $draft.graceMin, in: 0...60, step: 5)
                    .labelsHidden()
                    .accessibilityLabel("Thời gian cho phép trễ, đang là \(draft.graceMin) phút")
                Text("\(draft.graceMin)p trễ")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            WeekdayPicker(selection: $draft.daysOfWeek)
        }
        .padding(.vertical, 4)
    }
}

private struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Weekday.allCases) { day in
                    Button {
                        if selection.contains(day.rawValue) {
                            selection.remove(day.rawValue)
                        } else {
                            selection.insert(day.rawValue)
                        }
                    } label: {
                        Text(day.shortLabel)
                            .font(.caption.weight(.semibold))
                            .frame(width: 34, height: 28)
                            .foregroundStyle(selection.contains(day.rawValue) ? Color.white : Color.primary)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selection.contains(day.rawValue)
                                          ? Color.accentColor
                                          : Color(.tertiarySystemGroupedBackground))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(day.fullLabel)
                }
            }
            Text("Áp dụng: \(Array(selection).sorted().weekdaySummary)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Wifi draft

struct WifiDraft: Identifiable, Hashable {
    let id: UUID
    var bssid: String
    var ssid: String

    static func empty() -> WifiDraft {
        WifiDraft(id: UUID(), bssid: "", ssid: "")
    }
}

private struct WifiDraftRow: View {
    @Binding var draft: WifiDraft
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("BSSID (VD: aa:bb:cc:dd:ee:ff)", text: $draft.bssid)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Xóa WiFi")
            }

            TextField("Tên mạng (tùy chọn)", text: $draft.ssid)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - RPC param DTOs

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

private struct ShiftInsert: Encodable, Sendable {
    let branchId: UUID
    let name: String
    let startLocal: String
    let endLocal: String
    let graceMin: Int
    let isDefault: Bool
    let daysOfWeek: [Int]

    enum CodingKeys: String, CodingKey {
        case branchId = "branch_id"
        case name
        case startLocal = "start_local"
        case endLocal = "end_local"
        case graceMin = "grace_min"
        case isDefault = "is_default"
        case daysOfWeek = "days_of_week"
    }
}

private struct ShiftInsertResponse: Decodable, Sendable {
    let id: UUID
    let isDefault: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case isDefault = "is_default"
    }
}

private struct CreateBranchResult: Decodable, Sendable {
    let id: UUID
}

private struct BranchWifiInsert: Encodable, Sendable {
    let branchId: UUID
    let bssid: String
    let ssid: String?

    enum CodingKeys: String, CodingKey {
        case branchId = "branch_id"
        case bssid, ssid
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
            let title = (name?.isEmpty == false) ? name! : "Ca"
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
