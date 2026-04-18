import SwiftUI
import Supabase

/// Manager Review Queue — list of flagged `attendance_events` with realtime
/// INSERT/UPDATE/DELETE feed. Manager acts on each card by posting to the
/// `review-event` Edge Function.
struct ManagerReviewQueue: View {
    enum SortMode: Hashable {
        case newestFirst
        case highestRiskFirst
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var events: [FlaggedEvent] = []
    @State private var nameCache: [UUID: String] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var sortMode: SortMode = .newestFirst

    // Inline error presented after a failed review post. We keep the card on
    // screen, drop the spinner, and show this alert.
    @State private var actionError: String?

    // Per-card "busy" flag so optimistic dim + spinner is scoped to one card.
    @State private var busyIds: Set<UUID> = []

    // Deferred action sheet — populated when a bordered button is tapped.
    @State private var pendingAction: PendingAction?

    // Realtime plumbing.
    @State private var channel: RealtimeChannelV2?
    @State private var realtimeTask: Task<Void, Never>?

    // Haptic triggers: bumped on successful submit / error so views can
    // fire sensoryFeedback off MainActor state changes.
    @State private var successTrigger = 0
    @State private var errorTrigger = 0

    var body: some View {
        List {
            ForEach(sortedEvents) { event in
                reviewCard(event)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .transition(transition)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            Task { await submit(event: event, newStatus: .onTime, note: nil) }
                        } label: {
                            Label("Đúng giờ", systemImage: "checkmark.seal.fill")
                        }
                        .tint(.green)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await submit(event: event, newStatus: .rejected, note: nil) }
                        } label: {
                            Label("Từ chối", systemImage: "xmark.octagon.fill")
                        }
                        Button {
                            Task { await submit(event: event, newStatus: .late, note: nil) }
                        } label: {
                            Label("Trễ", systemImage: "clock.badge.exclamationmark")
                        }
                        .tint(.orange)
                    }
            }
        }
        .listStyle(.plain)
        .animation(reduceMotion ? .default : .spring(response: 0.4, dampingFraction: 0.85),
                   value: events.map(\.id))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        sortMode = .newestFirst
                    } label: {
                        Label("Mới nhất trước",
                              systemImage: sortMode == .newestFirst ? "checkmark" : "clock")
                    }
                    Button {
                        sortMode = .highestRiskFirst
                    } label: {
                        Label("Rủi ro cao nhất trước",
                              systemImage: sortMode == .highestRiskFirst ? "checkmark" : "exclamationmark.triangle")
                    }
                } label: {
                    Label("Sắp xếp", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .overlay { overlay }
        .navigationTitle("Duyệt")
        .sheet(item: $pendingAction) { action in
            decisionSheet(for: action)
                .presentationDetents([.height(220), .medium])
                .presentationDragIndicator(.visible)
        }
        .alert("Không thể áp dụng quyết định",
               isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
               )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .task {
            await load()
            await startRealtime()
        }
        .onDisappear {
            stopRealtime()
        }
        .refreshable { await load() }
        .sensoryFeedback(.success, trigger: successTrigger)
        .sensoryFeedback(.error, trigger: errorTrigger)
    }

    // MARK: - Card

    private func reviewCard(_ event: FlaggedEvent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(nameCache[event.employeeId] ?? "Đang tải…")
                    .font(.headline)
                Spacer()
                Text(relativeTime(event.serverTs))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Label(event.flaggedReason ?? "Bị gắn cờ để duyệt",
                  systemImage: "flag.fill")
                .foregroundStyle(.yellow)
                .font(.subheadline.weight(.medium))

            riskRow(event)

            actionRow(event)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .opacity(busyIds.contains(event.id) ? 0.55 : 1)
        .overlay {
            if busyIds.contains(event.id) {
                ProgressView()
            }
        }
        .allowsHitTesting(!busyIds.contains(event.id))
    }

    private func riskRow(_ event: FlaggedEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Gauge(value: Double(event.riskScore), in: 0...100) {
                Text("Rủi ro")
            } currentValueLabel: {
                Text("\(event.riskScore)")
            }
            .tint(riskTint(event.riskScore))

            HStack(spacing: 10) {
                // Prefer distance-to-branch (backfilled on new events). Fall
                // back to raw GPS accuracy for historical events without
                // distance_m populated.
                if let dist = event.distanceM {
                    Label("\(Int(dist.rounded())) m",
                          systemImage: "location")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("±\(Int((event.accuracyM ?? 0).rounded())) m",
                          systemImage: "location.slash")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Label(event.bssid != nil ? "Có WiFi" : "Không WiFi",
                      systemImage: "wifi")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(event.bssid != nil ? Color.secondary : Color.red)
            }
        }
    }

    private func actionRow(_ event: FlaggedEvent) -> some View {
        HStack(spacing: 8) {
            Button {
                pendingAction = PendingAction(event: event, newStatus: .onTime)
            } label: {
                Text("Đúng giờ")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            Button {
                pendingAction = PendingAction(event: event, newStatus: .late)
            } label: {
                Text("Trễ")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(.orange)

            Button {
                pendingAction = PendingAction(event: event, newStatus: .rejected)
            } label: {
                Text("Từ chối")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }

    // MARK: - Decision sheet

    private func decisionSheet(for action: PendingAction) -> some View {
        DecisionSheet(
            action: action,
            employeeName: nameCache[action.event.employeeId] ?? "nhân viên này"
        ) { note in
            pendingAction = nil
            await submit(event: action.event,
                         newStatus: action.newStatus,
                         note: note.isEmpty ? nil : note)
        } onCancel: {
            pendingAction = nil
        }
    }

    // MARK: - Overlay

    @ViewBuilder
    private var overlay: some View {
        if isLoading && events.isEmpty {
            ProgressView()
        } else if let errorMessage, events.isEmpty {
            ContentUnavailableView(
                "Không thể tải hàng đợi duyệt",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
        } else if events.isEmpty {
            ContentUnavailableView(
                "Đã duyệt xong",
                systemImage: "checkmark.seal.fill",
                description: Text("Không có gì bị gắn cờ — mọi người đã chấm công sạch.")
            )
        }
    }

    // MARK: - Derived

    private var sortedEvents: [FlaggedEvent] {
        switch sortMode {
        case .newestFirst:
            return events.sorted { $0.serverTs > $1.serverTs }
        case .highestRiskFirst:
            return events.sorted { lhs, rhs in
                if lhs.riskScore != rhs.riskScore { return lhs.riskScore > rhs.riskScore }
                return lhs.serverTs > rhs.serverTs
            }
        }
    }

    private var transition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
    }

    private func riskTint(_ score: Int) -> Color {
        if score < 33 { return .green }
        if score < 66 { return .orange }
        return .red
    }

    private func relativeTime(_ iso: String) -> String {
        let formatters: [ISO8601DateFormatter] = [.supabase, ISO8601DateFormatter()]
        for f in formatters {
            if let date = f.date(from: iso) {
                return date.formatted(.relative(presentation: .named))
            }
        }
        return iso
    }

    // MARK: - Network

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched: [FlaggedEvent] = try await SupabaseManager.shared.client
                .from("attendance_events")
                .select(FlaggedEvent.selectColumns)
                .eq("status", value: "flagged")
                .order("server_ts", ascending: false)
                .execute()
                .value
            events = fetched
            await refreshNameCache(for: fetched)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshNameCache(for events: [FlaggedEvent]) async {
        let missing = Set(events.map(\.employeeId)).subtracting(nameCache.keys)
        guard !missing.isEmpty else { return }

        struct ProfileRow: Codable { let id: UUID; let full_name: String }
        do {
            let rows: [ProfileRow] = try await SupabaseManager.shared.client
                .from("profiles")
                .select("id, full_name")
                .in("id", values: Array(missing))
                .execute()
                .value
            for row in rows { nameCache[row.id] = row.full_name }
        } catch {
            // Names are a nicety — don't block the queue on a lookup failure.
        }
    }

    private func submit(
        event: FlaggedEvent,
        newStatus: ReviewStatus,
        note: String?
    ) async {
        busyIds.insert(event.id)
        defer { busyIds.remove(event.id) }

        let body = ReviewEventBody(
            eventId: event.id,
            newStatus: newStatus.rawValue,
            note: note
        )
        do {
            let _: ReviewEventResponse = try await SupabaseManager.shared.client
                .functions
                .invoke("review-event", options: FunctionInvokeOptions(body: body))
            // Optimistically drop the card; the realtime UPDATE will also
            // drop it — `removeIfPresent` keeps that idempotent.
            withAnimation(reduceMotion ? .default : .spring(response: 0.4)) {
                events.removeAll { $0.id == event.id }
            }
            successTrigger &+= 1
        } catch FunctionsError.httpError(let code, let data) {
            let message = decodeFunctionError(data) ?? "HTTP \(code)"
            actionError = message
            errorTrigger &+= 1
        } catch {
            actionError = error.localizedDescription
            errorTrigger &+= 1
        }
    }

    private func decodeFunctionError(_ data: Data) -> String? {
        struct Err: Codable { let error: String? }
        return (try? JSONDecoder().decode(Err.self, from: data))?.error
    }

    // MARK: - Realtime

    private func startRealtime() async {
        guard channel == nil else { return }

        let client = SupabaseManager.shared.client
        let newChannel = client.realtimeV2.channel("flagged-events")

        // Bridge the @Sendable off-actor callback into a MainActor-friendly
        // AsyncStream. This keeps all @State mutation on MainActor without
        // capturing `self` in a Sendable closure.
        let (stream, continuation) = AsyncStream.makeStream(of: AnyAction.self)

        _ = newChannel.onPostgresChange(
            AnyAction.self,
            schema: "public",
            table: "attendance_events",
            filter: "status=eq.flagged"
        ) { action in
            continuation.yield(action)
        }

        await newChannel.subscribe()
        channel = newChannel

        realtimeTask = Task { @MainActor in
            for await action in stream {
                await handle(action)
            }
        }
    }

    private func stopRealtime() {
        realtimeTask?.cancel()
        realtimeTask = nil
        let toDrop = channel
        channel = nil
        Task { await toDrop?.unsubscribe() }
    }

    private func handle(_ action: AnyAction) async {
        let decoder = JSONDecoder()
        switch action {
        case .insert(let insert):
            guard let event = try? insert.decodeRecord(as: FlaggedEvent.self, decoder: decoder) else { return }
            // Server-side filter already narrowed to flagged, but double-check.
            guard event.status == .flagged else { return }
            if !events.contains(where: { $0.id == event.id }) {
                withAnimation(reduceMotion ? .default : .spring(response: 0.4)) {
                    events.insert(event, at: 0)
                }
                await refreshNameCache(for: [event])
            }

        case .update(let update):
            // The PG filter only fires UPDATEs where the NEW row is `flagged`.
            // When a reviewer flips status to on_time/late/rejected, the new
            // row no longer matches the filter, so the realtime channel sends
            // a synthetic DELETE instead. We still handle the UPDATE case for
            // in-place metadata edits (e.g. risk_score bump) defensively.
            guard let event = try? update.decodeRecord(as: FlaggedEvent.self, decoder: decoder) else { return }
            if let idx = events.firstIndex(where: { $0.id == event.id }) {
                if event.status == .flagged {
                    events[idx] = event
                } else {
                    withAnimation(reduceMotion ? .default : .spring(response: 0.4)) {
                        _ = events.remove(at: idx)
                    }
                }
            }

        case .delete(let delete):
            // Record is in oldRecord for DELETE. We only need the id.
            let idString = delete.oldRecord["id"]?.stringValue
            guard let idString, let id = UUID(uuidString: idString) else { return }
            withAnimation(reduceMotion ? .default : .spring(response: 0.4)) {
                events.removeAll { $0.id == id }
            }
        }
    }
}

// MARK: - Decision sheet

private struct DecisionSheet: View {
    let action: PendingAction
    let employeeName: String
    let onConfirm: @MainActor (String) async -> Void
    let onCancel: () -> Void

    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Quyết định") {
                    LabeledContent("Nhân viên", value: employeeName)
                    LabeledContent("Chuyển thành", value: action.newStatus.label)
                }
                Section("Ghi chú (tùy chọn)") {
                    TextField("Tại sao? (sẽ hiển thị trong nhật ký kiểm toán)",
                              text: $note,
                              axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle("Duyệt sự kiện")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xác nhận") {
                        let capturedNote = note
                        Task { await onConfirm(capturedNote) }
                    }
                    .tint(action.newStatus.tint)
                }
            }
        }
    }
}

// MARK: - Supporting types

struct PendingAction: Identifiable, Hashable {
    let event: FlaggedEvent
    let newStatus: ReviewStatus
    var id: UUID { event.id }
}

enum ReviewStatus: String, Hashable {
    case onTime = "on_time"
    case late
    case rejected

    var label: String {
        switch self {
        case .onTime:   "Đúng giờ"
        case .late:     "Trễ"
        case .rejected: "Bị từ chối"
        }
    }

    var tint: Color {
        switch self {
        case .onTime:   .green
        case .late:     .orange
        case .rejected: .red
        }
    }
}
