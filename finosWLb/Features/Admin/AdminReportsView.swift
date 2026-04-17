import SwiftUI

/// Admin Reports — scope-switched (Day / Week / Month) attendance drill-downs
/// with CSV export and filter chips. Lives inside `AdminSettingsList`'s
/// navigation stack.
struct AdminReportsView: View {
    // Scope + anchor date
    @State private var scope: ReportScope
    @State private var anchorDate: Date
    @State private var selectedBranchId: UUID? = nil
    @State private var selectedDeptId: UUID? = nil

    // Lookups
    @State private var branches: [Branch] = []
    @State private var departments: [Department] = []

    // Data sets (one per scope)
    @State private var dayRows: [AttendanceDayRow] = []
    @State private var weekEvents: [ReportEvent] = []
    @State private var weekProfiles: [ReportProfile] = []
    @State private var monthSeries: [DailySeriesRow] = []

    @State private var isLoading = false
    @State private var errorMessage: String?

    // Export
    @State private var showExportSheet = false

    init(
        initialScope: ReportScope = .week,
        initialDate: Date = Date()
    ) {
        _scope = State(initialValue: initialScope)
        _anchorDate = State(initialValue: initialDate)
    }

    var body: some View {
        content
            .navigationTitle("Reports")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    exportMenu
                }
            }
            .sheet(isPresented: $showExportSheet) {
                ExportSheet(
                    title: exportTitle,
                    summary: exportSummary,
                    requestBody: exportRequestBody
                )
            }
            .task { await loadLookups() }
            // Debounced reload: any time the filter tuple changes, re-enter
            // the task, sleep 300ms (cancelled by SwiftUI if the tuple
            // changes again), then fetch. No Combine required.
            .task(id: filterKey) { await debouncedReload() }
    }

    // MARK: - Filter key for debounce

    /// Stable fingerprint of every input that should refetch. SwiftUI cancels
    /// the previous `.task(id:)` as soon as this value changes.
    private var filterKey: String {
        "\(scope.rawValue)|\(Int(anchorDate.timeIntervalSince1970))|\(selectedBranchId?.uuidString ?? "-")|\(selectedDeptId?.uuidString ?? "-")"
    }

    private func debouncedReload() async {
        do {
            try await Task.sleep(for: .milliseconds(300))
        } catch { return }
        await load()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 12) {
            ScopePicker(scope: $scope)
                .padding(.horizontal, 16)
            DateScopeStepper(date: $anchorDate, scope: scope)
                .padding(.horizontal, 16)
            filterChips
                .padding(.horizontal, 16)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
            }

            scopeBody
        }
    }

    @ViewBuilder
    private var scopeBody: some View {
        switch scope {
        case .day:   dayView
        case .week:  weekView
        case .month: monthView
        }
    }

    // MARK: - Filter chips

    private var filterChips: some View {
        HStack(spacing: 8) {
            branchChip
            deptChip
            Spacer(minLength: 0)
        }
    }

    private var branchChip: some View {
        // Menu + sibling clear Button. Nesting a Button inside a Menu's label
        // swallows the inner tap (the Menu intercepts first), so the clear
        // affordance lives next to the Menu instead of on top of it.
        HStack(spacing: 4) {
            Menu {
                Button {
                    selectedBranchId = nil
                } label: {
                    Label("All branches", systemImage: selectedBranchId == nil ? "checkmark" : "")
                }
                Divider()
                ForEach(branches) { b in
                    Button {
                        selectedBranchId = b.id
                    } label: {
                        Label(b.name, systemImage: selectedBranchId == b.id ? "checkmark" : "")
                    }
                }
            } label: {
                chipLabel(
                    icon: "building.2",
                    text: selectedBranchId.flatMap { id in branches.first { $0.id == id }?.name } ?? "All branches",
                    isActive: selectedBranchId != nil
                )
            }
            if selectedBranchId != nil {
                Button {
                    selectedBranchId = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear branch filter")
            }
        }
    }

    private var deptChip: some View {
        HStack(spacing: 4) {
            Menu {
                Button {
                    selectedDeptId = nil
                } label: {
                    Label("All departments", systemImage: selectedDeptId == nil ? "checkmark" : "")
                }
                Divider()
                ForEach(departments) { d in
                    Button {
                        selectedDeptId = d.id
                    } label: {
                        Label(d.name, systemImage: selectedDeptId == d.id ? "checkmark" : "")
                    }
                }
            } label: {
                chipLabel(
                    icon: "rectangle.3.group",
                    text: selectedDeptId.flatMap { id in departments.first { $0.id == id }?.name } ?? "All depts",
                    isActive: selectedDeptId != nil
                )
            }
            if selectedDeptId != nil {
                Button {
                    selectedDeptId = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear department filter")
            }
        }
    }

    private func chipLabel(
        icon: String,
        text: String,
        isActive: Bool
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption)
            Text(text).font(.subheadline).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(isActive ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
        )
        .foregroundStyle(isActive ? Color.accentColor : Color.primary)
    }

    // MARK: - Export menu

    private var exportMenu: some View {
        Menu {
            Button {
                showExportSheet = true
            } label: {
                Label("Export CSV…", systemImage: "square.and.arrow.down")
            }
            ShareLink(item: shareSummary) {
                Label("Share summary", systemImage: "text.bubble")
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
    }

    // MARK: - Day view

    @ViewBuilder
    private var dayView: some View {
        if isLoading && dayRows.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if dayRows.isEmpty {
            ContentUnavailableView(
                "No attendance for this day",
                systemImage: "calendar",
                description: Text("Try a different date or clear filters.")
            )
        } else {
            List {
                ForEach(AttendanceEventStatus.dayDisplayOrder, id: \.self) { status in
                    let rows = dayRows.filter { $0.status == status }
                    if !rows.isEmpty {
                        Section("\(status.label) (\(rows.count))") {
                            ForEach(rows) { row in
                                dayRowView(row)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func dayRowView(_ row: AttendanceDayRow) -> some View {
        let name = weekProfiles.first { $0.id == row.employeeId }?.fullName ?? "—"
        return HStack(spacing: 12) {
            avatar(for: name)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline)
                Text(dayTimeSummary(row))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(status: row.status)
        }
        .padding(.vertical, 2)
    }

    private func avatar(for name: String) -> some View {
        Circle()
            .fill(Color.accentColor.opacity(0.15))
            .frame(width: 32, height: 32)
            .overlay {
                Text(initials(from: name))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
            }
    }

    private func dayTimeSummary(_ row: AttendanceDayRow) -> String {
        let inStr = row.firstIn.flatMap(parseTime) ?? "—"
        let outStr = row.lastOut.flatMap(parseTime) ?? "—"
        var parts = ["\(inStr) – \(outStr)"]
        if let worked = row.workedMin {
            parts.append("worked \(hm(worked))")
        }
        if let ot = row.overtimeMin, ot > 0 {
            parts.append("OT \(hm(ot))")
        }
        return parts.joined(separator: " · ")
    }

    private func parseTime(_ iso: String) -> String? {
        let formatters: [ISO8601DateFormatter] = [.supabase, ISO8601DateFormatter()]
        for f in formatters {
            if let d = f.date(from: iso) {
                return d.formatted(date: .omitted, time: .shortened)
            }
        }
        return nil
    }

    private func hm(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return "\(h)h \(String(format: "%02d", m))m"
    }

    private func initials(from name: String) -> String {
        let parts = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        return parts.compactMap(\.first).map(String.init).joined().uppercased()
    }

    // MARK: - Week view

    @ViewBuilder
    private var weekView: some View {
        if isLoading && weekProfiles.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if weekProfiles.isEmpty {
            ContentUnavailableView(
                "No employees",
                systemImage: "person.2",
                description: Text("Adjust your filters or assign employees.")
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                    if selectedBranchId == nil {
                        ForEach(branches) { branch in
                            let inBranch = weekProfiles.filter { $0.branchId == branch.id }
                            if !inBranch.isEmpty {
                                Section {
                                    // TODO(phase-6): 50-employee cap per branch.
                                    // Deliberate, pending a server-side pagination contract.
                                    weekGrid(for: Array(topN(inBranch, limit: 50)))
                                        .padding(.horizontal, 16)
                                } header: {
                                    Text(branch.name)
                                        .font(.headline)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 6)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(.regularMaterial)
                                }
                            }
                        }
                    } else {
                        weekGrid(for: weekProfiles)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    /// Rank by descending event count, then stable name — mirrors how the
    /// manager view implicitly sorts. The cap is an iOS-side safety net; a
    /// future server-paged version will remove the need for it.
    private func topN(_ profiles: [ReportProfile], limit: Int) -> [ReportProfile] {
        let counts = Dictionary(grouping: weekEvents, by: \.employeeId)
            .mapValues(\.count)
        return profiles
            .sorted {
                let a = counts[$0.id] ?? 0
                let b = counts[$1.id] ?? 0
                if a != b { return a > b }
                return $0.fullName < $1.fullName
            }
            .prefix(limit)
            .map { $0 }
    }

    private func weekGrid(for profiles: [ReportProfile]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                Text("").frame(width: 120, alignment: .leading)
                ForEach(weekDays, id: \.self) { day in
                    VStack(spacing: 0) {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2).fontWeight(.semibold)
                        Text(day.formatted(.dateTime.day()))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Divider()
            ForEach(profiles) { profile in
                GridRow {
                    Text(profile.fullName)
                        .font(.subheadline)
                        .frame(width: 120, alignment: .leading)
                        .lineLimit(1)
                    ForEach(weekDays, id: \.self) { day in
                        weekDot(for: profile, day: day)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func weekDot(for profile: ReportProfile, day: Date) -> some View {
        let status = weekCellStatus(employeeId: profile.id, day: day)
        return Circle()
            .fill(colorFor(status))
            .frame(width: 18, height: 18)
            .accessibilityLabel(
                "\(profile.fullName) \(day.formatted(.dateTime.weekday(.abbreviated))): \(status.label)"
            )
    }

    private func colorFor(_ s: WeekCellStatus) -> Color {
        switch s {
        case .onTime:    .green
        case .late:      .orange
        case .flagged:   .yellow
        case .rejected:  .red
        case .absent:    .gray.opacity(0.4)
        case .future:    .gray.opacity(0.15)
        case .none:      .clear
        }
    }

    private func weekCellStatus(employeeId: UUID, day: Date) -> WeekCellStatus {
        let eventsOnDay = weekEvents.filter {
            guard let d = $0.serverTsDate else { return false }
            return Calendar.current.isDate(d, inSameDayAs: day)
                && $0.employeeId == employeeId
        }
        let today = Calendar.current.startOfDay(for: Date())
        if Calendar.current.startOfDay(for: day) > today { return .future }
        if eventsOnDay.isEmpty { return .absent }

        let statuses = Set(eventsOnDay.map(\.status))
        if statuses.contains(.rejected) { return .rejected }
        if statuses.contains(.flagged) { return .flagged }
        if statuses.contains(.late) { return .late }
        return .onTime
    }

    private var weekDays: [Date] {
        let start = DateScopeStepper.startOfWeek(anchorDate)
        return (0..<5).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: start)
        }
    }

    // MARK: - Month view

    @ViewBuilder
    private var monthView: some View {
        if isLoading && monthSeries.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if monthSeries.isEmpty {
            ContentUnavailableView(
                "No data for this month",
                systemImage: "calendar",
                description: Text("Try a different month or clear filters.")
            )
        } else {
            ScrollView {
                monthHeatmap
                    .padding(16)
            }
        }
    }

    private var monthHeatmap: some View {
        let cal = Calendar.current
        let first = cal.date(from: cal.dateComponents([.year, .month], from: anchorDate)) ?? anchorDate
        let daysInMonth = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let cells: [Date] = (0..<daysInMonth).compactMap {
            cal.date(byAdding: .day, value: $0, to: first)
        }

        let weekdayOfFirst = cal.component(.weekday, from: first)  // 1=Sun
        let leadingBlanks = weekdayOfFirst - 1

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                ForEach(["S","M","T","W","T","F","S"], id: \.self) { letter in
                    Text(letter).font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(
                columns: [GridItem](repeating: .init(.flexible(), spacing: 4), count: 7),
                spacing: 4
            ) {
                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: 36)
                }
                ForEach(cells, id: \.self) { day in
                    monthCell(day)
                }
            }
            Text("Tint = attendance rate (present / total)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func monthCell(_ day: Date) -> some View {
        let dayString = ISO8601Date.format(day)
        let row = monthSeries.first { $0.date == dayString }
        let rate = row.map { rate in
            let total = rate.total
            return total > 0 ? Double(rate.present) / Double(total) : 0
        } ?? 0

        return Button {
            anchorDate = day
            scope = .day
        } label: {
            VStack(spacing: 2) {
                Text(day.formatted(.dateTime.day()))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(rate > 0.55 ? .white : .primary)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.1 + (rate * 0.7)))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(day.formatted(date: .abbreviated, time: .omitted)), attendance \(Int(rate * 100))%"
        )
    }

    // MARK: - Export & share text

    private var exportRequestBody: ExportReportBody {
        let (from, to) = scopeRange()
        return ExportReportBody(
            reportType: scope.exportType,
            from: ISO8601Date.format(from),
            to: ISO8601Date.format(to),
            branchId: selectedBranchId,
            deptId: selectedDeptId
        )
    }

    private var exportTitle: String {
        switch scope {
        case .day:   "Daily report"
        case .week:  "Weekly report"
        case .month: "Monthly report"
        }
    }

    private var exportSummary: String {
        let (from, to) = scopeRange()
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        let range = "\(fmt.string(from: from)) – \(fmt.string(from: to))"
        let branch = selectedBranchId.flatMap { id in branches.first { $0.id == id }?.name } ?? "All branches"
        let dept = selectedDeptId.flatMap { id in departments.first { $0.id == id }?.name } ?? "All depts"
        return "\(range) · \(branch) · \(dept)"
    }

    private var shareSummary: String {
        switch scope {
        case .day:
            let counts = Dictionary(grouping: dayRows, by: \.status).mapValues(\.count)
            let date = anchorDate.formatted(date: .complete, time: .omitted)
            return """
            Attendance — \(date)
            On time: \(counts[.onTime] ?? 0)
            Late: \(counts[.late] ?? 0)
            Flagged: \(counts[.flagged] ?? 0)
            Absent: \(counts[.absent] ?? 0)
            """
        case .week:
            let late = weekEvents.filter { $0.status == .late }.count
            let flagged = weekEvents.filter { $0.status == .flagged }.count
            return "Week of \(DateScopeStepper.startOfWeek(anchorDate).formatted(date: .abbreviated, time: .omitted))\nLate: \(late)  Flagged: \(flagged)  Total events: \(weekEvents.count)"
        case .month:
            let on = monthSeries.reduce(0) { $0 + $1.onTime }
            let late = monthSeries.reduce(0) { $0 + $1.late }
            let flag = monthSeries.reduce(0) { $0 + $1.flagged }
            let abs = monthSeries.reduce(0) { $0 + $1.absent }
            let mo = anchorDate.formatted(.dateTime.month(.wide).year())
            return "Attendance — \(mo)\nOn time: \(on)\nLate: \(late)\nFlagged: \(flag)\nAbsent: \(abs)"
        }
    }

    private func scopeRange() -> (Date, Date) {
        let cal = Calendar.current
        switch scope {
        case .day:
            return (anchorDate, anchorDate)
        case .week:
            let start = DateScopeStepper.startOfWeek(anchorDate)
            let end = cal.date(byAdding: .day, value: 6, to: start) ?? start
            return (start, end)
        case .month:
            let start = cal.date(from: cal.dateComponents([.year, .month], from: anchorDate)) ?? anchorDate
            let days = cal.range(of: .day, in: .month, for: start)?.count ?? 30
            let end = cal.date(byAdding: .day, value: days - 1, to: start) ?? start
            return (start, end)
        }
    }

    // MARK: - Networking

    private func loadLookups() async {
        do {
            async let b: [Branch] = SupabaseManager.shared.client
                .from("branches")
                .select("id, name, tz, address, radius_m")
                .order("name")
                .execute()
                .value
            async let d: [Department] = SupabaseManager.shared.client
                .from("departments")
                .select("id, name")
                .order("name")
                .execute()
                .value
            let (bb, dd) = try await (b, d)
            branches = bb
            departments = dd
        } catch {
            // Swallow — lookup failure shouldn't block the main query.
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            switch scope {
            case .day:   try await loadDay()
            case .week:  try await loadWeek()
            case .month: try await loadMonth()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadDay() async throws {
        let dateStr = ISO8601Date.format(anchorDate)
        var query = SupabaseManager.shared.client
            .from("attendance_days")
            .select("employee_id, date, branch_id, first_in, last_out, worked_min, overtime_min, status")
            .eq("date", value: dateStr)
        if let b = selectedBranchId {
            query = query.eq("branch_id", value: b.uuidString)
        }
        dayRows = try await query.execute().value

        // Also fetch profile names so we can render the row labels. Separate
        // query avoids forcing a Supabase relation join.
        let employeeIds = dayRows.map(\.employeeId)
        if !employeeIds.isEmpty {
            let ids = employeeIds.map(\.uuidString)
            weekProfiles = try await SupabaseManager.shared.client
                .from("profiles")
                .select("id, full_name, branch_id")
                .in("id", values: ids)
                .execute()
                .value
        } else {
            weekProfiles = []
        }
    }

    private func loadWeek() async throws {
        let start = DateScopeStepper.startOfWeek(anchorDate)
        guard let end = Calendar.current.date(byAdding: .day, value: 7, to: start) else { return }
        let startISO = ISO8601DateFormatter.supabase.string(from: start)
        let endISO = ISO8601DateFormatter.supabase.string(from: end)

        // Supabase's builder tightens its type after `.order()` — once you
        // call a transform method you can't add filters back on. Build the
        // filter chain first, then apply `.order` at the end.
        var filterChain = SupabaseManager.shared.client
            .from("profiles")
            .select("id, full_name, branch_id")
            .eq("role", value: "employee")
            .eq("active", value: true)
        if let b = selectedBranchId {
            filterChain = filterChain.eq("branch_id", value: b.uuidString)
        }
        if let d = selectedDeptId {
            filterChain = filterChain.eq("dept_id", value: d.uuidString)
        }
        async let profilesReq: [ReportProfile] = filterChain
            .order("full_name")
            .execute()
            .value
        async let eventsReq: [ReportEvent] = SupabaseManager.shared.client
            .from("attendance_events")
            .select("id, employee_id, server_ts, status")
            .gte("server_ts", value: startISO)
            .lt("server_ts", value: endISO)
            .execute()
            .value

        let (p, e) = try await (profilesReq, eventsReq)
        weekProfiles = p
        weekEvents = e
    }

    private func loadMonth() async throws {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: anchorDate)) ?? anchorDate
        let days = cal.range(of: .day, in: .month, for: start)?.count ?? 30
        let end = cal.date(byAdding: .day, value: days - 1, to: start) ?? start
        monthSeries = try await SupabaseManager.shared.client
            .rpc("daily_series", params: DailySeriesParams(
                p_from: ISO8601Date.format(start),
                p_to: ISO8601Date.format(end),
                p_branch_id: selectedBranchId,
                p_dept_id: selectedDeptId
            ))
            .execute()
            .value
    }
}

// MARK: - Shared report DTOs

/// Employee DTO for report screens. Carries `branchId` so the week view can
/// group by branch when no branch filter is active.
struct ReportProfile: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let fullName: String
    let branchId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case branchId = "branch_id"
    }
}

/// Lightweight event DTO for the week grid. Mirrors the private one inside
/// `ManagerReportsView`; promoting it to module scope lets admin + manager
/// share the grid logic.
struct ReportEvent: Codable, Hashable, Sendable {
    let id: UUID
    let employeeId: UUID
    let serverTs: String
    let status: AttendanceEventStatus

    enum CodingKeys: String, CodingKey {
        case id, status
        case employeeId = "employee_id"
        case serverTs = "server_ts"
    }

    var serverTsDate: Date? {
        let formatters: [ISO8601DateFormatter] = [.supabase, ISO8601DateFormatter()]
        for f in formatters {
            if let d = f.date(from: serverTs) { return d }
        }
        return nil
    }
}

/// Week-grid cell status. Module-scope so both report screens agree on the
/// visual vocabulary.
enum WeekCellStatus: Hashable {
    case onTime, late, flagged, rejected, absent, future, none

    var label: String {
        switch self {
        case .onTime:    "On time"
        case .late:      "Late"
        case .flagged:   "Flagged"
        case .rejected:  "Rejected"
        case .absent:    "Absent"
        case .future:    "Upcoming"
        case .none:      "No data"
        }
    }

    var shortLabel: String {
        switch self {
        case .onTime:    "on-time"
        case .late:      "late"
        case .flagged:   "flagged"
        case .rejected:  "rejected"
        case .absent:    "absent"
        case .future:    "—"
        case .none:      "—"
        }
    }
}

// MARK: - AttendanceEventStatus ordering helper

extension AttendanceEventStatus {
    /// Day view section order — fixed, not alphabetical, so managers scan
    /// "who needs attention" first.
    static let dayDisplayOrder: [AttendanceEventStatus] = [
        .flagged, .late, .absent, .onTime,
    ]
}

// MARK: - DailySeriesRow helper for present count

private extension DailySeriesRow {
    /// "Present" for the heatmap = anyone who wasn't absent.
    var present: Int { onTime + late + flagged }
}
