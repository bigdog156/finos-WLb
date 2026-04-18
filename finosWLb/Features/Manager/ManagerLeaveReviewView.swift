import SwiftUI
import Supabase

/// Manager-facing leave review queue. RLS auto-scopes `leave_requests` to the
/// manager's branch. The top picker toggles between pending and processed
/// (approved + rejected + cancelled) requests.
struct ManagerLeaveReviewView: View {
    enum Scope: String, Hashable, CaseIterable {
        case pending
        case processed

        var label: String {
            switch self {
            case .pending:   "Đang chờ"
            case .processed: "Đã xử lý"
            }
        }
    }

    @State private var requests: [LeaveRequest] = []
    @State private var nameCache: [UUID: String] = [:]

    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var scope: Scope = .pending

    // Per-row busy flag so the swipe's spinner is scoped.
    @State private var busyIds: Set<UUID> = []

    // Presentation state for the "Reject with note" flow (from swipe).
    @State private var rejectingRequest: LeaveRequest?

    // Presentation state for tap-to-open detail sheet.
    @State private var selectedRequest: LeaveRequest?

    // Inline alert for action failures — list stays on screen.
    @State private var actionError: String?

    // Haptic triggers.
    @State private var successTrigger = 0
    @State private var errorTrigger = 0

    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

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

            ForEach(filteredRequests) { request in
                row(request)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedRequest = request
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if request.status == .pending {
                            Button {
                                Task { await submit(request: request,
                                                    newStatus: .approved,
                                                    note: nil) }
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
        .navigationTitle("Đơn nghỉ phép")
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $selectedRequest) { request in
            LeaveReviewDetailSheet(
                request: request,
                employeeName: nameCache[request.employeeId] ?? "Không rõ",
                isBusy: busyIds.contains(request.id)
            ) { decision, note in
                selectedRequest = nil
                await submit(request: request, newStatus: decision, note: note)
            } onCancel: {
                selectedRequest = nil
            }
        }
        .sheet(item: $rejectingRequest) { request in
            RejectNoteSheet(
                request: request,
                employeeName: nameCache[request.employeeId] ?? "Không rõ"
            ) { note in
                rejectingRequest = nil
                await submit(request: request,
                             newStatus: .rejected,
                             note: note.isEmpty ? nil : note)
            } onCancel: {
                rejectingRequest = nil
            }
            .presentationDetents([.height(260), .medium])
            .presentationDragIndicator(.visible)
        }
        .alert(
            "Không thể cập nhật đơn",
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

    private func row(_ request: LeaveRequest) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: request.kind.systemImage)
                .font(.title3)
                .foregroundStyle(request.kind.tint)
                .frame(width: 32, height: 32)
                .background(request.kind.tint.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(nameCache[request.employeeId] ?? "Đang tải…")
                        .font(.headline)
                    Spacer()
                    LeaveStatusPill(status: request.status)
                }

                Text(request.kind.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(dateRangeSummary(request))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let reason = request.reason?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !reason.isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(busyIds.contains(request.id) ? 0.55 : 1)
        .overlay {
            if busyIds.contains(request.id) {
                ProgressView()
            }
        }
        .allowsHitTesting(!busyIds.contains(request.id))
    }

    // MARK: - Overlay

    @ViewBuilder
    private var overlay: some View {
        if isLoading && requests.isEmpty {
            ProgressView()
        } else if let errorMessage, requests.isEmpty {
            ContentUnavailableView(
                "Không thể tải đơn nghỉ",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
        } else if filteredRequests.isEmpty {
            ContentUnavailableView(
                "Không có đơn cần duyệt",
                systemImage: "checkmark.seal",
                description: Text(scope == .pending
                                  ? "Không có đơn nghỉ đang chờ duyệt."
                                  : "Chưa có đơn nào được xử lý.")
            )
        }
    }

    // MARK: - Derived

    private var filteredRequests: [LeaveRequest] {
        switch scope {
        case .pending:
            return requests.filter { $0.status == .pending }
        case .processed:
            return requests.filter {
                $0.status == .approved
                    || $0.status == .rejected
                    || $0.status == .cancelled
            }
        }
    }

    private func dateRangeSummary(_ request: LeaveRequest) -> String {
        let start = LeaveRequest.dateFormatter.date(from: request.startDate)
        let end = LeaveRequest.dateFormatter.date(from: request.endDate)
        let startStr = start.map(Self.displayDateFormatter.string(from:)) ?? request.startDate
        let endStr = end.map(Self.displayDateFormatter.string(from:)) ?? request.endDate
        let days = request.durationDays
        if startStr == endStr {
            return "\(startStr) (\(days) ngày)"
        }
        return "\(startStr) – \(endStr) (\(days) ngày)"
    }

    // MARK: - Network

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched: [LeaveRequest] = try await SupabaseManager.shared.client
                .from("leave_requests")
                .select(LeaveRequest.selectColumns)
                .order("created_at", ascending: false)
                .execute()
                .value
            requests = fetched
            await refreshNameCache(for: fetched)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshNameCache(for requests: [LeaveRequest]) async {
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
            // Names are a nicety — don't block on lookup failure.
        }
    }

    private func submit(
        request: LeaveRequest,
        newStatus: LeaveStatus,
        note: String?
    ) async {
        guard newStatus == .approved || newStatus == .rejected else { return }

        busyIds.insert(request.id)
        defer { busyIds.remove(request.id) }

        let body = ReviewLeaveBody(
            requestId: request.id,
            newStatus: newStatus.rawValue,
            note: note
        )
        do {
            let response: ReviewLeaveResponse = try await SupabaseManager.shared.client
                .functions
                .invoke("review-leave", options: FunctionInvokeOptions(body: body))
            if let idx = requests.firstIndex(where: { $0.id == response.leave.id }) {
                requests[idx] = response.leave
            }
            successTrigger &+= 1
        } catch FunctionsError.httpError(let code, let data) {
            actionError = decodeFunctionError(data) ?? "HTTP \(code)"
            errorTrigger &+= 1
        } catch {
            actionError = error.localizedDescription
            errorTrigger &+= 1
        }
    }

    private func decodeFunctionError(_ data: Data) -> String? {
        struct Err: Decodable { let error: String?; let detail: String? }
        let decoded = try? JSONDecoder().decode(Err.self, from: data)
        if let code = decoded?.error {
            if let detail = decoded?.detail, !detail.isEmpty {
                return "\(code) (\(detail))"
            }
            return code
        }
        return nil
    }
}

// MARK: - Status pill

private struct LeaveStatusPill: View {
    let status: LeaveStatus

    var body: some View {
        Label(status.label, systemImage: status.systemImage)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.tint.opacity(0.15),
                        in: Capsule())
            .foregroundStyle(status.tint)
    }
}

// MARK: - Detail sheet (tap-to-open)

private struct LeaveReviewDetailSheet: View {
    let request: LeaveRequest
    let employeeName: String
    let isBusy: Bool
    let onDecide: @MainActor (LeaveStatus, String?) async -> Void
    let onCancel: () -> Void

    @State private var note: String = ""

    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section("Thông tin đơn") {
                    LabeledContent("Nhân viên", value: employeeName)
                    LabeledContent("Loại nghỉ", value: request.kind.label)
                    LabeledContent("Bắt đầu", value: formatDate(request.startDate))
                    LabeledContent("Kết thúc", value: formatDate(request.endDate))
                    LabeledContent("Số ngày", value: "\(request.durationDays)")
                    LabeledContent("Trạng thái", value: request.status.label)
                }

                if let reason = request.reason?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !reason.isEmpty {
                    Section("Lý do xin nghỉ") {
                        Text(reason)
                    }
                }

                if request.status == .pending {
                    Section("Ghi chú (tùy chọn)") {
                        TextField(
                            "Ví dụ: đã xác nhận với phòng ban",
                            text: $note,
                            axis: .vertical
                        )
                        .lineLimit(2...5)
                    }
                } else if let reviewNote = request.reviewNote,
                          !reviewNote.isEmpty {
                    Section("Ghi chú duyệt") {
                        Text(reviewNote)
                    }
                }
            }
            .navigationTitle("Chi tiết đơn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng", action: onCancel)
                        .disabled(isBusy)
                }
                if request.status == .pending {
                    ToolbarItem(placement: .bottomBar) {
                        HStack(spacing: 12) {
                            Button(role: .destructive) {
                                let captured = note
                                Task { await onDecide(.rejected,
                                                      captured.isEmpty ? nil : captured) }
                            } label: {
                                Text("Từ chối")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .disabled(isBusy)

                            Button {
                                let captured = note
                                Task { await onDecide(.approved,
                                                      captured.isEmpty ? nil : captured) }
                            } label: {
                                Text("Duyệt")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .disabled(isBusy)
                        }
                    }
                }
            }
        }
    }

    private func formatDate(_ yyyyMMdd: String) -> String {
        guard let d = LeaveRequest.dateFormatter.date(from: yyyyMMdd) else {
            return yyyyMMdd
        }
        return Self.displayDateFormatter.string(from: d)
    }
}

// MARK: - Reject-with-note sheet (from swipe)

private struct RejectNoteSheet: View {
    let request: LeaveRequest
    let employeeName: String
    let onConfirm: @MainActor (String) async -> Void
    let onCancel: () -> Void

    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Từ chối đơn") {
                    LabeledContent("Nhân viên", value: employeeName)
                    LabeledContent("Loại", value: request.kind.label)
                }
                Section("Ghi chú (tùy chọn)") {
                    TextField(
                        "Lý do từ chối — hiển thị cho nhân viên",
                        text: $note,
                        axis: .vertical
                    )
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

#Preview {
    NavigationStack { ManagerLeaveReviewView() }
}
