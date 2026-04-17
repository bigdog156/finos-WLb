import SwiftUI
internal import PostgREST
import Supabase

/// Manager-facing read-only view of a single employee's events for a single day
/// (defaults to today). Reused by `ManagerBranchView` (row tap) and
/// `ManagerReportsView` (dot/name tap).
struct EmployeeDayDetailView: View {
    let employeeId: UUID
    let fullName: String
    let date: Date

    init(employeeId: UUID, fullName: String, date: Date = Date()) {
        self.employeeId = employeeId
        self.fullName = fullName
        self.date = date
    }

    @State private var events: [AttendanceEvent] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List(events) { event in
            HStack(spacing: 12) {
                Image(systemName: event.type == .checkIn
                      ? "arrow.down.circle.fill"
                      : "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(event.type == .checkIn ? .green : .blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.type.label).font(.headline)
                    Text(formatTimestamp(event.serverTs))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                StatusBadge(status: event.status)
            }
            .padding(.vertical, 2)
        }
        .overlay {
            if isLoading && events.isEmpty {
                ProgressView()
            } else if events.isEmpty, let errorMessage {
                ContentUnavailableView(
                    "Couldn't load events",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if events.isEmpty {
                ContentUnavailableView(
                    "No events",
                    systemImage: "calendar",
                    description: Text("\(fullName) has no recorded events for this day.")
                )
            }
        }
        .navigationTitle(fullName)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(fullName).font(.headline)
                    Text(dateSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var dateSubtitle: String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        // Local-day window. The view uses the device's current calendar/tz.
        // Branch timezone differences are a Phase 6 concern per the spec.
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            errorMessage = "Invalid date window"
            return
        }
        let startISO = ISO8601DateFormatter.supabase.string(from: start)
        let endISO = ISO8601DateFormatter.supabase.string(from: end)

        do {
            events = try await SupabaseManager.shared.client
                .from("attendance_events")
                .select("id, type, server_ts, client_ts, status, flagged_reason, branch_id, accuracy_m")
                .eq("employee_id", value: employeeId)
                .gte("server_ts", value: startISO)
                .lt("server_ts", value: endISO)
                .order("server_ts", ascending: true)
                .execute()
                .value
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formatTimestamp(_ iso: String) -> String {
        let formatters: [ISO8601DateFormatter] = [.supabase, ISO8601DateFormatter()]
        for f in formatters {
            if let date = f.date(from: iso) {
                return date.formatted(date: .omitted, time: .standard)
            }
        }
        return iso
    }
}
