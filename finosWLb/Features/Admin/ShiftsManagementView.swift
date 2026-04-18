import SwiftUI
internal import PostgREST
import Supabase

/// Admin screen for managing a branch's shifts: list, add, edit, delete, and
/// pick which one is the default. Pushed from `BranchEditorView` in edit mode.
struct ShiftsManagementView: View {
    let branch: BranchWithGeo
    var onChange: (() async -> Void)? = nil

    @State private var shifts: [Shift] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var presentedEditor: ShiftEditorPresentation?
    @State private var busyId: UUID?

    enum ShiftEditorPresentation: Identifiable {
        case create
        case edit(Shift)
        var id: String {
            switch self {
            case .create: "create"
            case .edit(let s): s.id.uuidString
            }
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(shifts) { shift in
                    Button {
                        presentedEditor = .edit(shift)
                    } label: {
                        row(shift)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await delete(shift) }
                        } label: {
                            Label("Xóa", systemImage: "trash")
                        }
                        Button {
                            Task { await setDefault(shift) }
                        } label: {
                            Label(shift.isDefault ? "Bỏ mặc định" : "Đặt mặc định",
                                  systemImage: "star")
                        }
                        .tint(.yellow)
                    }
                }
            } footer: {
                Text("Ca mặc định (⭐) được dùng để xác định giờ đi làm và đi trễ.")
                    .font(.footnote)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
        .overlay { overlay }
        .navigationTitle("Ca làm của \(branch.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presentedEditor = .create
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Thêm ca")
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $presentedEditor) { presentation in
            NavigationStack {
                ShiftEditorView(
                    mode: editorMode(for: presentation),
                    branchId: branch.id
                ) {
                    await load()
                    await onChange?()
                }
            }
        }
    }

    // MARK: - Row

    private func row(_ shift: Shift) -> some View {
        HStack(spacing: 12) {
            Image(systemName: shift.isDefault ? "star.fill" : "clock")
                .foregroundStyle(shift.isDefault ? Color.yellow : Color.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(shift.name).font(.headline)
                HStack(spacing: 8) {
                    Label(timeRange(shift), systemImage: "clock")
                        .labelStyle(.titleAndIcon)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Label(shift.daysOfWeek.weekdaySummary, systemImage: "calendar")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if shift.graceMin > 0 {
                    Text("Cho phép trễ \(shift.graceMin) phút")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if busyId == shift.id {
                ProgressView()
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Overlay

    @ViewBuilder
    private var overlay: some View {
        if isLoading && shifts.isEmpty {
            ProgressView()
        } else if shifts.isEmpty {
            ContentUnavailableView {
                Label("Chưa có ca làm", systemImage: "clock.badge.questionmark")
            } description: {
                Text("Thêm ca để nhân viên có lịch làm việc.")
            } actions: {
                Button("Thêm ca") { presentedEditor = .create }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Helpers

    private func editorMode(for presentation: ShiftEditorPresentation) -> ShiftEditorView.Mode {
        switch presentation {
        case .create:        .create
        case .edit(let s):   .edit(s)
        }
    }

    private func timeRange(_ shift: Shift) -> String {
        // Trim seconds for display.
        let start = shift.startLocal.split(separator: ":").prefix(2).joined(separator: ":")
        let end = shift.endLocal.split(separator: ":").prefix(2).joined(separator: ":")
        return "\(start) – \(end)"
    }

    // MARK: - Networking

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            shifts = try await SupabaseManager.shared.client
                .from("shifts")
                .select(Shift.selectColumns)
                .eq("branch_id", value: branch.id.uuidString)
                .order("start_local")
                .execute()
                .value
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ shift: Shift) async {
        busyId = shift.id
        defer { busyId = nil }
        do {
            try await SupabaseManager.shared.client
                .from("shifts")
                .delete()
                .eq("id", value: shift.id.uuidString)
                .execute()
            await load()
            await onChange?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setDefault(_ shift: Shift) async {
        busyId = shift.id
        defer { busyId = nil }
        do {
            // Clear other defaults on this branch.
            try await SupabaseManager.shared.client
                .from("shifts")
                .update(DefaultFlag(isDefault: false))
                .eq("branch_id", value: branch.id.uuidString)
                .neq("id", value: shift.id.uuidString)
                .execute()

            // Flip chosen row.
            try await SupabaseManager.shared.client
                .from("shifts")
                .update(DefaultFlag(isDefault: !shift.isDefault))
                .eq("id", value: shift.id.uuidString)
                .execute()

            // Mirror on branches.default_shift_id so the check-in EF resolves
            // the right shift without a secondary query.
            let branchPayload: BranchDefaultUpdate
            if shift.isDefault {
                branchPayload = BranchDefaultUpdate(defaultShiftId: nil)
            } else {
                branchPayload = BranchDefaultUpdate(defaultShiftId: shift.id)
            }
            try await SupabaseManager.shared.client
                .from("branches")
                .update(branchPayload)
                .eq("id", value: branch.id.uuidString)
                .execute()

            await load()
            await onChange?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Local DTOs

private struct DefaultFlag: Encodable {
    let isDefault: Bool
    enum CodingKeys: String, CodingKey { case isDefault = "is_default" }
}

private struct BranchDefaultUpdate: Encodable {
    let defaultShiftId: UUID?
    enum CodingKeys: String, CodingKey { case defaultShiftId = "default_shift_id" }
}
