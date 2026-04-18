import SwiftUI

/// Month-grid calendar of the employee's check-in activity. Each day cell
/// shows the day number plus colored dots summarising the status of that
/// day's events (green = on_time, orange = late, yellow = flagged, red =
/// rejected, gray = no events). Tap to select; the caller renders the
/// selected day's events outside the calendar.
///
/// Expected layout: Monday-first week (Vietnamese convention uses Sunday
/// first for the calendar visually, but we match `Calendar.current`'s
/// `firstWeekday` so the header and grid stay in sync).
struct CheckInCalendarView: View {
    /// All events the calendar can render. The calendar reads from this
    /// array — the caller is responsible for fetching a month's worth.
    let events: [AttendanceEvent]

    @Binding var selectedDay: Date
    @Binding var visibleMonth: Date

    @Environment(\.calendar) private var calendar

    private static let monthTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        f.locale = Locale(identifier: "vi_VN")
        return f
    }()

    var body: some View {
        VStack(spacing: 12) {
            header
            weekdayRow
            dayGrid
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Tháng trước")

            Spacer()

            Text(Self.monthTitleFormatter.string(from: visibleMonth).capitalized)
                .font(.headline)
                .monospacedDigit()

            Spacer()

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Tháng sau")
            .disabled(isCurrentMonthOrLater)
            .opacity(isCurrentMonthOrLater ? 0.35 : 1)
        }
    }

    // MARK: - Weekday row (T2 T3 T4 T5 T6 T7 CN)

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// ISO Monday-first, Vietnamese short labels.
    private var weekdaySymbols: [String] {
        ["T2", "T3", "T4", "T5", "T6", "T7", "CN"]
    }

    // MARK: - Day grid

    private var dayGrid: some View {
        let cells = gridCells
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
            spacing: 6
        ) {
            ForEach(cells, id: \.key) { cell in
                if let date = cell.date {
                    dayCell(date)
                        .frame(height: 44)
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDay)
        let isToday = calendar.isDateInToday(date)
        let inFuture = date > Date()
        let eventSummary = summary(for: date)
        let day = calendar.component(.day, from: date)

        return Button {
            selectedDay = date
        } label: {
            VStack(spacing: 4) {
                Text("\(day)")
                    .font(.subheadline.monospacedDigit())
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(inFuture ? Color.secondary.opacity(0.4) : .primary)

                HStack(spacing: 3) {
                    ForEach(eventSummary.dotColors, id: \.self) { color in
                        Circle().fill(color).frame(width: 5, height: 5)
                    }
                    if eventSummary.dotColors.isEmpty {
                        Circle().fill(Color.clear).frame(width: 5, height: 5)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isToday && !isSelected ? Color.accentColor : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(inFuture)
        .accessibilityLabel(accessibilityLabel(for: date, summary: eventSummary))
    }

    // MARK: - Grid generation

    private struct Cell: Hashable {
        let key: String
        let date: Date?
    }

    private var gridCells: [Cell] {
        // Monday-first layout regardless of `calendar.firstWeekday`.
        guard
            let monthRange = calendar.range(of: .day, in: .month, for: visibleMonth),
            let firstOfMonth = calendar.date(
                from: calendar.dateComponents([.year, .month], from: visibleMonth)
            )
        else { return [] }

        // Day-of-week of 1st of month. Calendar.weekday: Sunday=1..Saturday=7.
        // We want Monday=0..Sunday=6 for the leading-blanks count.
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingBlanks = (weekday + 5) % 7  // Mon → 0, Tue → 1, …, Sun → 6

        var cells: [Cell] = []

        for i in 0..<leadingBlanks {
            cells.append(Cell(key: "lead-\(i)", date: nil))
        }

        for dayOffset in 0..<monthRange.count {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: firstOfMonth) {
                let key = ISO8601DateFormatter().string(from: date)
                cells.append(Cell(key: key, date: date))
            }
        }

        // Pad to full weeks so the last row never has a ragged height.
        while cells.count % 7 != 0 {
            cells.append(Cell(key: "trail-\(cells.count)", date: nil))
        }
        return cells
    }

    // MARK: - Day summary

    private struct DaySummary {
        let dotColors: [Color]
        let statuses: [AttendanceEventStatus]
    }

    private func summary(for date: Date) -> DaySummary {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        let inDay = events.compactMap { event -> AttendanceEventStatus? in
            guard let ts = parseISO(event.serverTs) else { return nil }
            guard ts >= dayStart, ts < dayEnd else { return nil }
            return event.status
        }

        guard !inDay.isEmpty else {
            return DaySummary(dotColors: [], statuses: [])
        }

        // Deduplicate while keeping a stable order by severity so the dots
        // render red/orange before green.
        let severity: [AttendanceEventStatus: Int] = [
            .rejected: 0, .flagged: 1, .late: 2, .absent: 3, .onTime: 4
        ]
        let uniqueSorted = Array(Set(inDay)).sorted {
            (severity[$0] ?? 5) < (severity[$1] ?? 5)
        }
        let colors = uniqueSorted.prefix(3).map(Self.statusColor(_:))
        return DaySummary(dotColors: Array(colors), statuses: uniqueSorted)
    }

    private static func statusColor(_ status: AttendanceEventStatus) -> Color {
        switch status {
        case .onTime:   return .green
        case .late:     return .orange
        case .flagged:  return .yellow
        case .absent:   return .gray
        case .rejected: return .red
        }
    }

    // MARK: - Nav

    private var isCurrentMonthOrLater: Bool {
        let now = Date()
        let nowComps = calendar.dateComponents([.year, .month], from: now)
        let visComps = calendar.dateComponents([.year, .month], from: visibleMonth)
        if let ny = nowComps.year, let nm = nowComps.month,
           let vy = visComps.year, let vm = visComps.month {
            if vy > ny { return true }
            if vy == ny && vm >= nm { return true }
        }
        return false
    }

    private func shiftMonth(by months: Int) {
        if let shifted = calendar.date(byAdding: .month, value: months, to: visibleMonth) {
            visibleMonth = shifted
            // When the user scrolls away from the current month, snap the
            // selection to the first of that month so the events section
            // below the calendar has a sensible default.
            if !calendar.isDate(selectedDay, equalTo: shifted, toGranularity: .month) {
                let first = calendar.date(
                    from: calendar.dateComponents([.year, .month], from: shifted)
                ) ?? shifted
                selectedDay = first
            }
        }
    }

    // MARK: - Helpers

    private func parseISO(_ iso: String) -> Date? {
        if let d = ISO8601DateFormatter.supabase.date(from: iso) { return d }
        return ISO8601DateFormatter().date(from: iso)
    }

    private func accessibilityLabel(for date: Date, summary: DaySummary) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.locale = Locale(identifier: "vi_VN")
        var base = formatter.string(from: date)
        if !summary.statuses.isEmpty {
            base += ". " + summary.statuses.map(\.label).joined(separator: ", ")
        } else {
            base += ". Không có hoạt động."
        }
        return base
    }
}
