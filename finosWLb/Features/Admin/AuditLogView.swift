import SwiftUI
import UIKit
import Supabase

/// Admin-only audit log browser. Lives inside the Admin settings stack
/// (parent provides `NavigationStack`). Mirrors the filter-chip +
/// paginated-list shape used elsewhere in the Admin section.
struct AuditLogView: View {
    // Page size chosen to match typical list-view fetch budgets; the backend
    // is indexed by `ts` so deep pages are cheap.
    private static let pageSize = 50

    // MARK: - Filter models

    enum ActionFilter: Hashable {
        case all
        case specific(String)

        var label: String {
            switch self {
            case .all: return "Tất cả hành động"
            case .specific(let s): return s
            }
        }

        // Hardcoded as per spec — adding a new trigger requires explicitly
        // surfacing it here so the menu stays curated.
        static let allCases: [ActionFilter] = [
            .all,
            .specific("INSERT_branches"),
            .specific("UPDATE_branches"),
            .specific("DELETE_branches"),
            .specific("INSERT_departments"),
            .specific("UPDATE_departments"),
            .specific("DELETE_departments"),
            .specific("INSERT_profiles"),
            .specific("UPDATE_profiles"),
            .specific("DELETE_profiles"),
            .specific("review_event"),
            .specific("create_user"),
        ]
    }

    enum TargetFilter: Hashable {
        case all
        case specific(String)

        var label: String {
            switch self {
            case .all: return "Tất cả bảng"
            case .specific(let s): return s
            }
        }

        static let allCases: [TargetFilter] = [
            .all,
            .specific("branches"),
            .specific("departments"),
            .specific("profiles"),
            .specific("attendance_events"),
        ]
    }

    enum DateFilter: Hashable {
        case all
        case today
        case last7
        case last30
        case custom(Date, Date) // [start, endExclusive)

        var label: String {
            switch self {
            case .all: return "Tất cả ngày"
            case .today: return "Hôm nay"
            case .last7: return "7 ngày gần nhất"
            case .last30: return "30 ngày gần nhất"
            case .custom(let s, let e):
                let f = DateFormatter()
                f.dateStyle = .short
                f.timeStyle = .none
                return "\(f.string(from: s)) – \(f.string(from: e))"
            }
        }

        /// Inclusive lower bound ISO string, or nil for "all".
        func startISO() -> String? {
            let cal = Calendar.current
            let now = Date()
            switch self {
            case .all: return nil
            case .today:
                return ISO8601DateFormatter.supabase.string(from: cal.startOfDay(for: now))
            case .last7:
                let start = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: now)) ?? now
                return ISO8601DateFormatter.supabase.string(from: start)
            case .last30:
                let start = cal.date(byAdding: .day, value: -30, to: cal.startOfDay(for: now)) ?? now
                return ISO8601DateFormatter.supabase.string(from: start)
            case .custom(let s, _):
                return ISO8601DateFormatter.supabase.string(from: cal.startOfDay(for: s))
            }
        }

        /// Exclusive upper bound ISO string, or nil if unbounded.
        func endISO() -> String? {
            let cal = Calendar.current
            switch self {
            case .custom(_, let e):
                let endExclusive = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: e)) ?? e
                return ISO8601DateFormatter.supabase.string(from: endExclusive)
            default:
                return nil
            }
        }
    }

    // MARK: - State

    @State private var entries: [AuditLogEntry] = []
    @State private var nameCache: [UUID: String] = [:]

    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var hasMore = true
    @State private var errorMessage: String?

    @State private var actionFilter: ActionFilter = .all
    @State private var targetFilter: TargetFilter = .all
    @State private var dateFilter: DateFilter = .all

    @State private var showingCustomRange = false
    @State private var customStart: Date = Calendar.current.date(
        byAdding: .day, value: -7, to: Date()
    ) ?? Date()
    @State private var customEnd: Date = Date()

    @State private var selectedEntry: AuditLogEntry?

    var body: some View {
        List {
            filterBar
                .listRowInsets(.init(top: 8, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            ForEach(entries) { entry in
                Button {
                    selectedEntry = entry
                } label: {
                    row(entry)
                }
                .buttonStyle(.plain)
            }

            if hasMore && !entries.isEmpty {
                loadMoreSentinel
                    .listRowSeparator(.hidden)
            }

            if let errorMessage, !entries.isEmpty {
                Section {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
        .listStyle(.plain)
        .overlay { overlay }
        .navigationTitle("Nhật ký kiểm toán")
        .sheet(isPresented: $showingCustomRange) {
            customRangeSheet
        }
        .sheet(item: $selectedEntry) { entry in
            AuditPayloadDetail(entry: entry)
        }
        .task { await reload() }
        .refreshable { await reload() }
        // Any filter change restarts pagination from zero.
        .onChange(of: actionFilter) { _, _ in Task { await reload() } }
        .onChange(of: targetFilter) { _, _ in Task { await reload() } }
        .onChange(of: dateFilter) { _, _ in Task { await reload() } }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                actionMenu
                targetMenu
                dateMenu
            }
            .padding(.vertical, 4)
        }
    }

    private var actionMenu: some View {
        Menu {
            ForEach(ActionFilter.allCases, id: \.self) { filter in
                Button {
                    actionFilter = filter
                } label: {
                    Label(filter.label,
                          systemImage: actionFilter == filter ? "checkmark" : "")
                }
            }
        } label: {
            chip(title: actionFilter.label, isActive: actionFilter != .all)
        }
    }

    private var targetMenu: some View {
        Menu {
            ForEach(TargetFilter.allCases, id: \.self) { filter in
                Button {
                    targetFilter = filter
                } label: {
                    Label(filter.label,
                          systemImage: targetFilter == filter ? "checkmark" : "")
                }
            }
        } label: {
            chip(title: targetFilter.label, isActive: targetFilter != .all)
        }
    }

    private var dateMenu: some View {
        Menu {
            Button {
                dateFilter = .all
            } label: {
                Label("Tất cả ngày",
                      systemImage: isDateFilter(.all) ? "checkmark" : "")
            }
            Button {
                dateFilter = .today
            } label: {
                Label("Hôm nay",
                      systemImage: isDateFilter(.today) ? "checkmark" : "")
            }
            Button {
                dateFilter = .last7
            } label: {
                Label("7 ngày gần nhất",
                      systemImage: isDateFilter(.last7) ? "checkmark" : "")
            }
            Button {
                dateFilter = .last30
            } label: {
                Label("30 ngày gần nhất",
                      systemImage: isDateFilter(.last30) ? "checkmark" : "")
            }
            Divider()
            Button {
                showingCustomRange = true
            } label: {
                Label("Tùy chỉnh…",
                      systemImage: isCustomDateFilter() ? "checkmark" : "calendar")
            }
        } label: {
            chip(title: dateFilter.label, isActive: dateFilter != .all)
        }
    }

    private func isDateFilter(_ candidate: DateFilter) -> Bool {
        switch (dateFilter, candidate) {
        case (.all, .all), (.today, .today), (.last7, .last7), (.last30, .last30):
            return true
        default:
            return false
        }
    }

    private func isCustomDateFilter() -> Bool {
        if case .custom = dateFilter { return true }
        return false
    }

    private func chip(title: String, isActive: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(isActive ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
        )
        .foregroundStyle(isActive ? Color.accentColor : .primary)
    }

    private var customRangeSheet: some View {
        NavigationStack {
            Form {
                DatePicker("Bắt đầu",
                           selection: $customStart,
                           displayedComponents: .date)
                DatePicker("Kết thúc",
                           selection: $customEnd,
                           in: customStart...,
                           displayedComponents: .date)
            }
            .navigationTitle("Khoảng tùy chỉnh")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { showingCustomRange = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Áp dụng") {
                        dateFilter = .custom(customStart, customEnd)
                        showingCustomRange = false
                    }
                }
            }
        }
    }

    // MARK: - Row

    private func row(_ entry: AuditLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.action)
                    .font(.headline)
                Spacer()
                Text(relativeTime(entry.ts))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text("bởi \(actorLabel(for: entry))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(targetSubtitle(for: entry))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospaced()
        }
        .padding(.vertical, 4)
    }

    private func actorLabel(for entry: AuditLogEntry) -> String {
        guard let id = entry.actorId else { return "hệ thống" }
        return nameCache[id] ?? id.uuidString.prefix(8).description
    }

    private func targetSubtitle(for entry: AuditLogEntry) -> String {
        let idFragment: String
        if let raw = entry.targetId, !raw.isEmpty {
            idFragment = String(raw.prefix(8))
        } else {
            idFragment = "—"
        }
        return "\(entry.targetTable) · \(idFragment)"
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

    // MARK: - Load-more sentinel

    private var loadMoreSentinel: some View {
        HStack {
            Spacer()
            if isLoadingMore {
                ProgressView()
            } else {
                Button("Tải thêm") {
                    Task { await loadMore() }
                }
                .font(.footnote.weight(.medium))
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .task {
            // Auto-trigger pagination when the sentinel scrolls into view.
            if !isLoadingMore {
                await loadMore()
            }
        }
    }

    // MARK: - Overlay

    @ViewBuilder
    private var overlay: some View {
        if isLoading && entries.isEmpty {
            ProgressView()
        } else if let errorMessage, entries.isEmpty {
            ContentUnavailableView(
                "Không thể tải nhật ký kiểm toán",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
        } else if entries.isEmpty {
            ContentUnavailableView(
                "Không có mục kiểm toán",
                systemImage: "doc.text.magnifyingglass"
            )
        }
    }

    // MARK: - Networking

    private func reload() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await fetch(offset: 0)
            entries = fetched
            hasMore = fetched.count >= Self.pageSize
            await refreshNameCache(for: fetched)
        } catch {
            entries = []
            hasMore = false
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadMore() async {
        guard !isLoadingMore, hasMore, !entries.isEmpty else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let fetched = try await fetch(offset: entries.count)
            // Dedup defensively — if a row arrived since the last page, it
            // could otherwise appear twice.
            let existing = Set(entries.map(\.id))
            let fresh = fetched.filter { !existing.contains($0.id) }
            entries.append(contentsOf: fresh)
            hasMore = fetched.count >= Self.pageSize
            await refreshNameCache(for: fresh)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetch(offset: Int) async throws -> [AuditLogEntry] {
        // Build filters progressively. Each `.eq/.gte/.lt` returns a filter
        // builder so we reassign to the same `var` to keep the chain typed.
        var query = SupabaseManager.shared.client
            .from("audit_log")
            .select(AuditLogEntry.selectColumns)

        if case .specific(let action) = actionFilter {
            query = query.eq("action", value: action)
        }
        if case .specific(let table) = targetFilter {
            query = query.eq("target_table", value: table)
        }
        if let startISO = dateFilter.startISO() {
            query = query.gte("ts", value: startISO)
        }
        if let endISO = dateFilter.endISO() {
            query = query.lt("ts", value: endISO)
        }

        let response: [AuditLogEntry] = try await query
            .order("ts", ascending: false)
            .range(from: offset, to: offset + Self.pageSize - 1)
            .execute()
            .value
        return response
    }

    private func refreshNameCache(for rows: [AuditLogEntry]) async {
        let missing = Set(rows.compactMap(\.actorId)).subtracting(nameCache.keys)
        guard !missing.isEmpty else { return }

        struct ProfileRow: Codable { let id: UUID; let full_name: String }
        do {
            let profiles: [ProfileRow] = try await SupabaseManager.shared.client
                .from("profiles")
                .select("id, full_name")
                .in("id", values: Array(missing))
                .execute()
                .value
            for p in profiles { nameCache[p.id] = p.full_name }
        } catch {
            // Non-fatal — rows fall back to truncated UUIDs.
        }
    }
}

// MARK: - Payload detail sheet

/// Pretty-printed JSON viewer with a copy-to-clipboard shortcut.
private struct AuditPayloadDetail: View {
    let entry: AuditLogEntry

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    metadataHeader
                    Divider()
                    Text(prettyPrintedPayload)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .navigationTitle("Dữ liệu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIPasteboard.general.string = prettyPrintedPayload
                        copied = true
                    } label: {
                        Label(copied ? "Đã sao chép" : "Sao chép JSON",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                }
            }
        }
    }

    private var metadataHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.action).font(.headline)
            Text("\(entry.targetTable) · \(entry.targetId ?? "—")")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Text(entry.ts)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
    }

    /// Pretty-print the payload. Fall back to `String(describing:)` if
    /// `JSONSerialization` rejects it (shouldn't happen since `AnyJSON.value`
    /// is always JSON-compatible, but defensive).
    private var prettyPrintedPayload: String {
        guard let payload = entry.payload else { return "null" }
        let raw = payload.value
        if JSONSerialization.isValidJSONObject(raw) {
            if let data = try? JSONSerialization.data(
                withJSONObject: raw,
                options: [.prettyPrinted, .sortedKeys]
            ),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
        }
        // Scalars (string/number/bool/null) aren't valid top-level JSON for
        // JSONSerialization — encode via the Codable path to stay honest.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(payload),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return String(describing: payload.value)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AuditLogView()
    }
}
