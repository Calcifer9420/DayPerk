import SwiftUI

/// 日期入口统一跟随主题，日历只负责选日期，不改排班或结算数据。
struct BrewDatePicker: View {
    var title: String
    @Binding var selection: Date
    var calendar: Calendar
    var bounds: ClosedRange<Date>? = nil
    var showsLabel = true
    var monthsOnly = false
    var iconOnly = false
    @ObservedObject private var appearance = AppearanceSettings.shared
    @ObservedObject private var language = LocalizationManager.shared
    @State private var presented = false
    @State private var month: Date = Date()
    private var locale: Locale { language.currentLocale }

    private var localizedCalendar: Calendar {
        var value = calendar; value.locale = locale; value.firstWeekday = 2; return value
    }
    private func label(_ date: Date, template: String) -> String {
        let formatter = DateFormatter(); formatter.calendar = localizedCalendar; formatter.locale = locale
        formatter.timeZone = calendar.timeZone; formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
    var body: some View {
        Group {
            if showsLabel { LabeledContent { trigger } label: { Text(title) } }
            else { trigger }
        }
    }
    private var trigger: some View {
        Button { month = selection; presented.toggle() } label: {
            HStack(spacing: 7) {
                Image(systemName: "calendar").font(.system(size: 12))
                if !iconOnly {
                    Text(label(selection, template: monthsOnly ? "yMMMM" : "yMMMd")).monospacedDigit()
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                }
            }.fixedSize()
        }.buttonStyle(BrewButtonStyle()).accessibilityLabel(title)
            .accessibilityValue(label(selection, template: monthsOnly ? "yMMMM" : "yMMMd"))
            .popover(isPresented: $presented, arrowEdge: .bottom) { calendarPanel }
    }
    var calendarPanel: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Button { move(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel(L10n.text(monthsOnly ? "date.previous_year" : "ui.previous_month.6a276950"))
                    .disabled(!canMove(-1))
                Spacer(minLength: 0)
                Menu {
                    ForEach(1900 ... 2100, id: \.self) { year in
                        Button(String(year)) { setMonth(year: year, number: localizedCalendar.component(.month, from: month)) }
                    }
                } label: { Text(String(localizedCalendar.component(.year, from: month))).fontWeight(.semibold) }
                    .menuStyle(.borderlessButton).fixedSize()
                if !monthsOnly {
                    Menu {
                        ForEach(1 ... 12, id: \.self) { number in
                            Button(localizedCalendar.standaloneMonthSymbols[number - 1]) {
                                setMonth(year: localizedCalendar.component(.year, from: month), number: number)
                            }
                        }
                    } label: { Text(label(month, template: "MMMM")).fontWeight(.semibold) }
                        .menuStyle(.borderlessButton).fixedSize()
                }
                Spacer(minLength: 0)
                Button { move(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel(L10n.text(monthsOnly ? "date.next_year" : "ui.next_month.74e53211"))
                    .disabled(!canMove(1))
            }
            if monthsOnly { monthGrid } else { dayGrid }
            Divider()
            HStack {
                Button(L10n.text(monthsOnly ? "date.this_month" : "ui.today.d5f5a7a0")) { choose(Date()) }
                    .disabled(!isAllowed(Date()))
                Spacer()
                Button(L10n.text("ui.cancel.2cd0f3be"), systemImage: "xmark") { presented = false }
                    .labelStyle(.iconOnly).help(L10n.text("ui.cancel.2cd0f3be")).keyboardShortcut(.cancelAction)
            }
        }.padding(16).frame(width: 312)
            .foregroundStyle(.primary).background(appearance.theme.canvas)
            .preferredColorScheme(.dark).tint(appearance.theme.color).buttonStyle(BrewButtonStyle())
    }
    private var dayGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(0 ..< 7) { index in
                Text(localizedCalendar.veryShortStandaloneWeekdaySymbols[(index + 1) % 7])
                    .font(.caption).foregroundStyle(.secondary).frame(height: 22)
            }
            ForEach(Array(Self.days(in: month, calendar: localizedCalendar).enumerated()), id: \.offset) { _, date in
                if let date {
                    let selected = localizedCalendar.isDate(date, inSameDayAs: selection)
                    Button { choose(date) } label: {
                        Text(String(localizedCalendar.component(.day, from: date))).monospacedDigit()
                            .frame(maxWidth: .infinity).frame(height: 32)
                            .foregroundStyle(selected ? Color.black : .primary)
                            .background(selected ? appearance.theme.color : .clear, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(localizedCalendar.isDateInToday(date) ? appearance.theme.color : .clear))
                    }.buttonStyle(.plain).disabled(!isAllowed(date)).opacity(isAllowed(date) ? 1 : 0.25)
                        .accessibilityLabel(label(date, template: "yMMMMdEEEE"))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                } else { Color.clear.frame(height: 32) }
            }
        }
    }
    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 8) {
            ForEach(1 ... 12, id: \.self) { number in
                let date = localizedCalendar.date(from: DateComponents(year: localizedCalendar.component(.year, from: month), month: number, day: 1)) ?? month
                let selected = localizedCalendar.isDate(date, equalTo: selection, toGranularity: .month)
                Button { choose(date) } label: {
                    Text(localizedCalendar.shortStandaloneMonthSymbols[number - 1]).lineLimit(1)
                        .frame(maxWidth: .infinity).frame(height: 32)
                        .foregroundStyle(selected ? Color.black : appearance.theme.color)
                        .background(appearance.theme.color.opacity(selected ? 1 : 0.1), in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain).disabled(!isAllowed(date))
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
    private func isAllowed(_ date: Date) -> Bool {
        guard let bounds else { return true }
        return Self.contains(date, in: bounds, calendar: localizedCalendar)
    }
    private func choose(_ value: Date) {
        let date = monthsOnly ? (localizedCalendar.dateInterval(of: .month, for: value)?.start ?? value) : value
        guard isAllowed(date) else { return }
        let time = localizedCalendar.dateComponents([.hour, .minute, .second], from: selection)
        selection = localizedCalendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: time.second ?? 0, of: date) ?? date
        presented = false
    }
    private func setMonth(year: Int, number: Int) {
        if let value = localizedCalendar.date(from: DateComponents(year: year, month: number, day: 1)) { month = value }
    }
    private func canMove(_ value: Int) -> Bool {
        guard let bounds, let next = localizedCalendar.date(byAdding: monthsOnly ? .year : .month, value: value, to: month),
              let interval = localizedCalendar.dateInterval(of: monthsOnly ? .year : .month, for: next) else { return true }
        return interval.end > localizedCalendar.startOfDay(for: bounds.lowerBound) && interval.start <= localizedCalendar.startOfDay(for: bounds.upperBound)
    }
    private func move(_ value: Int) {
        guard canMove(value), let start = localizedCalendar.dateInterval(of: .month, for: month)?.start,
              let next = localizedCalendar.date(byAdding: monthsOnly ? .year : .month, value: value, to: start) else { return }
        month = next
    }
    static func days(in month: Date, calendar: Calendar) -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month), let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let offset = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: offset) + range.map { calendar.date(byAdding: .day, value: $0 - 1, to: interval.start) }
    }
    static func contains(_ date: Date, in bounds: ClosedRange<Date>, calendar: Calendar) -> Bool {
        calendar.startOfDay(for: date) >= calendar.startOfDay(for: bounds.lowerBound) && calendar.startOfDay(for: date) <= calendar.startOfDay(for: bounds.upperBound)
    }
}
