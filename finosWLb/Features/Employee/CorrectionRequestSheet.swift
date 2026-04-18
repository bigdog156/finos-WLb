import SwiftUI
internal import PostgREST
import Supabase

/// Sheet presented from Employee History so a user can request a correction
/// to a missed check-in / check-out. Inserts a row into
/// `attendance_corrections`. Manager approval later materialises an
/// `attendance_events` row via the `review-correction` Edge Function.
struct CorrectionRequestSheet: View {
    let profile: Profile
    /// Invoked after a successful insert so the caller can reload lists.
    let onSubmitted: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var targetType: AttendanceEventType = .checkIn
    @State private var targetDate: Date = Date()
    @State private var requestedTime: Date = Self.defaultTime()
    @State private var reason: String = ""

    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Loại", selection: $targetType) {
                        Text(AttendanceEventType.checkIn.label).tag(AttendanceEventType.checkIn)
                        Text(AttendanceEventType.checkOut.label).tag(AttendanceEventType.checkOut)
                    }

                    DatePicker("Ngày", selection: $targetDate,
                               in: ...Date(), displayedComponents: .date)

                    DatePicker("Giờ thực tế", selection: $requestedTime,
                               displayedComponents: .hourAndMinute)
                } header: {
                    Text("Thông tin bổ sung")
                } footer: {
                    Text("Chọn đúng ngày và giờ bạn đã ở chi nhánh — quản lý sẽ xem xét và duyệt.")
                        .font(.footnote)
                }

                Section {
                    TextField("Ví dụ: Quên chấm công do họp ngoài văn phòng…",
                              text: $reason, axis: .vertical)
                        .lineLimit(3...6)
                        .onChange(of: reason) { _, new in
                            if new.count > 500 { reason = String(new.prefix(500)) }
                        }
                } header: {
                    Text("Lý do (bắt buộc)")
                } footer: {
                    Text("\(reason.count)/500 ký tự")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Bổ sung công")
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
                            Text("Gửi").fontWeight(.semibold)
                        }
                    }
                    .disabled(isSubmitting || !canSubmit)
                }
            }
        }
    }

    private var canSubmit: Bool {
        !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() async {
        guard canSubmit, !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil

        // Compose the requested timestamp from the picked date + time.
        let calendar = Calendar.current
        let dayParts = calendar.dateComponents([.year, .month, .day], from: targetDate)
        let timeParts = calendar.dateComponents([.hour, .minute], from: requestedTime)
        var combined = DateComponents()
        combined.year = dayParts.year
        combined.month = dayParts.month
        combined.day = dayParts.day
        combined.hour = timeParts.hour
        combined.minute = timeParts.minute
        guard let requestedTs = calendar.date(from: combined) else {
            errorMessage = "Không thể tạo mốc thời gian. Vui lòng chọn lại."
            return
        }
        // Reject future timestamps client-side; the server will too, but a
        // friendly early check beats a generic 400.
        if requestedTs > Date().addingTimeInterval(60) {
            errorMessage = "Thời gian bổ sung không thể nằm trong tương lai."
            return
        }

        let targetDateStr = Self.dateOnlyFormatter.string(from: targetDate)
        let requestedIso = ISO8601DateFormatter.supabase.string(from: requestedTs)
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)

        let payload = AttendanceCorrectionInsert(
            employeeId: profile.id,
            targetDate: targetDateStr,
            targetType: targetType.rawValue,
            requestedTs: requestedIso,
            reason: trimmedReason
        )

        do {
            try await SupabaseManager.shared.client
                .from("attendance_corrections")
                .insert(payload)
                .execute()
            await onSubmitted()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static func defaultTime() -> Date {
        var comps = DateComponents()
        comps.hour = 8
        comps.minute = 30
        return Calendar.current.date(from: comps) ?? Date()
    }
}
