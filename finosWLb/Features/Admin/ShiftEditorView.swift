import SwiftUI
internal import PostgREST
import Supabase

/// Create / edit form for a single shift. Pushed from `ShiftsManagementView`.
/// On save/cancel the `onFinish` closure fires so the caller can reload.
struct ShiftEditorView: View {
    enum Mode: Hashable {
        case create
        case edit(Shift)

        var existing: Shift? {
            if case .edit(let s) = self { return s }
            return nil
        }
    }

    let mode: Mode
    let branchId: UUID
    let onFinish: () async -> Void

    // MARK: - Form state
    @State private var name: String
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var graceMin: Int
    @State private var isDefault: Bool
    @State private var selectedDays: Set<Int>

    // UI
    @State private var isSaving = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    init(mode: Mode, branchId: UUID, onFinish: @escaping () async -> Void) {
        self.mode = mode
        self.branchId = branchId
        self.onFinish = onFinish

        switch mode {
        case .create:
            _name = State(initialValue: "Ca sáng")
            _startTime = State(initialValue: Self.time(hour: 8, minute: 0))
            _endTime = State(initialValue: Self.time(hour: 17, minute: 0))
            _graceMin = State(initialValue: 15)
            _isDefault = State(initialValue: false)
            _selectedDays = State(initialValue: [1, 2, 3, 4, 5]) // Mon–Fri
        case .edit(let shift):
            _name = State(initialValue: shift.name)
            _startTime = State(initialValue: Shift.time(from: shift.startLocal) ?? Self.time(hour: 8, minute: 0))
            _endTime = State(initialValue: Shift.time(from: shift.endLocal) ?? Self.time(hour: 17, minute: 0))
            _graceMin = State(initialValue: shift.graceMin)
            _isDefault = State(initialValue: shift.isDefault)
            _selectedDays = State(initialValue: Set(shift.daysOfWeek))
        }
    }

    var body: some View {
        Form {
            Section("Thông tin ca") {
                TextField("Tên ca (VD: Ca sáng)", text: $name)
                    .textInputAutocapitalization(.sentences)
            }

            Section("Giờ làm việc") {
                DatePicker("Bắt đầu", selection: $startTime, displayedComponents: .hourAndMinute)
                DatePicker("Kết thúc", selection: $endTime, displayedComponents: .hourAndMinute)
                HStack {
                    Text("Cho phép trễ")
                    Spacer()
                    Stepper(
                        "\(graceMin) phút",
                        value: $graceMin,
                        in: 0...60,
                        step: 5
                    )
                    .fixedSize()
                }
            }

            Section {
                weekdayGrid
                presetRow
            } header: {
                Text("Ngày áp dụng")
            } footer: {
                Text("Áp dụng cho: \(Array(selectedDays).sorted().weekdaySummary)")
                    .font(.footnote)
            }

            Section("Đặt làm mặc định") {
                Toggle(isOn: $isDefault) {
                    Label {
                        Text("Ca mặc định của chi nhánh")
                    } icon: {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                    }
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
        .navigationTitle(mode.existing == nil ? "Thêm ca" : "Sửa ca")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Hủy") {
                    Task { await onFinish(); dismiss() }
                }
                .disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving { ProgressView() }
                    else { Text("Lưu").fontWeight(.semibold) }
                }
                .disabled(isSaving || !isValid)
            }
        }
    }

    // MARK: - Weekday grid

    private var weekdayGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 54), spacing: 8)]
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Weekday.allCases) { day in
                Button {
                    toggle(day)
                } label: {
                    Text(day.shortLabel)
                        .font(.callout.weight(.semibold))
                        .frame(width: 44, height: 36)
                        .foregroundStyle(selectedDays.contains(day.rawValue) ? Color.white : Color.primary)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selectedDays.contains(day.rawValue)
                                      ? Color.accentColor
                                      : Color(.secondarySystemGroupedBackground))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(day.fullLabel). \(selectedDays.contains(day.rawValue) ? "Đã chọn" : "Chưa chọn")")
            }
        }
        .padding(.vertical, 6)
    }

    private var presetRow: some View {
        HStack(spacing: 8) {
            presetButton(label: "T2–T6", days: [1,2,3,4,5])
            presetButton(label: "T2–T7", days: [1,2,3,4,5,6])
            presetButton(label: "Cuối tuần", days: [6,7])
            presetButton(label: "Hàng ngày", days: [1,2,3,4,5,6,7])
        }
    }

    private func presetButton(label: String, days: Set<Int>) -> some View {
        Button(label) {
            selectedDays = days
        }
        .font(.caption.weight(.medium))
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Derived

    private var isValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !selectedDays.isEmpty else { return false }
        // End must be after start (same-day shifts only for now).
        return endTime > startTime
    }

    // MARK: - Actions

    private func toggle(_ day: Weekday) {
        if selectedDays.contains(day.rawValue) {
            selectedDays.remove(day.rawValue)
        } else {
            selectedDays.insert(day.rawValue)
        }
    }

    private func save() async {
        guard isValid, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = Shift.timeString(from: startTime)
        let end = Shift.timeString(from: endTime)
        let days = Array(selectedDays).sorted()
        let client = SupabaseManager.shared.client

        do {
            switch mode {
            case .create:
                let payload = ShiftInsertPayload(
                    branchId: branchId,
                    name: trimmedName,
                    startLocal: start,
                    endLocal: end,
                    graceMin: graceMin,
                    isDefault: isDefault,
                    daysOfWeek: days
                )
                let inserted: [Shift] = try await client
                    .from("shifts")
                    .insert(payload)
                    .select(Shift.selectColumns)
                    .execute()
                    .value
                if isDefault, let newId = inserted.first?.id {
                    try await applyDefault(newId, otherExcluded: newId)
                }

            case .edit(let existing):
                let payload = ShiftUpdatePayload(
                    name: trimmedName,
                    startLocal: start,
                    endLocal: end,
                    graceMin: graceMin,
                    daysOfWeek: days
                )
                try await client
                    .from("shifts")
                    .update(payload)
                    .eq("id", value: existing.id.uuidString)
                    .execute()

                // Apply default toggle separately so we can cascade to branches.
                if isDefault != existing.isDefault {
                    if isDefault {
                        try await applyDefault(existing.id, otherExcluded: existing.id)
                    } else {
                        try await client
                            .from("shifts")
                            .update(IsDefaultOnly(isDefault: false))
                            .eq("id", value: existing.id.uuidString)
                            .execute()
                        try await client
                            .from("branches")
                            .update(BranchDefaultPatch(defaultShiftId: nil))
                            .eq("id", value: branchId.uuidString)
                            .eq("default_shift_id", value: existing.id.uuidString)
                            .execute()
                    }
                }
            }

            await onFinish()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Sets `is_default = true` on the chosen shift, clears it on every other
    /// shift for the branch, and mirrors the id onto `branches.default_shift_id`.
    private func applyDefault(_ chosenId: UUID, otherExcluded: UUID) async throws {
        let client = SupabaseManager.shared.client

        try await client
            .from("shifts")
            .update(IsDefaultOnly(isDefault: false))
            .eq("branch_id", value: branchId.uuidString)
            .neq("id", value: otherExcluded.uuidString)
            .execute()

        try await client
            .from("shifts")
            .update(IsDefaultOnly(isDefault: true))
            .eq("id", value: chosenId.uuidString)
            .execute()

        try await client
            .from("branches")
            .update(BranchDefaultPatch(defaultShiftId: chosenId))
            .eq("id", value: branchId.uuidString)
            .execute()
    }

    // MARK: - Helpers

    private static func time(hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps) ?? Date()
    }
}

// MARK: - Small DTOs

private struct IsDefaultOnly: Encodable {
    let isDefault: Bool
    enum CodingKeys: String, CodingKey { case isDefault = "is_default" }
}

private struct BranchDefaultPatch: Encodable {
    let defaultShiftId: UUID?
    enum CodingKeys: String, CodingKey { case defaultShiftId = "default_shift_id" }
}
