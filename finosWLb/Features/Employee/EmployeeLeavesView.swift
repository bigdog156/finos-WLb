import SwiftUI
internal import PostgREST
import Supabase

/// Employee-side "Nghỉ phép" screen.
///
/// Lists the signed-in employee's own leave requests split into two sections:
/// "Chờ duyệt" (pending) first, then "Đã xử lý" (approved / rejected /
/// cancelled) ordered by `createdAt` desc. Pending rows expose a destructive
/// "Hủy đơn" swipe action that UPDATEs the row's status to `cancelled` (RLS
/// allows employees to update their own pending rows).
///
/// New requests are created via `NewLeaveRequestSheet` presented from the
/// toolbar "+" button.
struct EmployeeLeavesView: View {
    let profile: Profile

    @State private var requests: [LeaveRequest] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingNewSheet = false
    @State private var cancellingIds: Set<UUID> = []
    @State private var cancelError: String?

    var body: some View {
        List {
            if !pending.isEmpty {
                Section("Chờ duyệt") {
                    ForEach(pending) { row in
                        LeaveRow(request: row)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Task { await cancel(request: row) }
                                } label: {
                                    Label("Hủy đơn", systemImage: "slash.circle")
                                }
                                .disabled(cancellingIds.contains(row.id))
                            }
                    }
                }
            }

            if !processed.isEmpty {
                Section("Đã xử lý") {
                    ForEach(processed) { row in
                        LeaveRow(request: row)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .overlay {
            if isLoading && requests.isEmpty {
                ProgressView()
            } else if requests.isEmpty, let errorMessage {
                ContentUnavailableView {
                    Label("Không thể tải đơn nghỉ", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Thử lại") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
            } else if requests.isEmpty {
                ContentUnavailableView {
                    Label("Chưa có đơn nghỉ phép", systemImage: "sun.max")
                } description: {
                    Text("Gửi đơn khi bạn cần nghỉ phép năm, nghỉ ốm hoặc các lý do khác.")
                } actions: {
                    Button {
                        showingNewSheet = true
                    } label: {
                        Label("Tạo đơn mới", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Nghỉ phép")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewSheet = true
                } label: {
                    Label("Tạo đơn", systemImage: "plus")
                }
                .accessibilityLabel("Tạo đơn nghỉ mới")
            }
        }
        .sheet(isPresented: $showingNewSheet) {
            NewLeaveRequestSheet(profile: profile) {
                await load()
            }
        }
        .alert("Không thể hủy đơn",
               isPresented: Binding(
                    get: { cancelError != nil },
                    set: { if !$0 { cancelError = nil } })) {
            Button("Đóng", role: .cancel) { cancelError = nil }
        } message: {
            Text(cancelError ?? "")
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Derived

    private var pending: [LeaveRequest] {
        requests
            .filter { $0.status == .pending }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var processed: [LeaveRequest] {
        requests
            .filter { $0.status != .pending }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Networking

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [LeaveRequest] = try await SupabaseManager.shared.client
                .from("leave_requests")
                .select(LeaveRequest.selectColumns)
                .eq("employee_id", value: profile.id.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
            requests = rows
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancel(request: LeaveRequest) async {
        guard request.status == .pending else { return }
        cancellingIds.insert(request.id)
        defer { cancellingIds.remove(request.id) }
        do {
            try await SupabaseManager.shared.client
                .from("leave_requests")
                .update(LeaveRequestCancelPayload())
                .eq("id", value: request.id.uuidString)
                .eq("status", value: LeaveStatus.pending.rawValue) // belt-and-suspenders
                .execute()
            await load()
        } catch {
            cancelError = error.localizedDescription
        }
    }
}

// MARK: - Row

private struct LeaveRow: View {
    let request: LeaveRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label {
                    Text(request.kind.label)
                        .font(.headline)
                } icon: {
                    Image(systemName: request.kind.systemImage)
                        .foregroundStyle(request.kind.tint)
                }

                Spacer()

                StatusPill(status: request.status)
            }

            Text(dateRangeText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let reason = request.reason?.trimmingCharacters(in: .whitespacesAndNewlines),
               !reason.isEmpty {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            if let note = request.reviewNote?.trimmingCharacters(in: .whitespacesAndNewlines),
               !note.isEmpty {
                Text("Ghi chú duyệt: \(note)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var dateRangeText: String {
        let start = LeaveRequest.dateFormatter.date(from: request.startDate)
        let end = LeaveRequest.dateFormatter.date(from: request.endDate)
        guard let start, let end else {
            return "\(request.startDate) – \(request.endDate) (\(request.durationDays) ngày)"
        }
        let dayMonth = DateFormatter()
        dayMonth.locale = Locale(identifier: "vi_VN")
        dayMonth.dateFormat = "dd/MM"

        let dayMonthYear = DateFormatter()
        dayMonthYear.locale = Locale(identifier: "vi_VN")
        dayMonthYear.dateFormat = "dd/MM/yyyy"

        if request.startDate == request.endDate {
            return "\(dayMonthYear.string(from: start)) (\(request.durationDays) ngày)"
        }
        return "\(dayMonth.string(from: start)) – \(dayMonthYear.string(from: end)) (\(request.durationDays) ngày)"
    }
}

// MARK: - Status pill

private struct StatusPill: View {
    let status: LeaveStatus

    var body: some View {
        Label(displayLabel, systemImage: status.systemImage)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.tint.opacity(0.15), in: Capsule())
            .foregroundStyle(status.tint)
            .accessibilityLabel(displayLabel)
    }

    // Task copy overrides the enum's own `.label` for these two states.
    private var displayLabel: String {
        switch status {
        case .pending:   return "Chờ duyệt"
        case .approved:  return "Đã duyệt"
        case .rejected:  return "Từ chối"
        case .cancelled: return "Đã hủy"
        }
    }
}

// MARK: - New request sheet

struct NewLeaveRequestSheet: View {
    let profile: Profile
    /// Called after a successful insert so the parent can refresh.
    let onSubmitted: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var kind: LeaveKind = .annual
    @State private var startDate: Date = .now
    @State private var endDate: Date = .now
    @State private var reason: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Loại nghỉ") {
                    Picker("Loại nghỉ", selection: $kind) {
                        ForEach(LeaveKind.allCases) { k in
                            Label {
                                Text(k.label)
                            } icon: {
                                Image(systemName: k.systemImage)
                                    .foregroundStyle(k.tint)
                            }
                            .tag(k)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                Section("Thời gian") {
                    DatePicker("Từ ngày",
                               selection: $startDate,
                               displayedComponents: .date)
                        .onChange(of: startDate) { _, newValue in
                            if endDate < newValue {
                                endDate = newValue
                            }
                        }

                    DatePicker("Đến ngày",
                               selection: $endDate,
                               in: startDate...,
                               displayedComponents: .date)

                    HStack {
                        Text("Tổng")
                        Spacer()
                        Text("\(durationDays) ngày")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Section("Lý do") {
                    TextField(
                        "Ví dụ: Về quê có việc gia đình",
                        text: $reason,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Đơn nghỉ mới")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("Gửi")
                        }
                    }
                    .disabled(isSubmitting)
                }
            }
            .interactiveDismissDisabled(isSubmitting)
        }
    }

    // MARK: - Derived

    private var durationDays: Int {
        let calendar = Calendar.current
        let s = calendar.startOfDay(for: startDate)
        let e = calendar.startOfDay(for: endDate)
        let days = calendar.dateComponents([.day], from: s, to: e).day ?? 0
        return max(1, days + 1)
    }

    // MARK: - Submit

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }

        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = LeaveRequestInsert(
            employeeId: profile.id,
            kind: kind.rawValue,
            startDate: Self.localDateString(from: startDate),
            endDate: Self.localDateString(from: endDate),
            reason: trimmed.isEmpty ? nil : trimmed
        )

        do {
            try await SupabaseManager.shared.client
                .from("leave_requests")
                .insert(payload)
                .execute()
            await onSubmitted()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Formats a `Date` (typically local-midnight from a date-only picker) as
    /// `yyyy-MM-dd` in the *user's* timezone. We deliberately do NOT use
    /// `LeaveRequest.format(_:)` — it forces UTC, which shifts the date in
    /// non-UTC locales (e.g. ICT = UTC+7 → picker's local midnight formats as
    /// the previous calendar day).
    private static func localDateString(from date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d",
                      comps.year ?? 1970,
                      comps.month ?? 1,
                      comps.day ?? 1)
    }
}

// MARK: - Preview

#Preview("Empty") {
    NavigationStack {
        EmployeeLeavesView(profile: Profile(
            id: UUID(),
            fullName: "Nguyễn Văn A",
            role: .employee,
            branchId: nil,
            deptId: nil,
            active: true
        ))
    }
}
