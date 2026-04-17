import SwiftUI
import Charts
import Supabase
internal import PostgREST

/// Admin dashboard — today's KPI strip, a 30-day stacked-status chart, and a
/// per-branch breakdown. Designed to live inside `AdminSettingsList`'s
/// existing `NavigationStack`, so we do not introduce our own.
struct AdminDashboardView: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass

    // KPI + chart state
    @State private var today: DashboardToday?
    @State private var byBranch: [BranchKPI] = []
    @State private var series: [DailySeriesRow] = []
    @State private var selectedDeptId: UUID? = nil
    @State private var departments: [Department] = []

    // Range picker. Today/7d/30d are preset; .custom opens a sheet with two
    // DatePickers. All four map onto a (from, to) pair before the RPC call.
    enum RangePreset: String, CaseIterable, Identifiable, Hashable {
        case today, sevenDay, thirtyDay, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .today:     "Today"
            case .sevenDay:  "7d"
            case .thirtyDay: "30d"
            case .custom:    "Custom"
            }
        }
    }
    @State private var rangePreset: RangePreset = .thirtyDay
    @State private var customFrom: Date = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
    @State private var customTo: Date = Date()
    @State private var showingCustomSheet = false

    // Navigation: tapping a chart bar pushes AdminReportsView seeded to that day.
    @State private var drillDate: Date?

    // Sparkline cache: branch id → last-14-day on-time rate series.
    // Populated concurrently once `byBranch` loads (N+1 query, N is small).
    @State private var sparkByBranch: [UUID: [DailySeriesRow]] = [:]

    // Ambient state
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var lastLoadAt: Date?

    private static let subtitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    var body: some View {
        content
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("Dashboard").font(.headline)
                        Text(Self.subtitleFormatter.string(from: Date()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    departmentFilter
                }
            }
            .task { await loadIfStale() }
            .refreshable { await load() }
            .onChange(of: selectedDeptId) { _, _ in
                Task { await load() }
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let errorMessage, today == nil {
            ContentUnavailableView {
                Label("Couldn't load dashboard", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try again") { Task { await load() } }
                    .buttonStyle(.borderedProminent)
            }
        } else if today == nil && isLoading {
            ScrollView {
                VStack(spacing: 16) {
                    kpiSkeleton
                    chartSkeleton
                    branchSkeleton
                }
                .padding(16)
            }
        } else if let today, today.totalEmployees == 0 {
            ContentUnavailableView(
                "No employees yet",
                systemImage: "person.3",
                description: Text("Invite employees from Admin → Users to populate the dashboard.")
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let today { kpiStrip(today) }
                    rangeBar
                    primaryChart
                    branchBreakdown
                }
                .padding(16)
            }
            .navigationDestination(
                isPresented: Binding(
                    get: { drillDate != nil },
                    set: { if !$0 { drillDate = nil } }
                )
            ) {
                if let drillDate {
                    AdminReportsView(initialScope: .day, initialDate: drillDate)
                }
            }
            .sheet(isPresented: $showingCustomSheet) {
                customRangeSheet
                    .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Range bar (segmented presets + custom)

    private var rangeBar: some View {
        HStack(spacing: 8) {
            Picker("Range", selection: $rangePreset) {
                ForEach(RangePreset.allCases) { p in
                    Text(p.label).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: rangePreset) { _, new in
                if new == .custom {
                    showingCustomSheet = true
                } else {
                    Task { await load() }
                }
            }
        }
    }

    @ViewBuilder
    private var customRangeSheet: some View {
        NavigationStack {
            Form {
                DatePicker("From",
                           selection: $customFrom,
                           in: ...Date(),
                           displayedComponents: .date)
                DatePicker("To",
                           selection: $customTo,
                           in: customFrom...Date(),
                           displayedComponents: .date)
            }
            .navigationTitle("Custom range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingCustomSheet = false
                        // Revert to the last non-custom preset — otherwise
                        // the picker is stuck on "Custom" with no applied range.
                        if rangePreset == .custom { rangePreset = .thirtyDay }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        showingCustomSheet = false
                        Task { await load() }
                    }
                    .disabled(customFrom > customTo)
                }
            }
        }
    }

    // MARK: - KPI strip

    @ViewBuilder
    private func kpiStrip(_ t: DashboardToday) -> some View {
        let tiles: [(String, Int, String, Color)] = [
            ("Employees", t.totalEmployees, "person.3",         .blue),
            ("Present",   t.present,        "checkmark.circle", .green),
            ("Late",      t.late,           "clock",            .orange),
            ("Flagged",   t.flagged,        "flag.fill",        .yellow),
            ("Absent",    t.absent,         "person.slash",     .gray),
        ]
        if hSizeClass == .regular {
            HStack(spacing: 12) {
                ForEach(tiles, id: \.0) { tile in
                    KPITile(title: tile.0, value: tile.1, systemImage: tile.2, tint: tile.3)
                }
            }
        } else {
            LazyVGrid(
                columns: [GridItem](repeating: .init(.flexible(), spacing: 12), count: 3),
                spacing: 12
            ) {
                ForEach(tiles, id: \.0) { tile in
                    KPITile(title: tile.0, value: tile.1, systemImage: tile.2, tint: tile.3)
                }
            }
        }
    }

    // MARK: - Department filter

    @ViewBuilder
    private var departmentFilter: some View {
        if departments.isEmpty {
            EmptyView()
        } else {
            Menu {
                Button {
                    selectedDeptId = nil
                } label: {
                    Label(
                        "All departments",
                        systemImage: selectedDeptId == nil ? "checkmark" : ""
                    )
                }
                Divider()
                ForEach(departments) { dept in
                    Button {
                        selectedDeptId = dept.id
                    } label: {
                        Label(
                            dept.name,
                            systemImage: selectedDeptId == dept.id ? "checkmark" : ""
                        )
                    }
                }
            } label: {
                Label("Department", systemImage: "line.3.horizontal.decrease.circle")
            }
        }
    }

    // MARK: - Primary chart

    private var primaryChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(chartTitle).font(.headline)
                Spacer()
            }
            Chart {
                ForEach(series) { row in
                    if let d = row.parsedDate {
                        BarMark(
                            x: .value("Day", d, unit: .day),
                            y: .value("On time", row.onTime)
                        )
                        .foregroundStyle(by: .value("Status", "On time"))

                        BarMark(
                            x: .value("Day", d, unit: .day),
                            y: .value("Late", row.late)
                        )
                        .foregroundStyle(by: .value("Status", "Late"))

                        BarMark(
                            x: .value("Day", d, unit: .day),
                            y: .value("Flagged", row.flagged)
                        )
                        .foregroundStyle(by: .value("Status", "Flagged"))

                        BarMark(
                            x: .value("Day", d, unit: .day),
                            y: .value("Absent", row.absent)
                        )
                        .foregroundStyle(by: .value("Status", "Absent"))
                    }
                }
            }
            .chartForegroundStyleScale([
                "On time": Color.green,
                "Late":    Color.orange,
                "Flagged": Color.yellow,
                "Absent":  Color.gray.opacity(0.5),
            ])
            .chartLegend(position: .bottom)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: max(1, seriesRangeDays / 6))) { _ in
                    AxisTick()
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            // Tap a bar → push AdminReportsView seeded to that day.
            // We convert the tap's x-position to a `Date` via the proxy and
            // snap to the nearest day in the series.
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture()
                                .onEnded { value in
                                    guard let plotFrame = proxy.plotFrame else { return }
                                    let xInPlot = value.location.x - geo[plotFrame].origin.x
                                    guard xInPlot >= 0,
                                          xInPlot <= geo[plotFrame].size.width else { return }
                                    if let tapped: Date = proxy.value(atX: xInPlot) {
                                        drillDate = snapToDay(tapped)
                                    }
                                }
                        )
                }
            }
            .frame(height: 240)
            .accessibilityLabel("\(chartTitle) attendance breakdown by status. Double tap a bar to drill into that day.")
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var chartTitle: String {
        switch rangePreset {
        case .today:     "Today"
        case .sevenDay:  "Last 7 days"
        case .thirtyDay: "Last 30 days"
        case .custom:    "Custom range"
        }
    }

    /// Snap an arbitrary chart-space Date to the closest day in `series`
    /// so the drill-down lands on a real bucket rather than between bars.
    private func snapToDay(_ date: Date) -> Date {
        let cal = Calendar.current
        let tappedDay = cal.startOfDay(for: date)
        let candidate = series.compactMap(\.parsedDate).min {
            abs($0.timeIntervalSince(tappedDay)) < abs($1.timeIntervalSince(tappedDay))
        }
        return candidate ?? tappedDay
    }

    // MARK: - Branch breakdown

    private var branchBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("By branch").font(.headline)
                Spacer()
            }

            if hSizeClass == .regular {
                branchTable
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(byBranch) { kpi in
                        NavigationLink {
                            AdminBranchDetailView(kpi: kpi)
                        } label: {
                            branchRowCompact(kpi)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Branch row (compact — iPhone)

    private func branchRowCompact(_ kpi: BranchKPI) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kpi.branchName).font(.subheadline).fontWeight(.semibold)
                Text("P \(kpi.present) · L \(kpi.late) · A \(kpi.absent)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            sparkline(for: kpi)
                .frame(width: 44, height: 24)
                .accessibilityLabel(sparkAccessibility(for: kpi))
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 10)
    }

    // MARK: - Branch table (regular — iPad)

    private var branchTable: some View {
        // iOS 17+ Table with sortable columns. Columns are simple readable
        // fields; the sparkline column renders the mini chart inline.
        Table(byBranch) {
            TableColumn("Name") { row in
                NavigationLink {
                    AdminBranchDetailView(kpi: row)
                } label: {
                    Text(row.branchName)
                }
                .buttonStyle(.plain)
            }
            TableColumn("Present rate") { row in
                Text(presentRate(row))
                    .monospacedDigit()
            }
            TableColumn("Flagged") { row in
                Text("\(row.flagged)").monospacedDigit()
            }
            TableColumn("Last 14d") { row in
                sparkline(for: row).frame(width: 88, height: 22)
            }
        }
        .frame(minHeight: 220)
    }

    // MARK: - Sparkline

    /// 44pt-wide inline chart of daily on-time rate. At that width we drop
    /// every axis and gridline and let `LineMark` fill the frame — the trend
    /// shape is what matters, not exact values.
    @ViewBuilder
    private func sparkline(for kpi: BranchKPI) -> some View {
        let data = sparkByBranch[kpi.branchId] ?? []
        if data.isEmpty {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.15))
        } else {
            Chart {
                ForEach(data) { row in
                    if let d = row.parsedDate {
                        LineMark(
                            x: .value("Day", d),
                            y: .value("Rate", onTimeRate(row))
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0.0...1.0)
            .chartPlotStyle { plot in
                plot.padding(0)
            }
        }
    }

    private func onTimeRate(_ row: DailySeriesRow) -> Double {
        let total = row.total
        guard total > 0 else { return 0 }
        return Double(row.onTime) / Double(total)
    }

    private func presentRate(_ kpi: BranchKPI) -> String {
        guard kpi.total > 0 else { return "—" }
        return String(format: "%.0f%%", Double(kpi.present) / Double(kpi.total) * 100)
    }

    private func sparkAccessibility(for kpi: BranchKPI) -> String {
        let data = sparkByBranch[kpi.branchId] ?? []
        guard let last = data.last else { return "No sparkline data" }
        let rate = Int((onTimeRate(last) * 100).rounded())
        return "\(kpi.branchName), last 14 days on-time rate ending at \(rate) percent"
    }

    // MARK: - Skeletons (initial load)

    private var kpiSkeleton: some View {
        LazyVGrid(columns: [GridItem](repeating: .init(.flexible(), spacing: 12), count: 3), spacing: 12) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 72)
            }
        }
    }

    private var chartSkeleton: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.secondary.opacity(0.12))
            .frame(height: 240)
    }

    private var branchSkeleton: some View {
        VStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 44)
            }
        }
    }

    // MARK: - Range resolution

    /// Translates the current `RangePreset` (+ custom dates) into a concrete
    /// `(from, to)` pair the RPC consumes. Centralised so chart axis labels
    /// and the RPC call can't disagree on what "7d" means.
    private func resolveRange() -> (Date, Date) {
        let now = Date()
        switch rangePreset {
        case .today:
            return (now, now)
        case .sevenDay:
            return (now.addingTimeInterval(-6 * 86_400), now)
        case .thirtyDay:
            return (now.addingTimeInterval(-29 * 86_400), now)
        case .custom:
            return (customFrom, customTo)
        }
    }

    private var seriesRangeDays: Int {
        let (from, to) = resolveRange()
        let secs = to.timeIntervalSince(from)
        return max(1, Int((secs / 86_400).rounded()) + 1)
    }

    // MARK: - Networking

    private func loadIfStale() async {
        // Cheap guard so flipping between tabs doesn't thrash the RPC.
        if let last = lastLoadAt, Date().timeIntervalSince(last) < 60 { return }
        await load()
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // `dashboard_today` returns a single-row set. Decoding as an
            // array + `.first` keeps us compatible whether the RPC is
            // declared `returns setof` or `returns table` server-side.
            async let todayRowsReq: [DashboardToday] = SupabaseManager.shared.client
                .rpc("dashboard_today")
                .execute()
                .value

            async let branchesReq: [BranchKPI] = SupabaseManager.shared.client
                .rpc("dashboard_today_by_branch")
                .execute()
                .value

            async let deptReq: [Department] = SupabaseManager.shared.client
                .from("departments")
                .select("id, name")
                .order("name")
                .execute()
                .value

            let (fromDate, toDate) = resolveRange()
            async let seriesReq: [DailySeriesRow] = SupabaseManager.shared.client
                .rpc("daily_series", params: DailySeriesParams(
                    p_from: ISO8601Date.format(fromDate),
                    p_to: ISO8601Date.format(toDate),
                    p_branch_id: nil,
                    p_dept_id: selectedDeptId
                ))
                .execute()
                .value

            let (todayRows, kpis, depts, ser) = try await (todayRowsReq, branchesReq, deptReq, seriesReq)
            today = todayRows.first
            byBranch = kpis
            departments = depts
            series = ser
            errorMessage = nil
            lastLoadAt = Date()

            await loadSparklines(for: kpis)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// N+1 fan-out: one `daily_series` call per branch for the sparkline's
    /// last 14 days. The branch set is small (< 50 typical), so this is fine;
    /// if it starts to hurt we can add a batched server-side RPC variant.
    private func loadSparklines(for kpis: [BranchKPI]) async {
        let to = ISO8601Date.format(Date())
        let from = ISO8601Date.format(Date().addingTimeInterval(-13 * 86_400))

        await withTaskGroup(of: (UUID, [DailySeriesRow]).self) { group in
            for kpi in kpis {
                group.addTask {
                    do {
                        let rows: [DailySeriesRow] = try await SupabaseManager.shared.client
                            .rpc("daily_series", params: DailySeriesParams(
                                p_from: from,
                                p_to: to,
                                p_branch_id: kpi.branchId,
                                p_dept_id: nil
                            ))
                            .execute()
                            .value
                        return (kpi.branchId, rows)
                    } catch {
                        return (kpi.branchId, [])
                    }
                }
            }
            var collected: [UUID: [DailySeriesRow]] = [:]
            for await (id, rows) in group {
                collected[id] = rows
            }
            sparkByBranch = collected
        }
    }
}

// MARK: - Admin branch detail

/// Thin read-only screen pushed from the admin Dashboard's branch breakdown.
/// Re-uses `BranchKPI` for the header and renders a 14-day series chart so
/// the admin has something to drill into without rebuilding a full branch UI.
struct AdminBranchDetailView: View {
    let kpi: BranchKPI

    @State private var series: [DailySeriesRow] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(
                    columns: [GridItem](repeating: .init(.flexible(), spacing: 12), count: 3),
                    spacing: 12
                ) {
                    KPITile(title: "Total",   value: kpi.total,   systemImage: "person.3",          tint: .blue)
                    KPITile(title: "Present", value: kpi.present, systemImage: "checkmark.circle",  tint: .green)
                    KPITile(title: "Late",    value: kpi.late,    systemImage: "clock",             tint: .orange)
                    KPITile(title: "Flagged", value: kpi.flagged, systemImage: "flag.fill",         tint: .yellow)
                    KPITile(title: "Absent",  value: kpi.absent,  systemImage: "person.slash",      tint: .gray)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Last 14 days").font(.headline)
                    if isLoading && series.isEmpty {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.12))
                            .frame(height: 220)
                    } else if let errorMessage, series.isEmpty {
                        ContentUnavailableView(
                            "Couldn't load",
                            systemImage: "exclamationmark.triangle",
                            description: Text(errorMessage)
                        )
                    } else {
                        branchChart
                    }
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(16)
        }
        .navigationTitle(kpi.branchName)
        .task { await load() }
    }

    private var branchChart: some View {
        Chart {
            ForEach(series) { row in
                if let d = row.parsedDate {
                    BarMark(x: .value("Day", d, unit: .day), y: .value("On time", row.onTime))
                        .foregroundStyle(by: .value("Status", "On time"))
                    BarMark(x: .value("Day", d, unit: .day), y: .value("Late", row.late))
                        .foregroundStyle(by: .value("Status", "Late"))
                    BarMark(x: .value("Day", d, unit: .day), y: .value("Flagged", row.flagged))
                        .foregroundStyle(by: .value("Status", "Flagged"))
                    BarMark(x: .value("Day", d, unit: .day), y: .value("Absent", row.absent))
                        .foregroundStyle(by: .value("Status", "Absent"))
                }
            }
        }
        .chartForegroundStyleScale([
            "On time": Color.green,
            "Late":    Color.orange,
            "Flagged": Color.yellow,
            "Absent":  Color.gray.opacity(0.5),
        ])
        .chartLegend(position: .bottom)
        .frame(height: 220)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let from = ISO8601Date.format(Date().addingTimeInterval(-13 * 86_400))
            let to = ISO8601Date.format(Date())
            series = try await SupabaseManager.shared.client
                .rpc("daily_series", params: DailySeriesParams(
                    p_from: from,
                    p_to: to,
                    p_branch_id: kpi.branchId,
                    p_dept_id: nil
                ))
                .execute()
                .value
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Date helpers

/// Formats `Date` as `YYYY-MM-DD` using the shared UTC formatter. Lives here
/// so every Phase 6 screen has a single canonical path for the date columns
/// the RPCs expect. Marked nonisolated-safe because `DateFormatter` is thread
/// safe for reads.
enum ISO8601Date {
    static func format(_ date: Date) -> String {
        DailySeriesRow.dateFormatter.string(from: date)
    }
}
