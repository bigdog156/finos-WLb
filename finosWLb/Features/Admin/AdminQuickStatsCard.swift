import SwiftUI
import OSLog
internal import PostgREST
import Supabase

/// Self-contained "at-a-glance" admin summary rendered at the top of the
/// Admin settings list so the admin sees the critical numbers without
/// drilling into the full dashboard.
///
/// Data comes from the `admin_dashboard_summary` RPC (RLS-scoped). The card
/// refreshes on appear and supports pull-to-refresh through its enclosing
/// list via the shared `onRefresh` closure.
struct AdminQuickStatsCard: View {
    @State private var summary: AdminDashboardSummary?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow

            if let summary {
                heroGrid(summary)
                if summary.pendingFlags + summary.pendingLeaves + summary.pendingCorrections > 0 {
                    Divider().padding(.vertical, 2)
                    pendingRow(summary)
                }
                Divider().padding(.vertical, 2)
                footprintRow(summary)
            } else if isLoading {
                loadingSkeleton
            } else if let errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await load() }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.pie.fill")
                .font(.callout)
                .foregroundStyle(.orange)
            Text("Hôm nay")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            if isLoading, summary != nil {
                ProgressView().scaleEffect(0.7)
            }
            NavigationLink {
                AdminDashboardView()
            } label: {
                Text("Chi tiết")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
    }

    // MARK: - Hero (big number + ring)

    private func heroGrid(_ s: AdminDashboardSummary) -> some View {
        HStack(alignment: .center, spacing: 16) {
            // On-time ring
            ZStack {
                Circle()
                    .stroke(ringColor(s).opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: max(0.01, s.onTimeRate))
                    .stroke(ringColor(s), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int((s.onTimeRate * 100).rounded()))%")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(ringColor(s))
                    Text("Đúng giờ")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 78, height: 78)

            // Today's traffic: check-ins vs check-outs
            VStack(alignment: .leading, spacing: 6) {
                metric(label: "Lượt vào", value: s.checkInsToday,
                       icon: "arrow.down.circle.fill", tint: .green)
                metric(label: "Lượt ra",  value: s.checkOutsToday,
                       icon: "arrow.up.circle.fill", tint: .blue)
                metric(label: "Vắng",     value: s.absentToday,
                       icon: "person.slash.fill", tint: .gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metric(label: String, value: Int, icon: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(tint)
                .frame(width: 18)
            Text("\(value)")
                .font(.subheadline.bold().monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func ringColor(_ s: AdminDashboardSummary) -> Color {
        let p = Int((s.onTimeRate * 100).rounded())
        if p >= 80 { return .green }
        if p >= 50 { return .orange }
        return .red
    }

    // MARK: - Pending row

    private func pendingRow(_ s: AdminDashboardSummary) -> some View {
        HStack(spacing: 8) {
            Label {
                Text("Cần xử lý:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "tray.and.arrow.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if s.pendingFlags > 0 {
                badge(count: s.pendingFlags, icon: "flag.fill", tint: .yellow)
            }
            if s.pendingLeaves > 0 {
                badge(count: s.pendingLeaves, icon: "sun.max.fill", tint: .blue)
            }
            if s.pendingCorrections > 0 {
                badge(count: s.pendingCorrections, icon: "calendar.badge.plus", tint: .orange)
            }
            Spacer()
        }
    }

    private func badge(count: Int, icon: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text("\(count)")
                .font(.caption.weight(.bold).monospacedDigit())
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.15), in: Capsule())
    }

    // MARK: - Footprint (branches + employees)

    private func footprintRow(_ s: AdminDashboardSummary) -> some View {
        HStack(spacing: 14) {
            footprintItem(value: s.totalBranches, label: "Chi nhánh", icon: "building.2")
            Divider().frame(height: 24)
            footprintItem(value: s.totalActiveEmployees, label: "Nhân viên", icon: "person.3")
            Divider().frame(height: 24)
            footprintItem(value: s.presentToday, label: "Có mặt", icon: "checkmark.circle")
            Spacer()
        }
    }

    private func footprintItem(value: Int, label: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value)")
                    .font(.subheadline.bold().monospacedDigit())
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Loading

    private var loadingSkeleton: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 78, height: 78)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 14)
                }
            }
        }
    }

    // MARK: - Networking

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [AdminDashboardSummary] = try await SupabaseManager.shared.client
                .rpc("admin_dashboard_summary")
                .execute()
                .value
            summary = rows.first
            errorMessage = nil
            AppLog.ui.info("admin quick stats loaded")
        } catch {
            errorMessage = error.localizedDescription
            AppLog.ui.error("admin quick stats failed: \(logMessage(for: error), privacy: .public)")
        }
    }
}
