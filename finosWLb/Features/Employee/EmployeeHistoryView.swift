import SwiftUI
internal import PostgREST
import Supabase

struct EmployeeHistoryView: View {
    @State private var events: [AttendanceEvent] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
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
        .background(Color(.systemGroupedBackground))
        .overlay {
            if isLoading && events.isEmpty {
                ProgressView()
            } else if events.isEmpty, let errorMessage {
                ContentUnavailableView {
                    Label("Không thể tải lịch sử", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Thử lại") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
            } else if events.isEmpty {
                ContentUnavailableView {
                    Label("Chưa có hoạt động", systemImage: "calendar.badge.clock")
                } description: {
                    Text("Lịch sử chấm công sẽ hiển thị ở đây sau khi bạn chấm công lần đầu.")
                }
            }
        }
        .navigationTitle("Lịch sử")
        .task { await load() }
        .refreshable { await load() }
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

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Header / Rows

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

    // MARK: - Loading

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            events = try await SupabaseManager.shared.client
                .from("attendance_events")
                .select("id, type, server_ts, client_ts, status, flagged_reason, branch_id, accuracy_m")
                .order("server_ts", ascending: false)
                .limit(200)
                .execute()
                .value
            errorMessage = nil
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
