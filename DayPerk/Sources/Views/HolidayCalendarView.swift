import SwiftUI

extension LeaveKind {
    var color: Color { self == .compensatory ? .purple : .cyan }
}

enum CalendarDayKind {
    case work, rest, holiday, makeup, overtime, leave, compensatoryLeave
    var color: Color {
        switch self {
        case .leave: return LeaveKind.general.color
        case .compensatoryLeave: return LeaveKind.compensatory.color
        case .work: return .secondary
        case .rest: return .mint
        case .holiday: return .green
        case .makeup: return .orange
        case .overtime: return .red
        }
    }
    var title: String {
        switch self {
        case .leave: return L10n.text("leave.short")
        case .compensatoryLeave: return LeaveKind.compensatory.title
        case .work: return L10n.text("ui.work.104ab921")
        case .rest: return L10n.text("ui.rest.05863ec2")
        case .holiday: return L10n.text("ui.holiday.992b3299")
        case .makeup: return L10n.text("ui.make_up_workday.07f65c10")
        case .overtime: return L10n.text("ui.overtime.de4d7bb8")
        }
    }
}

struct HolidayCalendarView: View {
    @Binding var overrides: [String: Bool]
    @Binding var selectedDate: Date
    var overtimeDates: [String: Double]
    var region: PayrollRegion
    var subdivision: String
    var rhythm: WorkRhythm
    var weekdays: Set<Int>
    var leaveDays: [String: LeaveDay]
    var workCalendar: Calendar
    var selectionEnd: Binding<Date>?
    var selectionBegan: (() -> Void)?
    var confirmedRange: ClosedRange<Date>?
    var selectionBounds: ClosedRange<Date>?
    var selectionID: UUID?
    var showsRefreshButton: Bool
    @State private var awaitingRangeEnd = false
    @ObservedObject private var china = ChinaHolidayCalendar.shared
    @ObservedObject private var international = RegionalHolidayCalendar.shared
    @ObservedObject private var language = LocalizationManager.shared
    @State private var month: Date

    init(overrides: Binding<[String: Bool]>, selectedDate: Binding<Date>, overtimeDates: [String: Double] = [:],
         region: PayrollRegion = .china, subdivision: String = "", rhythm: WorkRhythm = WorkRhythm(),
         weekdays: Set<Int> = [2, 3, 4, 5, 6], workCalendar: Calendar = .current, leaveDays: [String: LeaveDay] = [:],
         selectionEnd: Binding<Date>? = nil, selectionBegan: (() -> Void)? = nil,
         confirmedRange: ClosedRange<Date>? = nil, selectionBounds: ClosedRange<Date>? = nil, selectionID: UUID? = nil, showsRefreshButton: Bool = true) {
        _overrides = overrides; _selectedDate = selectedDate
        _month = State(initialValue: selectedDate.wrappedValue)
        self.overtimeDates = overtimeDates; self.region = region; self.subdivision = subdivision
        self.selectionEnd = selectionEnd; self.selectionBegan = selectionBegan
        self.confirmedRange = confirmedRange; self.selectionBounds = selectionBounds; self.selectionID = selectionID
        self.showsRefreshButton = showsRefreshButton
        self.leaveDays = leaveDays
        self.rhythm = rhythm; self.weekdays = weekdays; self.workCalendar = workCalendar
    }
    private var calendar: Calendar {
        var value = workCalendar; value.locale = language.currentLocale; value.firstWeekday = 2; return value
    }
    private func key(_ date: Date) -> String { WorkPlan.dayKey(date, calendar: calendar) }
    private var foreignDays: [RegionalHoliday] { international.days(country: region.rawValue, subdivision: subdivision) }
    private func official(_ date: Date) -> (name: String, off: Bool)? {
        if region == .china, let day = china.cache.plans.values.flatMap(\.days).first(where: { $0.date == key(date) }) {
            return (day.name, day.isOffDay)
        }
        return foreignDays.first { $0.date == key(date) }.map { ($0.name, true) }
    }
    private func activeLeave(_ date: Date) -> LeaveDay? {
        let day = key(date)
        let scheduled: Bool
        if overtimeDates[day] != nil { scheduled = true }
        else if let value = overrides[day] { scheduled = value }
        else if rhythm.observesPublicHolidays != false, let value = official(date) { scheduled = !value.off }
        else { scheduled = rhythm.enabled ? rhythm.isWorkday(date, calendar: calendar) : weekdays.contains(calendar.component(.weekday, from: date)) }
        return scheduled ? leaveDays[day] : nil
    }
    private func kind(_ date: Date) -> CalendarDayKind {
        let day = key(date)
        if let leave = activeLeave(date) { return leave.isCompensatory ? .compensatoryLeave : .leave }
        if overtimeDates[day] != nil { return .overtime }
        if let override = overrides[day] {
            return override ? .makeup : official(date)?.off == true ? .holiday : .rest
        }
        if rhythm.observesPublicHolidays != false, let plan = official(date) { return plan.off ? .holiday : .makeup }
        let work = rhythm.enabled ? rhythm.isWorkday(date, calendar: calendar) : weekdays.contains(calendar.component(.weekday, from: date))
        return work ? .work : .rest
    }
    private var cells: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month), let days = calendar.range(of: .day, in: .month, for: month) else { return [] }
        var result = Array<Date?>(repeating: nil, count: (calendar.component(.weekday, from: interval.start) + 5) % 7)
        result += days.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: interval.start) }.map(Optional.some)
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }
    private var help: String {
        if region == .china { return L10n.text("ui.state_council_holiday_and_make_up_w.61cc7940") }
        let url = PayrollCatalog.bundled.holidayProviders.first { $0.country == region.rawValue }?.officialURL ?? ""
        if region == .hongKong || region == .macau { return "• " + L10n.text("holiday.official_source") + "\n" + url }
        return "• " + L10n.text("ui.public_holidays_are_filtered_by_cou.e03a7f4b")
            + "\n• " + L10n.text("ui.nager_date_supplies_public_dates_of.4040c449") + "\n" + url
    }
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(month.formatted(.dateTime.year().month(.wide).locale(language.currentLocale))).font(.headline)
                Spacer()
                Button { move(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel(L10n.text("ui.previous_month.6a276950"))
                Button(L10n.text("ui.today.d5f5a7a0")) {
                    let today = selectionBounds.map { min(max(Date(), $0.lowerBound), $0.upperBound) } ?? Date()
                    month = today; if selectionEnd == nil { selectedDate = today }
                }
                Button { move(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel(L10n.text("ui.next_month.74e53211"))
                InfoHelp(text: help).frame(width: 18, height: 18)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(0 ..< 7) { offset in
                    Text(calendar.shortStandaloneWeekdaySymbols[(offset + 1) % 7]).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date { cell(date) } else { Color.clear.frame(height: 48) }
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    legend([.makeup, .overtime, .rest, .holiday, .compensatoryLeave, .leave])
                    Spacer(minLength: 8)
                    if showsRefreshButton { refreshButton }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        legend([.makeup, .overtime])
                        Spacer(minLength: 8)
                        if showsRefreshButton { refreshButton }
                    }
                    legend([.rest, .holiday, .compensatoryLeave, .leave])
                }
            }.font(.caption)
            if let value = official(selectedDate) {
                Text(L10n.text(value.name)).font(.caption).foregroundStyle(kind(selectedDate).color).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(.vertical, 8).onChange(of: selectedDate) { _, value in month = value }
            .onChange(of: selectionID) { _, _ in awaitingRangeEnd = false }
            .onChange(of: selectionEnd?.wrappedValue) { _, value in if let value { month = value } }
            .onChange(of: selectionEnd != nil) { _, _ in awaitingRangeEnd = false }
    }
    private var refreshButton: some View {
        Button {
            Task {
                if region == .china {
                    overrides = await china.refresh(overrides: overrides, currentOverrides: { overrides })
                    ActionToastCenter.shared.show(china.result, isError: china.hasRefreshFailures)
                } else {
                    await international.refresh(country: region.rawValue, calendar: calendar)
                    ActionToastCenter.shared.show(international.errorMessage.isEmpty ? L10n.text("action.refreshed") : international.errorMessage, isError: !international.errorMessage.isEmpty)
                }
            }
        } label: {
            Label(L10n.text("ui.refresh_holidays.6bead756") + " \(calendar.component(.year, from: Date())) / \(calendar.component(.year, from: Date()) + 1)", systemImage: "arrow.clockwise")
        }.disabled(region == .custom || china.refreshing || international.refreshing)
    }
    private func legend(_ kinds: [CalendarDayKind]) -> some View {
        HStack(spacing: 10) {
            ForEach(kinds, id: \.title) { item in
                Label(item.title, systemImage: "circle.fill").foregroundStyle(item.color)
            }
        }.fixedSize()
    }
    private func select(_ date: Date) {
        if let bounds = selectionBounds, !contains(date, in: bounds) { return }
        guard let selectionEnd else { selectedDate = date; return }
        if awaitingRangeEnd {
            let first = selectedDate
            selectedDate = min(first, date); selectionEnd.wrappedValue = max(first, date)
            awaitingRangeEnd = false
        } else {
            selectedDate = date; selectionEnd.wrappedValue = date
            selectionBegan?(); awaitingRangeEnd = true
        }
    }

    private func move(_ offset: Int) { if let next = calendar.date(byAdding: .month, value: offset, to: month) { month = next } }
    private func contains(_ date: Date, in range: ClosedRange<Date>) -> Bool {
        calendar.startOfDay(for: date) >= calendar.startOfDay(for: range.lowerBound)
            && calendar.startOfDay(for: date) <= calendar.startOfDay(for: range.upperBound)
    }
    private func cell(_ date: Date) -> some View {
        let status = kind(date), selected = calendar.isDate(date, inSameDayAs: selectedDate)
        let end = selectionEnd?.wrappedValue ?? selectedDate
        let last = selectionEnd != nil && calendar.isDate(date, inSameDayAs: end)
        let inRange = selectionEnd != nil && calendar.startOfDay(for: date) >= calendar.startOfDay(for: min(selectedDate, end))
            && calendar.startOfDay(for: date) <= calendar.startOfDay(for: max(selectedDate, end))
        let shift = rhythm.customSchedule(for: key(date))
        let shiftLabel = shift.map { String(format: "%02d:%02d–%02d:%02d", $0.startMinute / 60, $0.startMinute % 60, $0.endMinute / 60, $0.endMinute % 60) }
        let label = activeLeave(date).map { $0.summary } ?? overtimeDates[key(date)].map { "\(L10n.text("ui.ot.c2d4fe38")) \($0.formatted(.number.precision(.fractionLength(0 ... 2))))×" }
            ?? (status == .work ? shiftLabel ?? " " : L10n.text(status.title))
        return Button { select(date) } label: {
            VStack(spacing: 3) {
                ZStack {
                    Text("\(calendar.component(.day, from: date))").font(.callout).monospacedDigit()
                    if rhythm.observesPublicHolidays == false && official(date)?.off == true {
                        Circle().fill(.green).frame(width: 4, height: 4).offset(x: 18)
                    }
                }.frame(width: 26, height: 24)
                    .overlay(Circle().stroke(confirmedRange.map { contains(date, in: $0) } == true ? Color.cyan.opacity(0.8) : .clear, lineWidth: 1.5))
                Text(label).font(.system(size: 10)).foregroundStyle(status.color).lineLimit(1).minimumScaleFactor(0.7).frame(height: 12)
            }.frame(maxWidth: .infinity).frame(height: 48)
                .background((selected || last) ? Color.accentColor.opacity(0.23) : inRange ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                .background {
                    if let range = confirmedRange, contains(date, in: range) {
                        GeometryReader { geometry in
                            Path { path in
                                let center = geometry.size.width / 2
                                if !calendar.isDate(date, inSameDayAs: range.lowerBound) {
                                    path.move(to: CGPoint(x: -3, y: 16.5)); path.addLine(to: CGPoint(x: center - 15, y: 16.5))
                                }
                                if !calendar.isDate(date, inSameDayAs: range.upperBound) {
                                    path.move(to: CGPoint(x: center + 15, y: 16.5)); path.addLine(to: CGPoint(x: geometry.size.width + 3, y: 16.5))
                                }
                            }.stroke(Color.cyan.opacity(0.65), lineWidth: 2)
                        }
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 7).stroke((selected || last) ? Color.accentColor : .clear))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(selectionBounds.map { !contains(date, in: $0) } ?? false)
            .accessibilityLabel(key(date) + " " + L10n.text(status.title) + " " + label)
    }
}
