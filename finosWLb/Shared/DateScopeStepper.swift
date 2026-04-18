import SwiftUI

/// Generic date stepper whose granularity depends on the current report scope.
/// Layout: ◀︎ [tap → DatePicker sheet] ▶︎. Step sizes:
///   - `.day`  : ±1 day
///   - `.week` : ±7 days (stepping always lands on the Monday anchor)
///   - `.month`: ±1 month (centred on the month's first day)
///
/// The binding is the anchor date for the scope — callers normalise it
/// further if their chart/grid needs (e.g. manager week grid normalises to
/// Monday in its own `onChange` handler).
struct DateScopeStepper: View {
    @Binding var date: Date
    let scope: ReportScope

    @State private var showPicker = false

    private static let mondayCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2   // Monday
        cal.timeZone = .current
        return cal
    }()

    private static let weekRangeFormatter: DateIntervalFormatter = {
        let f = DateIntervalFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return f
    }()

    var body: some View {
        HStack {
            Button {
                step(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(previousLabel)

            Spacer()

            Button {
                showPicker = true
            } label: {
                Text(centerLabel)
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Chọn một ngày")

            Spacer()

            Button {
                step(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .disabled(isAtPresent)
            .accessibilityLabel(nextLabel)
        }
        .sheet(isPresented: $showPicker) {
            pickerSheet
                .presentationDetents([.medium])
        }
    }

    // MARK: - Centre label

    private var centerLabel: String {
        switch scope {
        case .day:
            return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        case .week:
            let start = Self.startOfWeek(date)
            let end = Self.mondayCalendar.date(byAdding: .day, value: 6, to: start) ?? start
            return Self.weekRangeFormatter.string(from: start, to: end) ?? ""
        case .month:
            return Self.monthFormatter.string(from: date)
        }
    }

    // MARK: - Stepping

    private func step(by units: Int) {
        let cal = Self.mondayCalendar
        let next: Date?
        switch scope {
        case .day:   next = cal.date(byAdding: .day,        value: units, to: date)
        case .week:  next = cal.date(byAdding: .weekOfYear, value: units, to: date)
        case .month: next = cal.date(byAdding: .month,      value: units, to: date)
        }
        if let next {
            date = next
        }
    }

    /// We don't let the user step into the future: it's just confusing for
    /// attendance reports. Cap at "the period containing today".
    private var isAtPresent: Bool {
        let cal = Self.mondayCalendar
        let today = cal.startOfDay(for: Date())
        switch scope {
        case .day:
            return cal.isDate(date, inSameDayAs: today)
        case .week:
            return Self.startOfWeek(date) == Self.startOfWeek(today)
        case .month:
            return cal.component(.year, from: date) == cal.component(.year, from: today)
                && cal.component(.month, from: date) == cal.component(.month, from: today)
        }
    }

    private var previousLabel: String {
        switch scope {
        case .day:   "Ngày trước"
        case .week:  "Tuần trước"
        case .month: "Tháng trước"
        }
    }
    private var nextLabel: String {
        switch scope {
        case .day:   "Ngày sau"
        case .week:  "Tuần sau"
        case .month: "Tháng sau"
        }
    }

    // MARK: - Picker sheet

    @ViewBuilder
    private var pickerSheet: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "Ngày",
                    selection: $date,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
            }
            .navigationTitle("Chọn ngày")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { showPicker = false }
                }
            }
        }
    }

    // MARK: - Helpers

    static func startOfWeek(_ date: Date) -> Date {
        let cal = mondayCalendar
        let weekday = cal.component(.weekday, from: date)
        let offset = (weekday == 1) ? -6 : -(weekday - 2)
        return cal.startOfDay(
            for: cal.date(byAdding: .day, value: offset, to: date) ?? date
        )
    }
}

#Preview {
    @Previewable @State var date = Date()
    @Previewable @State var scope: ReportScope = .week
    return VStack(spacing: 20) {
        ScopePicker(scope: $scope)
        DateScopeStepper(date: $date, scope: scope)
    }
    .padding()
}
