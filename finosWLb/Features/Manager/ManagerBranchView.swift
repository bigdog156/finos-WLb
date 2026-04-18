import SwiftUI
internal import PostgREST
import Supabase

/// "My Branch" — today-only snapshot of the manager's branch roster, grouped
/// by derived state and searchable by name. Backed by the
/// `branch_employee_today` view (RLS-scoped).
struct ManagerBranchView: View {
    @State private var rows: [BranchEmployeeToday] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var search: String = ""
    @State private var selectedDeptId: UUID? = nil     // nil == "All"

    private static let headerDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    var body: some View {
        List {
            // Summary strip lives inside the List so it scrolls with content
            // on short screens but still feels pinned-ish at top.
            Section {
                summaryStrip
                    .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ForEach(BranchEmployeeToday.DerivedState.allCases, id: \.self) { state in
                let group = filtered.filter { $0.derivedState == state }
                if !group.isEmpty {
                    Section("\(state.label) (\(group.count))") {
                        ForEach(group) { row in
                            NavigationLink {
                                EmployeeDayDetailView(
                                    employeeId: row.employeeId,
                                    fullName: row.fullName
                                )
                            } label: {
                                employeeRow(row)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $search, prompt: "Tìm theo tên")
        .toolbar {
            if departments.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            selectedDeptId = nil
                        } label: {
                            Label("Tất cả phòng ban",
                                  systemImage: selectedDeptId == nil ? "checkmark" : "")
                        }
                        Divider()
                        ForEach(departments, id: \.self) { dept in
                            Button {
                                selectedDeptId = dept
                            } label: {
                                Label(deptLabel(dept),
                                      systemImage: selectedDeptId == dept ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Label("Phòng ban",
                              systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
        .overlay { overlay }
        .navigationTitle("Chi nhánh của tôi")
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text("Chi nhánh của tôi").font(.headline)
                    Text(Self.headerDateFormatter.string(from: Date()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Summary strip

    private var summaryStrip: some View {
        HStack(spacing: 12) {
            statTile(count: presentCount, label: "Có mặt")
            statTile(count: absentCount, label: "Vắng")
            statTile(count: flaggedCount, label: "Gắn cờ")
        }
    }

    private func statTile(count: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(count)").font(.title2).bold()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Row

    private func employeeRow(_ row: BranchEmployeeToday) -> some View {
        HStack(spacing: 12) {
            avatar(for: row.fullName)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.fullName).font(.headline)
                Text(timeSummary(row))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if row.flaggedCount > 0 {
                Image(systemName: "flag.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("\(row.flaggedCount) sự kiện bị gắn cờ")
            }
            if row.hasLate {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Đã trễ")
            }

            ManagerStatePill(state: row.derivedState)
        }
        .padding(.vertical, 2)
    }

    private func avatar(for name: String) -> some View {
        Circle()
            .fill(Color.accentColor.opacity(0.15))
            .frame(width: 36, height: 36)
            .overlay {
                Text(initials(from: name))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
    }

    // MARK: - Overlays

    @ViewBuilder
    private var overlay: some View {
        if isLoading && rows.isEmpty {
            ProgressView()
        } else if let errorMessage, rows.isEmpty {
            ContentUnavailableView(
                "Không thể tải hôm nay",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
        } else if rows.isEmpty {
            ContentUnavailableView(
                "Chưa có nhân viên",
                systemImage: "person.2",
                description: Text("Phân công nhân viên vào chi nhánh này từ Quản trị.")
            )
        } else if filtered.isEmpty {
            // Search/filter miss — keep it lightweight; full-view empty states
            // are reserved for "no data at all".
            ContentUnavailableView.search(text: search)
        }
    }

    // MARK: - Derived data

    private var filtered: [BranchEmployeeToday] {
        var out = rows
        if let selectedDeptId {
            out = out.filter { $0.deptId == selectedDeptId }
        }
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            out = out.filter { $0.fullName.localizedCaseInsensitiveContains(q) }
        }
        return out
    }

    private var departments: [UUID] {
        let ids = Set(rows.compactMap(\.deptId))
        return Array(ids).sorted { $0.uuidString < $1.uuidString }
    }

    private func deptLabel(_ id: UUID) -> String {
        // We don't currently ship dept names with the view row — show a short
        // UUID prefix. Trivial to swap for a joined name in a future iteration.
        "PB " + String(id.uuidString.prefix(4))
    }

    private var presentCount: Int {
        rows.filter {
            let s = $0.derivedState
            return s == .present || s == .late || s == .flagged
        }.count
    }
    private var absentCount: Int { rows.filter { $0.derivedState == .absent }.count }
    private var flaggedCount: Int { rows.filter { $0.flaggedCount > 0 }.count }

    // MARK: - Formatting

    private func timeSummary(_ row: BranchEmployeeToday) -> String {
        let inStr = row.firstIn.flatMap(parseTime)
        let outStr = row.lastOut.flatMap(parseTime)
        switch (inStr, outStr) {
        case (nil, _):            return "Chưa vào"
        case (let i?, nil):       return "Vào \(i)"
        case (let i?, let o?):    return "Vào \(i) · Ra \(o)"
        }
    }

    private func parseTime(_ iso: String) -> String? {
        let formatters: [ISO8601DateFormatter] = [.supabase, ISO8601DateFormatter()]
        for f in formatters {
            if let date = f.date(from: iso) {
                return date.formatted(date: .omitted, time: .shortened)
            }
        }
        return nil
    }

    private func initials(from name: String) -> String {
        let parts = name
            .split(whereSeparator: { $0.isWhitespace })
            .prefix(2)
        let letters = parts.compactMap(\.first).map(String.init)
        return letters.joined().uppercased()
    }

    // MARK: - Network

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            rows = try await SupabaseManager.shared.client
                .from("branch_employee_today")
                .select()
                .order("full_name")
                .execute()
                .value
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
