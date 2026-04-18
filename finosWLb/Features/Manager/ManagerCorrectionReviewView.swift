import SwiftUI
import OSLog
internal import PostgREST
import Supabase

/// Manager-facing queue for correction requests (`attendance_corrections`).
/// RLS auto-scopes to the manager's branch. Approving an item calls the
/// `review-correction` Edge Function, which inserts the matching
/// `attendance_events` row on the server and returns the updated correction.
struct ManagerCorrectionReviewView: View {
    enum Scope: String, Hashable, CaseIterable {
        case pending, processed

        var label: String {
            switch self {
            case .pending:   "Đang chờ"
            case .processed: "Đã xử lý"
            }
        }
    }

    @State private var requests: [AttendanceCorrection] = []
    @State private var nameCache: [UUID: String] = [:]

    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var scope: Scope = .pending
    @State private var busyIds: Set<UUID> = []
    @State private var actionError: String?
    @State private var rejectingRequest: AttendanceCorrection?
    @State private var selectedRequest: AttendanceCorrection?
    @State private var successTrigger = 0
    @State private var errorTrigger = 0

    var body: some View {
        List {
            Section {
                Picker("Trạng thái", selection: $scope) {
                    ForEach(Scope.allCases, id: \.self) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            ForEach(filtered) { request in
                row(request)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedRequest = request }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if request.status == .pending {
                            Button {
                                Task { await submit(request, newStatus: .approved, note: nil) }
                            } label: {
                                Label("Duyệt", systemImage: "checkmark.seal.fill")
                            }
                            .tint(.green)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if request.status == .pending {
                            Button(role: .destructive) {
                                rejectingRequest = request
                            } label: {
                                Label("Từ chối", systemImage: "xmark.seal.fill")
                            }
                        }
                    }
            }
        }
        .listStyle(.plain)
        .overlay { overlay }
        .navigationTitle("Bổ sung công")
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $selectedRequest) { request in
            detailSheet(for: request)
        }
        .sheet(item: $rejectingRequest) { request in
            rejectSheet(for: request)
                .presentationDetents([.height(260), .medium])
                .presentationDragIndicator(.visible)
        }
        .alert(
            "Không thể cập nhật",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .sensoryFeedback(.success, trigger: successTrigger)
        .sensoryFeedback(.error, trigger: errorTrigger)
    }

    // MARK: - Row

    private func row(_ r: AttendanceCorrection) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 32, height: 32)
                .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(nameCache[r.employeeId] ?? "Đang tải…")
                        .font(.headline)
                    Spacer()
                    statusPill(r.status)
                }
                Text("Bổ sung \(r.targetType.label.lowercased())")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(requestedSummary(r))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(r.reason)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .opacity(busyIds.contains(r.id) ? 0.55 : 1)
        .overlay {
            if busyIds.contains(r.id) {
                ProgressView()
            }
        }
        .allowsHitTesting(!busyIds.contains(r.id))
    }

    private func statusPill(_ status: LeaveStatus) -> some View {
        Text(status.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.tint.opacity(0.15), in: Capsule())
            .foregroundStyle(status.tint)
    }

    // MARK: - Overlay

    @ViewBuilder
    private var overlay: some View {
        if isLoading && requests.isEmpty {
            ProgressView()
        } else if let errorMessage, requests.isEmpty {
            ContentUnavailableView(
                "Không thể tải danh sách",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
        } else if filtered.isEmpty {
            ContentUnavailableView(
                "Không có đơn",
                systemImage: "checkmark.seal",
                description: Text(scope == .pending
                                  ? "Không có đơn bổ sung công đang chờ."
                                  : "Chưa có đơn nào được xử lý.")
            )
        }
    }

    // MARK: - Filtered list

    private var filtered: [AttendanceCorrection] {
        switch scope {
        case .pending:
            return requests.filter { $0.status == .pending }
        case .processed:
            return requests.filter {
                $0.status == .approved || $0.status == .rejected || $0.status == .cancelled
            }
        }
    }

    // MARK: - Detail sheet

    private func detailSheet(for request: AttendanceCorrection) -> some View {
        NavigationStack {
            Form {
                Section("Thông tin đơn") {
                    LabeledContent("Nhân viên", value: nameCache[request.employeeId] ?? "Không rõ")
                    LabeledContent("Loại", value: request.targetType.label)
                    LabeledContent("Ngày", value: request.targetDate)
                    LabeledContent("Giờ yêu cầu", value: formatTime(request.requestedTs))
                    LabeledContent("Trạng thái", value: request.status.label)
                }
                Section("Lý do") {
                    Text(request.reason)
                }
                if request.status == .pending {
                    Section {
                        Button {
                            let id = request.id
                            selectedRequest = nil
                            Task { await submit(byId: id, newStatus: .approved, note: nil) }
                        } label: {
                            Label("Duyệt", systemImage: "checkmark.seal.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)

                        Button(role: .destructive) {
                            selectedRequest = nil
                            rejectingRequest = request
                        } label: {
                            Label("Từ chối", systemImage: "xmark.seal.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                } else if let note = request.reviewNote, !note.isEmpty {
                    Section("Ghi chú duyệt") {
                        Text(note)
                    }
                }
            }
            .navigationTitle("Chi tiết đơn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { selectedRequest = nil }
                }
            }
        }
    }

    private func rejectSheet(for request: AttendanceCorrection) -> some View {
        RejectCorrectionSheet(
            request: request,
            employeeName: nameCache[request.employeeId] ?? "Không rõ"
        ) { note in
            rejectingRequest = nil
            await submit(request, newStatus: .rejected, note: note.isEmpty ? nil : note)
        } onCancel: {
            rejectingRequest = nil
        }
    }

    // MARK: - Network

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [AttendanceCorrection] = try await SupabaseManager.shared.client
                .from("attendance_corrections")
                .select(AttendanceCorrection.selectColumns)
                .order("created_at", ascending: false)
                .execute()
                .value
            requests = rows
            await refreshNameCache(for: rows)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshNameCache(for requests: [AttendanceCorrection]) async {
        let missing = Set(requests.map(\.employeeId)).subtracting(nameCache.keys)
        guard !missing.isEmpty else { return }
        struct ProfileRow: Decodable { let id: UUID; let full_name: String }
        do {
            let rows: [ProfileRow] = try await SupabaseManager.shared.client
                .from("profiles")
                .select("id, full_name")
                .in("id", values: Array(missing))
                .execute()
                .value
            for row in rows { nameCache[row.id] = row.full_name }
        } catch {
            // Names are a nicety — don't block.
        }
    }

    private func submit(byId id: UUID, newStatus: LeaveStatus, note: String?) async {
        guard let request = requests.first(where: { $0.id == id }) else { return }
        await submit(request, newStatus: newStatus, note: note)
    }

    private func submit(
        _ request: AttendanceCorrection,
        newStatus: LeaveStatus,
        note: String?
    ) async {
        guard newStatus == .approved || newStatus == .rejected else { return }
        AppLog.ui.info("review-correction submit \(newStatus.rawValue, privacy: .public) for \(request.id.uuidString, privacy: .public)")

        busyIds.insert(request.id)
        defer { busyIds.remove(request.id) }

        let params = ReviewCorrectionRPCParams(
            p_request_id: request.id,
            p_new_status: newStatus.rawValue,
            p_note: note
        )
        do {
            let response: ReviewCorrectionResponse = try await SupabaseManager.shared.client
                .rpc("review_correction_rpc", params: params)
                .execute()
                .value
            if let idx = requests.firstIndex(where: { $0.id == response.correction.id }) {
                requests[idx] = response.correction
            }
            successTrigger &+= 1
        } catch let error as PostgrestError {
            AppLog.ui.error("review_correction_rpc failed: \(error.message, privacy: .public)")
            actionError = error.message
            errorTrigger &+= 1
        } catch {
            actionError = error.localizedDescription
            errorTrigger &+= 1
        }
    }

    // MARK: - Helpers

    private func requestedSummary(_ r: AttendanceCorrection) -> String {
        "\(r.targetDate) lúc \(formatTime(r.requestedTs))"
    }

    private func formatTime(_ iso: String) -> String {
        let formatters: [ISO8601DateFormatter] = [.supabase, ISO8601DateFormatter()]
        for f in formatters {
            if let date = f.date(from: iso) {
                return date.formatted(date: .omitted, time: .shortened)
            }
        }
        return iso
    }
}

// MARK: - Reject sheet

private struct RejectCorrectionSheet: View {
    let request: AttendanceCorrection
    let employeeName: String
    let onConfirm: @MainActor (String) async -> Void
    let onCancel: () -> Void

    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Từ chối đơn") {
                    LabeledContent("Nhân viên", value: employeeName)
                    LabeledContent("Ngày", value: request.targetDate)
                }
                Section("Ghi chú (tùy chọn)") {
                    TextField("Lý do từ chối — hiển thị cho nhân viên",
                              text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Từ chối đơn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Từ chối") {
                        let captured = note
                        Task { await onConfirm(captured) }
                    }
                    .tint(.red)
                }
            }
        }
    }
}
