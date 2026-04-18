import SwiftUI
import SwiftData
internal import PostgREST
import Supabase

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var service: CheckInService?
    @State private var uiState: UIState = .unknown
    @State private var todayEvents: [AttendanceEvent] = []
    @State private var lastOutcome: CheckInOutcome?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var hapticTrigger = 0
    @State private var showPendingSheet = false
    @State private var pendingNote: String = ""
    @State private var showNoteSheet = false

    enum UIState { case unknown, checkedIn, checkedOut }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                clockHeader
                statusCard
                primaryActionButton
                noteRow
                statusChips
                if !todayEvents.isEmpty {
                    timelineSection
                }
                if let pending = service?.pendingCount(), pending > 0 {
                    pendingPill(count: pending)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Hôm nay")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await loadTodayEvents() }
        .task {
            if service == nil {
                service = CheckInService(
                    locationService: LocationService(),
                    wifiService: WiFiService(),
                    modelContext: modelContext
                )
            }
            await loadTodayEvents()
            await service?.flushQueue()
        }
        .alert("Không thể chấm công", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK") { errorMessage = nil }
        } message: { msg in
            Text(msg)
        }
        .sensoryFeedback(.success, trigger: hapticTrigger) { _, _ in
            lastOutcome?.event.status != .rejected
        }
        .sensoryFeedback(.error, trigger: hapticTrigger) { _, _ in
            errorMessage != nil || lastOutcome?.event.status == .rejected
        }
        .sheet(isPresented: $showPendingSheet) {
            PendingQueueSheet(service: service)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showNoteSheet) {
            CheckInNoteSheet(note: $pendingNote)
                .presentationDetents([.height(280)])
        }
    }

    // MARK: - Clock header

    private var clockHeader: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 4) {
                Text(context.date, format: .dateTime.hour().minute().second())
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text(vietnameseDayLabel(context.date))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Status card

    private var statusCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(stateColor.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: stateIcon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(stateColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(stateTitle).font(.headline)
                Text(stateSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if uiState == .checkedIn, let start = currentShiftStart {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text(workDurationText(start: start, now: context.date))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tint)
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Primary action button

    private var primaryActionButton: some View {
        let nextType: AttendanceEventType = (uiState == .checkedIn) ? .checkOut : .checkIn
        let busy = (service?.isWorking == true)
        let disabled = (service == nil) || busy || uiState == .unknown

        return VStack(spacing: 14) {
            Button {
                Task { await performAction(type: nextType) }
            } label: {
                ZStack {
                    Circle()
                        .fill(buttonTint.gradient)
                        .shadow(color: buttonTint.opacity(0.35), radius: 20, y: 10)
                    if busy {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.4)
                    } else {
                        Image(systemName: nextType == .checkIn
                              ? "arrow.down.to.line.circle.fill"
                              : "arrow.up.to.line.circle.fill")
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(.white)
                    }
                }
                .frame(width: 180, height: 180)
            }
            .buttonStyle(.plain)
            .disabled(disabled)
            .opacity(disabled && !busy ? 0.6 : 1)
            .accessibilityLabel(nextType.label)
            .accessibilityAddTraits(.isButton)

            Text(nextType.label)
                .font(.title3.weight(.semibold))
            Text(buttonHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Note row

    private var noteRow: some View {
        let trimmed = pendingNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasNote = !trimmed.isEmpty
        return Button {
            showNoteSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: hasNote ? "text.bubble.fill" : "text.bubble")
                    .font(.callout)
                    .foregroundStyle(hasNote ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hasNote ? "Ghi chú cho lần chấm công" : "Thêm ghi chú (tùy chọn)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    if hasNote {
                        Text(trimmed)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Ví dụ: Họp khách ngoài văn phòng, kẹt xe…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if hasNote {
                    Button {
                        pendingNote = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Xóa ghi chú")
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Status chips (last result summary)

    @ViewBuilder
    private var statusChips: some View {
        if let last = lastOutcome {
            HStack(spacing: 8) {
                Chip(
                    label: "\(last.distanceM) m",
                    systemImage: "location.fill",
                    tint: last.distanceM <= last.radiusM ? .green : .orange
                )
                Chip(
                    label: "Bán kính \(last.radiusM) m",
                    systemImage: "scope",
                    tint: .secondary
                )
                Chip(
                    label: last.event.status.label,
                    systemImage: statusSymbol(last.event.status),
                    tint: statusTint(last.event.status)
                )
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func statusSymbol(_ s: AttendanceEventStatus) -> String {
        switch s {
        case .onTime:   "checkmark.seal.fill"
        case .late:     "clock.badge.exclamationmark"
        case .flagged:  "flag.fill"
        case .absent:   "person.slash"
        case .rejected: "xmark.octagon.fill"
        }
    }

    private func statusTint(_ s: AttendanceEventStatus) -> Color {
        switch s {
        case .onTime:   .green
        case .late:     .orange
        case .flagged:  .yellow
        case .absent:   .gray
        case .rejected: .red
        }
    }

    // MARK: - Timeline of today's events

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hoạt động hôm nay")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(todayEvents.enumerated()), id: \.element.id) { idx, event in
                    timelineRow(event)
                    if idx < todayEvents.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    private func timelineRow(_ event: AttendanceEvent) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill((event.type == .checkIn ? Color.green : Color.blue).opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: event.type == .checkIn
                      ? "arrow.down.circle.fill"
                      : "arrow.up.circle.fill")
                    .font(.callout)
                    .foregroundStyle(event.type == .checkIn ? Color.green : Color.blue)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(event.type.label).font(.subheadline.weight(.medium))
                Text(formatTimeOnly(event.serverTs))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(status: event.status)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Pending sync pill

    private func pendingPill(count: Int) -> some View {
        Button {
            showPendingSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("\(count) lượt đang chờ gửi")
                Image(systemName: "chevron.right")
                    .font(.caption2)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.orange)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.orange.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Có \(count) lượt chấm công đang chờ gửi. Nhấn để xem.")
    }

    // MARK: - Derived state

    private var stateIcon: String {
        switch uiState {
        case .unknown:    "hourglass"
        case .checkedIn:  "checkmark.circle.fill"
        case .checkedOut: "moon.stars"
        }
    }

    private var stateColor: Color {
        switch uiState {
        case .unknown:    .secondary
        case .checkedIn:  .green
        case .checkedOut: .orange
        }
    }

    private var stateTitle: String {
        switch uiState {
        case .unknown:    "Đang tải…"
        case .checkedIn:  "Đang làm việc"
        case .checkedOut: "Chưa vào ca"
        }
    }

    private var stateSubtitle: String {
        switch uiState {
        case .unknown:
            return "Đang kiểm tra trạng thái hiện tại"
        case .checkedIn:
            if let t = lastCheckInTimeText {
                return "Bắt đầu ca lúc \(t)"
            }
            return "Bạn đã chấm công vào"
        case .checkedOut:
            return "Nhấn nút bên dưới để bắt đầu ca"
        }
    }

    private var buttonTint: Color {
        switch uiState {
        case .checkedIn:            .orange
        case .checkedOut, .unknown: .accentColor
        }
    }

    private var buttonHint: String {
        switch uiState {
        case .unknown:    "Đang chuẩn bị"
        case .checkedIn:  "Kết thúc ca làm việc"
        case .checkedOut: "Bắt đầu ca làm việc"
        }
    }

    private var currentShiftStart: Date? {
        guard uiState == .checkedIn,
              let last = todayEvents.first(where: { $0.type == .checkIn && $0.status != .rejected })
        else { return nil }
        return parseISO(last.serverTs)
    }

    private var lastCheckInTimeText: String? {
        currentShiftStart?.formatted(date: .omitted, time: .shortened)
    }

    private func workDurationText(start: Date, now: Date) -> String {
        let secs = max(0, Int(now.timeIntervalSince(start)))
        let hours = secs / 3600
        let minutes = (secs % 3600) / 60
        if hours > 0 {
            return "Đã làm \(hours) giờ \(minutes) phút"
        }
        return "Đã làm \(minutes) phút"
    }

    // MARK: - Actions

    private func performAction(type: AttendanceEventType) async {
        guard let service else { return }
        errorMessage = nil
        let note = pendingNote.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let result = try await service.submit(type: type, note: note.isEmpty ? nil : note)
            lastOutcome = result
            hapticTrigger &+= 1
            if result.event.status == .rejected {
                errorMessage = result.event.flaggedReason ?? "Chấm công bị từ chối."
                showError = true
            } else {
                uiState = (type == .checkIn) ? .checkedIn : .checkedOut
                pendingNote = ""
            }
            await loadTodayEvents()
        } catch let error as CheckInError {
            errorMessage = error.localizedDescription
            showError = true
            hapticTrigger &+= 1
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            hapticTrigger &+= 1
        }
    }

    // MARK: - Loading

    private func loadTodayEvents() async {
        do {
            let startOfDay = Calendar.current.startOfDay(for: Date())
            let startISO = ISO8601DateFormatter.supabase.string(from: startOfDay)
            let events: [AttendanceEvent] = try await SupabaseManager.shared.client
                .from("attendance_events")
                .select("id, type, server_ts, client_ts, status, flagged_reason, branch_id, accuracy_m")
                .gte("server_ts", value: startISO)
                .order("server_ts", ascending: false)
                .execute()
                .value
            todayEvents = events
            if let last = events.first(where: { $0.status != .rejected }) {
                uiState = (last.type == .checkIn) ? .checkedIn : .checkedOut
            } else {
                uiState = .checkedOut
            }
        } catch {
            if uiState == .unknown {
                uiState = .checkedOut
            }
        }
    }

    // MARK: - Helpers

    private func parseISO(_ iso: String) -> Date? {
        if let d = ISO8601DateFormatter.supabase.date(from: iso) { return d }
        return ISO8601DateFormatter().date(from: iso)
    }

    private func formatTimeOnly(_ iso: String) -> String {
        guard let d = parseISO(iso) else { return iso }
        return d.formatted(date: .omitted, time: .shortened)
    }

    private func vietnameseDayLabel(_ date: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let weekday = cal.component(.weekday, from: date)
        let names = ["", "Chủ nhật", "Thứ hai", "Thứ ba", "Thứ tư", "Thứ năm", "Thứ sáu", "Thứ bảy"]
        let name = (1...7).contains(weekday) ? names[weekday] : ""
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        return "\(name), \(f.string(from: date))"
    }
}

// MARK: - Chip

private struct Chip: View {
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            Text(label)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.caption.weight(.medium))
        .labelStyle(.titleAndIcon)
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.15), in: Capsule())
    }
}

// MARK: - Note sheet

private struct CheckInNoteSheet: View {
    @Binding var note: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ghi chú (tối đa 500 ký tự)", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($isFocused)
                        .onChange(of: note) { _, new in
                            if new.count > 500 {
                                note = String(new.prefix(500))
                            }
                        }
                } footer: {
                    Text("Ghi chú sẽ được lưu cùng lượt chấm công sắp tới để quản lý tham khảo.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Ghi chú chấm công")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        note = ""
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { isFocused = true }
        }
    }
}
