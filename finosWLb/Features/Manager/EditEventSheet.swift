import SwiftUI
import Supabase

/// Manager-only sheet for correcting an `attendance_events` row via the
/// `edit-event` Edge Function. The EF writes an `audit_log` entry, so the UI
/// requires a non-empty reason and at least one of status / time to have
/// actually changed before Save is enabled.
struct EditEventSheet: View {
    let event: AttendanceEvent
    let onSaved: @MainActor (AttendanceEvent) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var newStatus: AttendanceEventStatus
    @State private var keepOriginalTime: Bool = true
    @State private var newDate: Date
    @State private var reason: String = ""

    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var successTrigger = 0

    init(
        event: AttendanceEvent,
        onSaved: @escaping @MainActor (AttendanceEvent) async -> Void
    ) {
        self.event = event
        self.onSaved = onSaved
        _newStatus = State(initialValue: event.status)
        // Seed the DatePicker with the event's current server_ts (falling back
        // to now if the ISO parse fails — the toggle-off default hides it).
        let seeded = Self.parseServerTs(event.serverTs) ?? Date()
        _newDate = State(initialValue: seeded)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sự kiện") {
                    LabeledContent("Loại", value: event.type.label)
                    LabeledContent("Thời gian hiện tại",
                                   value: Self.formatForDisplay(event.serverTs))
                    LabeledContent("Trạng thái hiện tại",
                                   value: event.status.label)
                }

                Section("Đổi trạng thái thành") {
                    Picker("Trạng thái mới", selection: $newStatus) {
                        ForEach(AttendanceEventStatus.allCases, id: \.self) { status in
                            Text(status.label).tag(status)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Đổi thời gian") {
                    Toggle("Giữ nguyên thời gian", isOn: $keepOriginalTime)
                    DatePicker(
                        "Thời gian mới",
                        selection: $newDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .disabled(keepOriginalTime)
                }

                Section("Lý do") {
                    TextField(
                        "Bắt buộc — sẽ ghi vào nhật ký kiểm toán",
                        text: $reason,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Sửa sự kiện")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSubmitting)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("Lưu") {
                            Task { await submit() }
                        }
                        .disabled(!canSubmit)
                    }
                }
            }
            .sensoryFeedback(.success, trigger: successTrigger)
        }
    }

    // MARK: - Derived

    private var trimmedReason: String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var statusChanged: Bool {
        newStatus != event.status
    }

    private var timeChanged: Bool {
        !keepOriginalTime
    }

    private var canSubmit: Bool {
        !trimmedReason.isEmpty && (statusChanged || timeChanged)
    }

    // MARK: - Network

    private func submit() async {
        guard canSubmit else { return }

        isSubmitting = true
        defer { isSubmitting = false }

        let statusPayload = statusChanged ? newStatus.rawValue : nil
        let tsPayload = timeChanged
            ? ISO8601DateFormatter.supabase.string(from: newDate)
            : nil

        let body = EditEventBody(
            eventId: event.id,
            newStatus: statusPayload,
            newServerTs: tsPayload,
            reason: trimmedReason
        )

        do {
            let response: EditEventResponse = try await SupabaseManager.shared.client
                .functions
                .invoke("edit-event", options: FunctionInvokeOptions(body: body))

            successTrigger &+= 1
            await onSaved(response.event)
            dismiss()
        } catch FunctionsError.httpError(let code, let data) {
            errorMessage = Self.decodeFunctionError(data) ?? "HTTP \(code)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func decodeFunctionError(_ data: Data) -> String? {
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

    // MARK: - Formatting helpers

    private static func parseServerTs(_ iso: String) -> Date? {
        let formatters: [ISO8601DateFormatter] = [.supabase, ISO8601DateFormatter()]
        for f in formatters {
            if let date = f.date(from: iso) { return date }
        }
        return nil
    }

    private static func formatForDisplay(_ iso: String) -> String {
        guard let date = parseServerTs(iso) else { return iso }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

#Preview {
    EditEventSheet(
        event: AttendanceEvent(
            id: UUID(),
            type: .checkIn,
            serverTs: "2026-04-17T08:31:00.000Z",
            clientTs: "2026-04-17T08:31:00.000Z",
            status: .flagged,
            flaggedReason: "Xa chi nhánh",
            branchId: nil,
            accuracyM: 12,
            note: nil
        ),
        onSaved: { _ in }
    )
}
