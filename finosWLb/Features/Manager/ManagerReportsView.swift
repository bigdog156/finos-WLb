import SwiftUI
import Supabase

/// Manager Reports — scope-switchable attendance view (Day / Week / Month)
/// scoped to the manager's branch via RLS. Shares the admin reports DTOs
/// (`ReportProfile`, `ReportEvent`, `WeekCellStatus`) plus the Phase 6
/// shared components (`ScopePicker`, `DateScopeStepper`, `ExportSheet`).
struct ManagerReportsView: View {
    @State private var scope: ReportScope = .week
    @State private var anchorDate: Date = Date()

    @State private var profiles: [ReportProfile] = []
    @State private var events: [ReportEvent] = []
    @State private var dayRows: [AttendanceDayRow] = []
    @State private var monthSeries: [DailySeriesRow] = []

    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var showExportSheet = false
    @State private var popoverCell: PopoverCell?

    private static let mondayCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.timeZone = .current
        return cal
    }()

    var body: some View {
        content
            .navigationTitle("Reports")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showExportSheet = true
                        } label: {
                            Label("Export CSV…", systemImage: "square.and.arrow.down")
                        }
                        ShareLink(item: summaryText()) {
                            Label("Share summary", systemImage: "text.bubble")
                        }
                        .disabled(scope != .week)
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showExportSheet) {
                ExportSheet(
                    title: exportTitle,
                    summary: exportSummary,
                    requestBody: exportRequestBody
                )
            }
            .task(id: filterKey) { await debouncedLoad() }
            .refreshable { await load() }
    }

    // MARK: - Filter key + debounce

    private var filterKey: String {
        "\(scope.rawValue)|\(Int(anchorDate.timeIntervalSince1970))"
    }

    private func debouncedLoad() async {
        do {
            try await Task.sleep(for: .milliseconds(200))
        } catch { return }
        await load()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading && profiles.isEmpty && dayRows.isEmpty && monthSeries.isEmpty {
            ProgressView()
        } else if let errorMessage, profiles.isEmpty, dayRows.isEmpty, monthSeries.isEmpty {
            ContentUnavailableView(
                "Couldn't load reports",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    ScopePicker(scope: $scope)
                    DateScopeStepper(date: $anchorDate, scope: scope)
                    summaryStrip
                    scopeBody
                }
                .padding(16)
            }
        }
    }

    @ViewBuilder
    private var scopeBody: some View {
        switch scope {
        case .day:   dayBody
        case .week:  weekBody
        case .month: monthBody
        }
    }

    // MARK: - Summary strip (adapts to scope)

    @ViewBuilder
    private var summaryStrip: some View {
        let tiles: [(String, Int)] = {
            switch scope {
            case .day:
                let byStatus = Dictionary(grouping: dayRows, by: \.status).mapValues(\.count)
                return [
                    ("Present", dayRows.filter { $0.status != .absent }.count),
                    ("Late",    byStatus[.late] ?? 0),
                    ("Flagged", byStatus[.flagged] ?? 0),
                ]
            case .week:
                return [
                    ("Late events", events.filter { $0.status == .late }.count),
                    ("Absences",    absentDays),
                    ("Total",       events.count),
                ]
            case .month:
                return [
                    ("On time", monthSeries.reduce(0) { $0 + $1.onTime }),
                    ("Late",    monthSeries.reduce(0) { $0 + $1.late }),
                    ("Absent",  monthSeries.reduce(0) { $0 + $1.absent }),
                ]
            }
        }()
        HStack(spacing: 12) {
            ForEach(tiles, id: \.0) { tile in
                KPITile(title: tile.0, value: tile.1)
            }
        }
    }

    // MARK: - Day body

    @ViewBuilder
    private var dayBody: some View {
        if dayRows.isEmpty {
            ContentUnavailableView(
                "No attendance",
                systemImage: "calendar",
                description: Text("No employees have activity for \(anchorDate.formatted(date: .abbreviated, time: .omitted)).")
            )
            .padding(.top, 24)
        } else {
            VStack(spacing: 12) {
                ForEach(AttendanceEventStatus.dayDisplayOrder, id: \.self) { status in
                    let rows = dayRows.filter { $0.status == status }
                    if !rows.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(status.label) (\(rows.count))")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 6)
                            ForEach(rows) { row in
                                dayRow(row)
                                Divider()
                            }
                        }
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    private func dayRow(_ row: AttendanceDayRow) -> some View {
        let name = profiles.first { $0.id == row.employeeId }?.fullName ?? "Employee"
        return NavigationLink {
            EmployeeDayDetailView(
                employeeId: row.employeeId,
                fullName: name,
                date: row.parsedDate ?? anchorDate
            )
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                    .overlay { Text(initials(name)).font(.caption2.weight(.semibold)) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.subheadline).fontWeight(.semibold)
                    Text(dayTimeSummary(row))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(status: row.status)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func dayTimeSummary(_ row: AttendanceDayRow) -> String {
        let inStr = row.firstIn.flatMap(parseTime) ?? "—"
        let outStr = row.lastOut.flatMap(parseTime) ?? "—"
        var parts = ["\(inStr) – \(outStr)"]
        if let w = row.workedMin { parts.append("worked \(hm(w))") }
        if let ot = row.overtimeMin, ot > 0 { parts.append("OT \(hm(ot))") }
        return parts.joined(separator: " · ")
    }

    private func hm(_ minutes: Int) -> String {
        "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }

    // MARK: - Week body (existing Mon–Fri grid)

    @ViewBuilder
    private var weekBody: some View {
        if profiles.isEmpty {
            ContentUnavailableView(
                "No employees yet",
                systemImage: "person.2",
                description: Text("Assign employees to this branch from Admin.")
            )
        } else {
            weekGrid
        }
    }

    private var weekGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                Text("")
                    .frame(width: 120, alignment: .leading)
                ForEach(weekDays, id: \.self) { day in
                    VStack(spacing: 2) {
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
                    NavigationLink {
                        EmployeeDayDetailView(
                            employeeId: profile.id,
                            fullName: profile.fullName,
                            date: Date()
                        )
                    } label: {
                        Text(profile.fullName)
                            .font(.subheadline)
                            .frame(width: 120, alignment: .leading)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)

                    ForEach(weekDays, id: \.self) { day in
                        dot(for: profile, day: day)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func dot(for profile: ReportProfile, day: Date) -> some View {
        let status = cellStatus(employeeId: profile.id, day: day)
        let cellId = "\(profile.id.uuidString)-\(Self.mondayCalendar.startOfDay(for: day).timeIntervalSince1970)"
        Button {
            popoverCell = PopoverCell(
                id: cellId,
                employeeName: profile.fullName,
                day: day,
                status: status
            )
        } label: {
            Circle()
                .fill(colorFor(status))
                .frame(width: 28, height: 28)
                .overlay(
                    Circle().strokeBorder(.white.opacity(0.6), lineWidth: status == .none ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(status == .none)
        .popover(
            isPresented: Binding(
                get: { popoverCell?.id == cellId },
                set: { if !$0 { popoverCell = nil } }
            )
        ) {
            popoverContent(profile: profile, day: day, status: status)
        }
        .accessibilityLabel("\(profile.fullName), \(day.formatted(date: .abbreviated, time: .omitted)), \(status.label)")
    }

    private func popoverContent(profile: ReportProfile, day: Date, status: WeekCellStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(profile.fullName).font(.headline)
            Text(day.formatted(date: .complete, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Circle().fill(colorFor(status)).frame(width: 10, height: 10)
                Text(status.label)
            }
            if status != .none && status != .future {
                NavigationLink {
                    EmployeeDayDetailView(
                        employeeId: profile.id,
                        fullName: profile.fullName,
                        date: day
                    )
                } label: {
                    Label("View events", systemImage: "arrow.right.circle")
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .presentationCompactAdaptation(.popover)
    }

    private func cellStatus(employeeId: UUID, day: Date) -> WeekCellStatus {
        let normalizedDay = Self.mondayCalendar.startOfDay(for: day)
        let today = Self.mondayCalendar.startOfDay(for: Date())
        if normalizedDay > today { return .future }

        let eventsOnDay = events.filter {
            $0.employeeId == employeeId &&
            Self.mondayCalendar.isDate($0.serverTsDate ?? .distantPast, inSameDayAs: day)
        }
        if eventsOnDay.isEmpty { return .absent }

        let statuses = Set(eventsOnDay.map(\.status))
        if statuses.contains(.rejected) { return .rejected }
        if statuses.contains(.flagged) { return .flagged }
        if statuses.contains(.late) { return .late }
        return .onTime
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

    private var weekDays: [Date] {
        let start = DateScopeStepper.startOfWeek(anchorDate)
        return (0..<5).compactMap {
            Self.mondayCalendar.date(byAdding: .day, value: $0, to: start)
        }
    }

    private var absentDays: Int {
        profiles.reduce(0) { acc, profile in
            acc + weekDays.filter { cellStatus(employeeId: profile.id, day: $0) == .absent }.count
        }
    }

    // MARK: - Month body

    @ViewBuilder
    private var monthBody: some View {
        if profiles.isEmpty {
            ContentUnavailableView(
                "No employees yet",
                systemImage: "person.2",
                description: Text("Assign employees to this branch from Admin.")
            )
        } else {
            VStack(spacing: 12) {
                ForEach(profiles) { profile in
                    monthRow(profile)
                }
            }
        }
    }

    private func monthRow(_ profile: ReportProfile) -> some View {
        let cal = Calendar.current
        let first = cal.date(from: cal.dateComponents([.year, .month], from: anchorDate)) ?? anchorDate
        let daysInMonth = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let days: [Date] = (0..<daysInMonth).compactMap {
            cal.date(byAdding: .day, value: $0, to: first)
        }

        // Aggregate per-day status from events for this employee.
        let byDay: [Date: WeekCellStatus] = Dictionary(uniqueKeysWithValues:
            days.map { day in
                (cal.startOfDay(for: day), cellStatus(employeeId: profile.id, day: day))
            }
        )

        let presentCount = byDay.values.filter { $0 == .onTime || $0 == .late || $0 == .flagged }.count
        let lateCount = byDay.values.filter { $0 == .late }.count
        let flagCount = byDay.values.filter { $0 == .flagged }.count
        let otMinutes = 0    // Overtime is recorded on attendance_days; the
                              // month mini-calendar is event-driven, so OT
                              // is shown only when it's available from a
                              // monthly attendance_days fetch (future).

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(profile.fullName).font(.subheadline).fontWeight(.semibold)
                Spacer()
                Text("P \(presentCount) · L \(lateCount) · F \(flagCount) · OT \(otMinutes / 60)h")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(
                columns: [GridItem](repeating: .init(.flexible(), spacing: 4), count: 7),
                spacing: 4
            ) {
                ForEach(days, id: \.self) { day in
                    Circle()
                        .fill(colorFor(byDay[cal.startOfDay(for: day)] ?? .none))
                        .frame(width: 14, height: 14)
                        .accessibilityLabel(
                            "\(day.formatted(date: .abbreviated, time: .omitted)): \((byDay[cal.startOfDay(for: day)] ?? .none).label)"
                        )
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Share text (week-only)

    private func summaryText() -> String {
        let start = DateScopeStepper.startOfWeek(anchorDate)
        let end = Self.mondayCalendar.date(byAdding: .day, value: 6, to: start) ?? start
        let range = DateIntervalFormatter()
        range.dateStyle = .medium
        range.timeStyle = .none
        let label = range.string(from: start, to: end) ?? ""
        var lines: [String] = []
        lines.append("Week of \(label)")
        lines.append("Late: \(events.filter { $0.status == .late }.count)  Absent: \(absentDays)  Total: \(events.count)")
        lines.append("")
        for profile in profiles {
            var parts: [String] = []
            for day in weekDays {
                let status = cellStatus(employeeId: profile.id, day: day)
                guard status != .none, status != .future else { continue }
                let d = day.formatted(.dateTime.weekday(.abbreviated))
                parts.append("\(d) \(status.shortLabel)")
            }
            if !parts.isEmpty {
                lines.append("\(profile.fullName): \(parts.joined(separator: ", "))")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Export helpers

    private var exportRequestBody: ExportReportBody {
        let (from, to) = scopeRange()
        return ExportReportBody(
            reportType: scope.exportType,
            from: ISO8601Date.format(from),
            to: ISO8601Date.format(to),
            branchId: nil,      // EF auto-scopes the manager; sending nil is correct
            deptId: nil
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
        let f = DateFormatter(); f.dateStyle = .medium
        return "\(f.string(from: from)) – \(f.string(from: to)) · Your branch"
    }

    private func scopeRange() -> (Date, Date) {
        let cal = Calendar.current
        switch scope {
        case .day:
            return (anchorDate, anchorDate)
        case .week:
            let s = DateScopeStepper.startOfWeek(anchorDate)
            let e = cal.date(byAdding: .day, value: 6, to: s) ?? s
            return (s, e)
        case .month:
            let s = cal.date(from: cal.dateComponents([.year, .month], from: anchorDate)) ?? anchorDate
            let days = cal.range(of: .day, in: .month, for: s)?.count ?? 30
            let e = cal.date(byAdding: .day, value: days - 1, to: s) ?? s
            return (s, e)
        }
    }

    // MARK: - Networking

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
        dayRows = try await SupabaseManager.shared.client
            .from("attendance_days")
            .select("employee_id, date, branch_id, first_in, last_out, worked_min, overtime_min, status")
            .eq("date", value: dateStr)
            .execute()
            .value

        // Profile names for row labels.
        let employeeIds = dayRows.map(\.employeeId)
        if !employeeIds.isEmpty {
            profiles = try await SupabaseManager.shared.client
                .from("profiles")
                .select("id, full_name, branch_id")
                .in("id", values: employeeIds.map(\.uuidString))
                .execute()
                .value
        }
    }

    private func loadWeek() async throws {
        let start = DateScopeStepper.startOfWeek(anchorDate)
        guard let end = Self.mondayCalendar.date(byAdding: .day, value: 7, to: start) else { return }
        let startISO = ISO8601DateFormatter.supabase.string(from: start)
        let endISO = ISO8601DateFormatter.supabase.string(from: end)

        async let profilesReq: [ReportProfile] = SupabaseManager.shared.client
            .from("profiles")
            .select("id, full_name, branch_id")
            .eq("role", value: "employee")
            .eq("active", value: true)
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
        profiles = p
        events = e
    }

    private func loadMonth() async throws {
        // Month view needs *both* the per-employee event stream (for the
        // mini-calendar dots) and the aggregate series (for the summary
        // strip totals).
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: anchorDate)) ?? anchorDate
        let days = cal.range(of: .day, in: .month, for: start)?.count ?? 30
        guard let end = cal.date(byAdding: .day, value: days, to: start) else { return }

        let startISO = ISO8601DateFormatter.supabase.string(from: start)
        let endISO = ISO8601DateFormatter.supabase.string(from: end)

        async let profilesReq: [ReportProfile] = SupabaseManager.shared.client
            .from("profiles")
            .select("id, full_name, branch_id")
            .eq("role", value: "employee")
            .eq("active", value: true)
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

        async let seriesReq: [DailySeriesRow] = SupabaseManager.shared.client
            .rpc("daily_series", params: DailySeriesParams(
                p_from: ISO8601Date.format(start),
                p_to: ISO8601Date.format(cal.date(byAdding: .day, value: -1, to: end) ?? start),
                p_branch_id: nil,    // manager is auto-scoped by RLS
                p_dept_id: nil
            ))
            .execute()
            .value

        let (p, e, s) = try await (profilesReq, eventsReq, seriesReq)
        profiles = p
        events = e
        monthSeries = s
    }

    // MARK: - Format helpers

    private func parseTime(_ iso: String) -> String? {
        let formatters: [ISO8601DateFormatter] = [.supabase, ISO8601DateFormatter()]
        for f in formatters {
            if let d = f.date(from: iso) {
                return d.formatted(date: .omitted, time: .shortened)
            }
        }
        return nil
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        return parts.compactMap(\.first).map(String.init).joined().uppercased()
    }
}

// MARK: - Supporting private types

private struct PopoverCell: Hashable, Identifiable {
    let id: String
    let employeeName: String
    let day: Date
    let status: WeekCellStatus
}
