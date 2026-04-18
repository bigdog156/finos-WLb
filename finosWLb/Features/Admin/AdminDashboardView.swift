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

    // Admin-only rich summary + live activity feed
    @State private var summary: AdminDashboardSummary?
    @State private var recentEvents: [AdminRecentEvent] = []

    // Range picker. Today/7d/30d are preset; .custom opens a sheet with two
    // DatePickers. All four map onto a (from, to) pair before the RPC call.
    enum RangePreset: String, CaseIterable, Identifiable, Hashable {
        case today, sevenDay, thirtyDay, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .today:     "Hôm nay"
            case .sevenDay:  "7 ngày"
            case .thirtyDay: "30 ngày"
            case .custom:    "Tùy chỉnh"
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
            .navigationTitle("Tổng quan")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("Tổng quan").font(.headline)
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
                Label("Không thể tải bảng tổng quan", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Thử lại") { Task { await load() } }
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
                "Chưa có nhân viên",
                systemImage: "person.3",
                description: Text("Mời nhân viên từ Quản trị → Người dùng để điền dữ liệu vào bảng.")
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let summary { heroHeader(summary) }
                    if let summary, summary.pendingFlags + summary.pendingLeaves + summary.pendingCorrections > 0 {
                        pendingWorkStrip(summary)
                    }
                    if let today { kpiStrip(today) }
                    rangeBar
                    primaryChart
                    branchBreakdown
                    if !recentEvents.isEmpty { recentActivity }
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

    // MARK: - Hero header

    private func heroHeader(_ summary: AdminDashboardSummary) -> some View {
        HStack(alignment: .top, spacing: 16) {
            onTimeRing(summary: summary)

            VStack(alignment: .leading, spacing: 6) {
                miniStat(label: "Chi nhánh", value: summary.totalBranches, system: "building.2")
                miniStat(label: "Nhân viên hoạt động", value: summary.totalActiveEmployees, system: "person.3")
                miniStat(label: "Lượt vào hôm nay", value: summary.checkInsToday, system: "arrow.down.circle")
                miniStat(label: "Lượt ra hôm nay", value: summary.checkOutsToday, system: "arrow.up.circle")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func onTimeRing(summary: AdminDashboardSummary) -> some View {
        let percent = Int((summary.onTimeRate * 100).rounded())
        let color: Color = percent >= 80 ? .green : percent >= 50 ? .orange : .red
        return ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(0.01, summary.onTimeRate))
                .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: summary.onTimeRate)
            VStack(spacing: 0) {
                Text("\(percent)%")
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(color)
                Text("Đúng giờ")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 110, height: 110)
    }

    private func miniStat(label: String, value: Int, system: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: system)
                .font(.callout)
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value)")
                    .font(.headline.monospacedDigit())
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Pending work strip

    private func pendingWorkStrip(_ summary: AdminDashboardSummary) -> some View {
        let items: [(Int, String, String, Color)] = [
            (summary.pendingFlags, "Sự kiện gắn cờ", "flag.fill", .yellow),
            (summary.pendingLeaves, "Đơn nghỉ phép", "sun.max.fill", .blue),
            (summary.pendingCorrections, "Bổ sung công", "calendar.badge.plus", .orange),
        ]
        return VStack(alignment: .leading, spacing: 8) {
            Text("Việc cần xử lý")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 10) {
                ForEach(items, id: \.1) { count, label, icon, color in
                    pendingPill(count: count, label: label, icon: icon, color: color)
                }
            }
        }
    }

    private func pendingPill(count: Int, label: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.callout)
                    .foregroundStyle(color)
                if count > 0 {
                    Text("\(count)")
                        .font(.title3.bold().monospacedDigit())
                }
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(count > 0 ? .primary : .secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(count > 0 ? color.opacity(0.12) : Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(count > 0 ? color.opacity(0.3) : .clear, lineWidth: 0.5)
        )
    }

    // MARK: - Recent activity feed

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Hoạt động gần đây").font(.headline)
                Spacer()
                Text("\(recentEvents.count) sự kiện")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(recentEvents.enumerated()), id: \.element.id) { idx, event in
                    recentEventRow(event)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    if idx < recentEvents.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func recentEventRow(_ event: AdminRecentEvent) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill((event.eventType == .checkIn ? Color.green : Color.blue).opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: event.eventType == .checkIn
                      ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .foregroundStyle(event.eventType == .checkIn ? Color.green : Color.blue)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(event.employeeName).font(.subheadline.weight(.medium))
                    Text("· \(event.branchName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Text(formatRelative(event.serverTs))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if event.status != .onTime {
                        StatusBadge(status: event.status)
                    }
                }
            }
            Spacer()
        }
    }

    private func formatRelative(_ iso: String) -> String {
        let formatters: [ISO8601DateFormatter] = [.supabase, ISO8601DateFormatter()]
        for f in formatters {
            if let date = f.date(from: iso) {
                return date.formatted(.relative(presentation: .named))
            }
        }
        return iso
    }

    // MARK: - Range bar (segmented presets + custom)

    private var rangeBar: some View {
        HStack(spacing: 8) {
            Picker("Khoảng", selection: $rangePreset) {
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
                DatePicker("Từ",
                           selection: $customFrom,
                           in: ...Date(),
                           displayedComponents: .date)
                DatePicker("Đến",
                           selection: $customTo,
                           in: customFrom...Date(),
                           displayedComponents: .date)
            }
            .navigationTitle("Khoảng tùy chỉnh")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        showingCustomSheet = false
                        // Revert to the last non-custom preset — otherwise
                        // the picker is stuck on "Custom" with no applied range.
                        if rangePreset == .custom { rangePreset = .thirtyDay }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Áp dụng") {
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
            ("Nhân viên", t.totalEmployees, "person.3",         .blue),
            ("Có mặt",    t.present,        "checkmark.circle", .green),
            ("Trễ",       t.late,           "clock",            .orange),
            ("Gắn cờ",    t.flagged,        "flag.fill",        .yellow),
            ("Vắng",      t.absent,         "person.slash",     .gray),
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
                        "Tất cả phòng ban",
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
                Label("Phòng ban", systemImage: "line.3.horizontal.decrease.circle")
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
                            x: .value("Ngày", d, unit: .day),
                            y: .value("Đúng giờ", row.onTime)
                        )
                        .foregroundStyle(by: .value("Trạng thái", "Đúng giờ"))

                        BarMark(
                            x: .value("Ngày", d, unit: .day),
                            y: .value("Trễ", row.late)
                        )
                        .foregroundStyle(by: .value("Trạng thái", "Trễ"))

                        BarMark(
                            x: .value("Ngày", d, unit: .day),
                            y: .value("Gắn cờ", row.flagged)
                        )
                        .foregroundStyle(by: .value("Trạng thái", "Gắn cờ"))

                        BarMark(
                            x: .value("Ngày", d, unit: .day),
                            y: .value("Vắng", row.absent)
                        )
                        .foregroundStyle(by: .value("Trạng thái", "Vắng"))
                    }
                }
            }
            .chartForegroundStyleScale([
                "Đúng giờ": Color.green,
                "Trễ":      Color.orange,
                "Gắn cờ":   Color.yellow,
                "Vắng":     Color.gray.opacity(0.5),
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
            .accessibilityLabel("\(chartTitle) thống kê chấm công theo trạng thái. Nhấn đúp vào một cột để xem chi tiết ngày đó.")
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var chartTitle: String {
        switch rangePreset {
        case .today:     "Hôm nay"
        case .sevenDay:  "7 ngày gần nhất"
        case .thirtyDay: "30 ngày gần nhất"
        case .custom:    "Khoảng tùy chỉnh"
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
                Text("Theo chi nhánh").font(.headline)
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
                Text("CM \(kpi.present) · T \(kpi.late) · V \(kpi.absent)")
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
            TableColumn("Tên") { row in
                NavigationLink {
                    AdminBranchDetailView(kpi: row)
                } label: {
                    Text(row.branchName)
                }
                .buttonStyle(.plain)
            }
            TableColumn("Tỷ lệ có mặt") { row in
                Text(presentRate(row))
                    .monospacedDigit()
            }
            TableColumn("Gắn cờ") { row in
                Text("\(row.flagged)").monospacedDigit()
            }
            TableColumn("14 ngày gần nhất") { row in
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
                            x: .value("Ngày", d),
                            y: .value("Tỷ lệ", onTimeRate(row))
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
        guard let last = data.last else { return "Không có dữ liệu biểu đồ mini" }
        let rate = Int((onTimeRate(last) * 100).rounded())
        return "\(kpi.branchName), tỷ lệ đúng giờ 14 ngày gần nhất kết thúc ở \(rate) phần trăm"
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

            async let summaryReq: [AdminDashboardSummary] = SupabaseManager.shared.client
                .rpc("admin_dashboard_summary")
                .execute()
                .value

            async let recentReq: [AdminRecentEvent] = SupabaseManager.shared.client
                .rpc("admin_recent_events", params: RecentEventsParams(p_limit: 15))
                .execute()
                .value

            let (todayRows, kpis, depts, ser, sum, recent) = try await (
                todayRowsReq, branchesReq, deptReq, seriesReq, summaryReq, recentReq
            )
            today = todayRows.first
            byBranch = kpis
            departments = depts
            series = ser
            summary = sum.first
            recentEvents = recent
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
                    KPITile(title: "Tổng",    value: kpi.total,   systemImage: "person.3",          tint: .blue)
                    KPITile(title: "Có mặt",  value: kpi.present, systemImage: "checkmark.circle",  tint: .green)
                    KPITile(title: "Trễ",     value: kpi.late,    systemImage: "clock",             tint: .orange)
                    KPITile(title: "Gắn cờ",  value: kpi.flagged, systemImage: "flag.fill",         tint: .yellow)
                    KPITile(title: "Vắng",    value: kpi.absent,  systemImage: "person.slash",      tint: .gray)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("14 ngày gần nhất").font(.headline)
                    if isLoading && series.isEmpty {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.12))
                            .frame(height: 220)
                    } else if let errorMessage, series.isEmpty {
                        ContentUnavailableView(
                            "Không thể tải",
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
                    BarMark(x: .value("Ngày", d, unit: .day), y: .value("Đúng giờ", row.onTime))
                        .foregroundStyle(by: .value("Trạng thái", "Đúng giờ"))
                    BarMark(x: .value("Ngày", d, unit: .day), y: .value("Trễ", row.late))
                        .foregroundStyle(by: .value("Trạng thái", "Trễ"))
                    BarMark(x: .value("Ngày", d, unit: .day), y: .value("Gắn cờ", row.flagged))
                        .foregroundStyle(by: .value("Trạng thái", "Gắn cờ"))
                    BarMark(x: .value("Ngày", d, unit: .day), y: .value("Vắng", row.absent))
                        .foregroundStyle(by: .value("Trạng thái", "Vắng"))
                }
            }
        }
        .chartForegroundStyleScale([
            "Đúng giờ": Color.green,
            "Trễ":      Color.orange,
            "Gắn cờ":   Color.yellow,
            "Vắng":     Color.gray.opacity(0.5),
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

/// Params wrapper for `admin_recent_events(p_limit integer)`.
private struct RecentEventsParams: Encodable, Sendable {
    let p_limit: Int
}
