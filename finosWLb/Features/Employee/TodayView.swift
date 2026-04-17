import SwiftUI
import SwiftData
internal import PostgREST
import Supabase

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var service: CheckInService?
    @State private var uiState: UIState = .unknown
    @State private var outcome: CheckInOutcome?
    @State private var errorMessage: String?

    enum UIState {
        case unknown, checkedIn, checkedOut
    }

    var body: some View {
        Form {
            Section {
                stateCard
            }

            Section {
                actionButton
            }

            if let outcome {
                Section("Last result") {
                    outcomeRow(outcome)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            if let pending = service?.pendingCount(), pending > 0 {
                Section {
                    Label("\(pending) pending check-in(s) queued",
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Today")
        .task {
            if service == nil {
                service = CheckInService(
                    locationService: LocationService(),
                    wifiService: WiFiService(),
                    modelContext: modelContext
                )
            }
            await loadLastState()
            await service?.flushQueue()
        }
    }

    private var stateCard: some View {
        HStack(spacing: 12) {
            Image(systemName: stateIcon)
                .font(.system(size: 36))
                .foregroundStyle(stateColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(stateTitle).font(.headline)
                Text(stateSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var actionButton: some View {
        let nextType: AttendanceEventType = (uiState == .checkedIn) ? .checkOut : .checkIn
        Button {
            Task { await performAction(type: nextType) }
        } label: {
            HStack {
                Text(nextType.label).fontWeight(.semibold)
                Spacer()
                if service?.isWorking == true {
                    ProgressView()
                } else {
                    Image(systemName: "location.fill")
                }
            }
        }
        .disabled(service == nil || service?.isWorking == true || uiState == .unknown)
    }

    private func outcomeRow(_ outcome: CheckInOutcome) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(outcome.event.type.label).font(.headline)
                Spacer()
                StatusBadge(status: outcome.event.status)
            }
            Text("\(outcome.distanceM) m from branch (allowed: \(outcome.radiusM) m)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let reason = outcome.event.flaggedReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var stateIcon: String {
        switch uiState {
        case .unknown:     "questionmark.circle"
        case .checkedIn:   "checkmark.circle.fill"
        case .checkedOut:  "circle"
        }
    }

    private var stateColor: Color {
        switch uiState {
        case .checkedIn:               .green
        case .checkedOut, .unknown:    .secondary
        }
    }

    private var stateTitle: String {
        switch uiState {
        case .unknown:     "Loading…"
        case .checkedIn:   "Checked in"
        case .checkedOut:  "Not checked in"
        }
    }

    private var stateSubtitle: String {
        switch uiState {
        case .unknown:     "Checking current status"
        case .checkedIn:   "Tap Check Out to end your shift"
        case .checkedOut:  "Tap Check In to start your shift"
        }
    }

    private func performAction(type: AttendanceEventType) async {
        guard let service else { return }
        errorMessage = nil
        do {
            let result = try await service.submit(type: type)
            outcome = result
            if result.event.status != .rejected {
                uiState = (type == .checkIn) ? .checkedIn : .checkedOut
            }
        } catch let error as CheckInError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadLastState() async {
        do {
            let events: [AttendanceEvent] = try await SupabaseManager.shared.client
                .from("attendance_events")
                .select("id, type, server_ts, client_ts, status, flagged_reason, branch_id, accuracy_m")
                .order("server_ts", ascending: false)
                .limit(1)
                .execute()
                .value

            if let last = events.first, last.status != .rejected {
                uiState = (last.type == .checkIn) ? .checkedIn : .checkedOut
            } else {
                uiState = .checkedOut
            }
        } catch {
            uiState = .checkedOut
        }
    }
}
