import SwiftUI
internal import PostgREST
import Supabase

struct EmployeeHistoryView: View {
    let profile: Profile

    enum Mode: String, Hashable, CaseIterable {
        case list, calendar

        var label: String {
            switch self {
            case .list:     "Danh sách"
            case .calendar: "Lịch"
            }
        }

        var systemImage: String {
            switch self {
            case .list:     "list.bullet.rectangle"
            case .calendar: "calendar"
            }
        }
    }

    @State private var events: [AttendanceEvent] = []
    @State private var corrections: [AttendanceCorrection] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCorrectionSheet = false
    @State private var mode: Mode = .list
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var visibleMonth: Date = Date()

    var body: some View {
        Group {
            switch mode {
            case .list:     listModeView
            case .calendar: calendarModeView
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Lịch sử")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Chế độ", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { m in
                        Label(m.label, systemImage: m.systemImage).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCorrectionSheet = true
                } label: {
                    Label("Bổ sung công", systemImage: "calendar.badge.plus")
                }
                .accessibilityLabel("Bổ sung công")
            }
        }
        .sheet(isPresented: $showCorrectionSheet) {
            CorrectionRequestSheet(profile: profile) {
                await load()
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - List mode

    private var listModeView: some View {
        List {
            if !pendingCorrections.isEmpty {
                Section {
                    ForEach(pendingCorrections) { correction in
                        correctionRow(correction)
                    }
                    .onDelete { indexes in
                        for idx in indexes {
                            Task { await cancel(pendingCorrections[idx]) }
                        }
                    }
                } header: {
                    Label("Đơn bổ sung đang chờ duyệt", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                        .textCase(nil)
                } footer: {
                    Text("Vuốt sang trái để hủy đơn khi chưa được duyệt.")
                        .font(.footnote)
                }
            }

            ForEach(groupedEvents, id: \.dayKey) { group in
                Section {
                    ForEach(group.events) { event in
                        eventRow(event)
                    }
                } header: {
                    dayHeader(group)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .overlay {
            if isLoading && events.isEmpty && corrections.isEmpty {
                ProgressView()
            } else if events.isEmpty, corrections.isEmpty, let errorMessage {
                ContentUnavailableView {
                    Label("Không thể tải lịch sử", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Thử lại") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
            } else if events.isEmpty, corrections.isEmpty {
                ContentUnavailableView {
                    Label("Chưa có hoạt động", systemImage: "calendar.badge.clock")
                } description: {
                    Text("Lịch sử chấm công sẽ hiển thị ở đây sau khi bạn chấm công lần đầu.")
                } actions: {
                    Button {
                        showCorrectionSheet = true
                    } label: {
                        Label("Bổ sung công", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    // MARK: - Calendar mode

    private var calendarModeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CheckInCalendarView(
                    events: events,
                    selectedDay: $selectedDay,
                    visibleMonth: $visibleMonth
                )

                // Legend
                legendRow
                    .padding(.horizontal, 24)

                // Selected day summary
                selectedDaySection
                    .padding(.horizontal, 16)
            }
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .overlay {
            if isLoading && events.isEmpty {
                ProgressView()
            }
        }
    }

    private var legendRow: some View {
        HStack(spacing: 14) {
            legendDot(color: .green, label: "Đúng giờ")
            legendDot(color: .orange, label: "Trễ")
            legendDot(color: .yellow, label: "Gắn cờ")
            legendDot(color: .red, label: "Từ chối")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
        }
    }

    @ViewBuilder
    private var selectedDaySection: some View {
        let cal = Calendar.current
        let dayEvents = events
            .filter { event in
                guard let d = parseDate(event.serverTs) else { return false }
                return cal.isDate(d, inSameDayAs: selectedDay)
            }
            .sorted { $0.serverTs < $1.serverTs }

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(vietnameseDayLabel(selectedDay))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let duration = durationLabel(for: dayEvents) {
                    Label(duration, systemImage: "clock")
                        .labelStyle(.titleAndIcon)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if dayEvents.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "moon.zzz")
                        .foregroundStyle(.secondary)
                    Text("Không có chấm công ngày này")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(dayEvents.enumerated()), id: \.element.id) { idx, event in
                        eventRow(event)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        if idx < dayEvents.count - 1 {
                            Divider().padding(.leading, 62)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
        }
    }

    private func durationLabel(for dayEvents: [AttendanceEvent]) -> String? {
        var total: TimeInterval = 0
        var lastIn: Date?
        for event in dayEvents.filter({ $0.status != .rejected }) {
            guard let date = parseDate(event.serverTs) else { continue }
            switch event.type {
            case .checkIn:
                lastIn = date
            case .checkOut:
                if let inDate = lastIn {
                    total += date.timeIntervalSince(inDate)
                    lastIn = nil
                }
            }
        }
        guard total > 0 else { return nil }
        let h = Int(total) / 3600
        let m = (Int(total) % 3600) / 60
        return h > 0 ? "\(h)g \(m)p" : "\(m)p"
    }

    // MARK: - Day grouping

    private struct DayGroup {
        let dayKey: String
        let date: Date
        let events: [AttendanceEvent]
    }

    private var groupedEvents: [DayGroup] {
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: events) { event -> String in
            guard let d = parseDate(event.serverTs) else { return "—" }
            return Self.dayKeyFormatter.string(from: calendar.startOfDay(for: d))
        }
        return byDay.compactMap { _, events -> DayGroup? in
            guard let first = events.first, let d = parseDate(first.serverTs) else { return nil }
            let day = calendar.startOfDay(for: d)
            let key = Self.dayKeyFormatter.string(from: day)
            return DayGroup(
                dayKey: key,
                date: day,
                events: events.sorted { $0.serverTs > $1.serverTs }
            )
        }
        .sorted { $0.date > $1.date }
    }

    private var pendingCorrections: [AttendanceCorrection] {
        corrections.filter { $0.status == .pending }
    }

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Rows

    private func dayHeader(_ group: DayGroup) -> some View {
        HStack(spacing: 8) {
            Text(vietnameseDayLabel(group.date))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .textCase(nil)
            Spacer()
            if let duration = dayDuration(group) {
                Label(duration, systemImage: "clock")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
    }

    private func eventRow(_ event: AttendanceEvent) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill((event.type == .checkIn ? Color.green : Color.blue).opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: event.type == .checkIn
                      ? "arrow.down.circle.fill"
                      : "arrow.up.circle.fill")
                .font(.title3)
                .foregroundStyle(event.type == .checkIn ? Color.green : Color.blue)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(event.type.label).font(.subheadline.weight(.medium))
                Text(formatTimeOnly(event.serverTs))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let reason = event.flaggedReason, !reason.isEmpty, event.status != .onTime {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer()
            StatusBadge(status: event.status)
        }
        .padding(.vertical, 4)
    }

    private func correctionRow(_ correction: AttendanceCorrection) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "calendar.badge.plus")
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Bổ sung \(correction.targetType.label.lowercased())")
                    .font(.subheadline.weight(.medium))
                Text(formatCorrectionDateTime(correction))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(correction.reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Text(correction.status.label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(correction.status.tint.opacity(0.15), in: Capsule())
                .foregroundStyle(correction.status.tint)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let eventsTask: [AttendanceEvent] = SupabaseManager.shared.client
                .from("attendance_events")
                .select("id, type, server_ts, client_ts, status, flagged_reason, branch_id, accuracy_m, note")
                .order("server_ts", ascending: false)
                .limit(200)
                .execute()
                .value
            async let correctionsTask: [AttendanceCorrection] = SupabaseManager.shared.client
                .from("attendance_corrections")
                .select(AttendanceCorrection.selectColumns)
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value

            events = try await eventsTask
            corrections = try await correctionsTask
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancel(_ correction: AttendanceCorrection) async {
        do {
            try await SupabaseManager.shared.client
                .from("attendance_corrections")
                .update(AttendanceCorrectionCancelPayload())
                .eq("id", value: correction.id.uuidString)
                .eq("status", value: "pending")
                .execute()
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func parseDate(_ iso: String) -> Date? {
        if let d = ISO8601DateFormatter.supabase.date(from: iso) { return d }
        return ISO8601DateFormatter().date(from: iso)
    }

    private func formatTimeOnly(_ iso: String) -> String {
        guard let d = parseDate(iso) else { return iso }
        return d.formatted(date: .omitted, time: .shortened)
    }

    private func formatCorrectionDateTime(_ correction: AttendanceCorrection) -> String {
        let dateStr = correction.targetDate
        let time = parseDate(correction.requestedTs).map { $0.formatted(date: .omitted, time: .shortened) } ?? ""
        return "\(dateStr) lúc \(time)"
    }

    private func vietnameseDayLabel(_ date: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        if calendar.isDateInToday(date) { return "Hôm nay" }
        if calendar.isDateInYesterday(date) { return "Hôm qua" }

        let weekday = calendar.component(.weekday, from: date)
        let names = ["", "Chủ nhật", "Thứ hai", "Thứ ba", "Thứ tư", "Thứ năm", "Thứ sáu", "Thứ bảy"]
        let name = (1...7).contains(weekday) ? names[weekday] : ""
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        return "\(name), \(f.string(from: date))"
    }

    /// Sum of time between matched check-in/check-out pairs on the same day.
    private func dayDuration(_ group: DayGroup) -> String? {
        let sorted = group.events
            .filter { $0.status != .rejected }
            .sorted { $0.serverTs < $1.serverTs }

        var total: TimeInterval = 0
        var lastIn: Date?
        for event in sorted {
            guard let date = parseDate(event.serverTs) else { continue }
            switch event.type {
            case .checkIn:
                lastIn = date
            case .checkOut:
                if let inDate = lastIn {
                    total += date.timeIntervalSince(inDate)
                    lastIn = nil
                }
            }
        }

        guard total > 0 else { return nil }
        let hours = Int(total) / 3600
        let minutes = (Int(total) % 3600) / 60
        if hours > 0 { return "\(hours)g \(minutes)p" }
        return "\(minutes)p"
    }
}
