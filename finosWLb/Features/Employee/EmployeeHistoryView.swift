import SwiftUI
internal import PostgREST
import Supabase

struct EmployeeHistoryView: View {
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
                    "Couldn't load history",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if events.isEmpty {
                ContentUnavailableView(
                    "No events yet",
                    systemImage: "calendar",
                    description: Text("Your check-ins will appear here.")
                )
            }
        }
        .navigationTitle("History")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            events = try await SupabaseManager.shared.client
                .from("attendance_events")
                .select("id, type, server_ts, client_ts, status, flagged_reason, branch_id, accuracy_m")
                .order("server_ts", ascending: false)
                .limit(100)
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
                return date.formatted(date: .abbreviated, time: .shortened)
            }
        }
        return iso
    }
}
