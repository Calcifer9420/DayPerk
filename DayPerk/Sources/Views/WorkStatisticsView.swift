import SwiftUI
import UniformTypeIdentifiers

/// 时间价值取实际工时记录，预计收入由工资规则独立提供；两者不混记。
enum WorkReportPeriod: String, CaseIterable, Identifiable {
    case day, week, month
    var id: Self {
        self
    }
}

struct WorkReportDay: Identifiable {
    var date: Date
    var total: WorkDayTotal
    var expectedIncome: Double = 0
    var expectedWorkSeconds: Double = 0
    var isFuture = false
    var paidLeaveSeconds: Double = 0
    var unpaidLeaveSeconds: Double = 0
    var paidLeaveDays: Double = 0
    var unpaidLeaveDays: Double = 0
    var id: String {
        total.id
    }

    var balance: Double {
        isFuture ? 0 : expectedIncome - total.earned
    }
}

struct WorkReport {
    var interval: DateInterval
    var days: [WorkReportDay]
    // 未来日期只展示计划，不提前计入截至今天的工时与收入汇总。
    private var accountedDays: [WorkReportDay] { days.filter { !$0.isFuture } }
    // 按单日整数秒汇总，确保明细、合计和导出一致。
    var workSeconds: Int { accountedDays.reduce(0) { $0 + WorkDurationInput.wholeSeconds($1.total.seconds) } }
    var expectedWorkSeconds: Int { accountedDays.reduce(0) { $0 + WorkDurationInput.wholeSeconds($1.expectedWorkSeconds) } }
    var timeDifferenceSeconds: Int { workSeconds - expectedWorkSeconds }
    var seconds: Double {
        accountedDays.reduce(0) { $0 + $1.total.seconds }
    }

    var overtimeSeconds: Double {
        accountedDays.reduce(0) { $0 + $1.total.overtimeSeconds }
    }

    var unpaidOvertimeSeconds: Double {
        accountedDays.reduce(0) { $0 + $1.total.unpaidOvertimeSeconds }
    }

    var paidLeaveDays: Double { days.reduce(0) { $0 + $1.paidLeaveDays } }
    var unpaidLeaveDays: Double { days.reduce(0) { $0 + $1.unpaidLeaveDays } }
    var paidLeaveSeconds: Double { days.reduce(0) { $0 + $1.paidLeaveSeconds } }
    var unpaidLeaveSeconds: Double { days.reduce(0) { $0 + $1.unpaidLeaveSeconds } }

    var earned: Double {
        accountedDays.reduce(0) { $0 + $1.total.earned }
    }

    var expectedIncome: Double {
        accountedDays.reduce(0) { $0 + $1.expectedIncome }
    }

    var balance: Double {
        days.reduce(0) { $0 + $1.balance }
    }

    var workedDays: Int {
        accountedDays.filter { $0.total.seconds > 0 }.count
    }

    func rows(byWeek: Bool, calendar: Calendar = .current) -> [WorkReport] {
        var groups: [[WorkReportDay]] = []
        for day in days {
            if groups.isEmpty || !byWeek || calendar.component(.weekday, from: day.date) == 2 {
                groups.append([day])
            } else {
                groups[groups.count - 1].append(day)
            }
        }
        return groups.compactMap { group in
            guard let first = group.first, let last = group.last,
                  let end = calendar.date(byAdding: .day, value: 1, to: last.date) else { return nil }
            return WorkReport(interval: DateInterval(start: first.date, end: end), days: group)
        }
    }

    static func make(days records: [WorkDayTotal], containing date: Date, period: WorkReportPeriod,
                     calendar sourceCalendar: Calendar = .current, asOf: Date = Date(),
                     expectedIncome: (WorkDayTotal) -> Double = { _ in 0 },
                     expectedWorkSeconds: (WorkDayTotal) -> Double = { $0.referenceSeconds ?? 0 },
                     leave: (String) -> LeaveSummary = { _ in LeaveSummary() }) -> WorkReport
    {
        var calendar = sourceCalendar
        calendar.firstWeekday = 2
        let dayStart = calendar.startOfDay(for: date)
        let start: Date
        let end: Date
        switch period {
        case .day:
            start = dayStart
            end = calendar.date(byAdding: .day, value: 1, to: start)!
        case .week:
            let daysSinceMonday = (calendar.component(.weekday, from: dayStart) + 5) % 7
            start = calendar.date(byAdding: .day, value: -daysSinceMonday, to: dayStart)!
            end = calendar.date(byAdding: .day, value: 7, to: start)!
        case .month:
            let interval = calendar.dateInterval(of: .month, for: date)!
            start = interval.start
            end = interval.end
        }
        let indexed = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        var rows: [WorkReportDay] = []
        var cursor = start
        while cursor < end {
            let key = WorkPlan.dayKey(cursor, calendar: calendar)
            let total = indexed[key] ?? WorkDayTotal(id: key)
            let timeOff = leave(key)
            rows.append(WorkReportDay(date: cursor, total: total, expectedIncome: expectedIncome(total),
                                      expectedWorkSeconds: expectedWorkSeconds(total),
                                      isFuture: cursor > calendar.startOfDay(for: asOf), paidLeaveSeconds: timeOff.paidSeconds, unpaidLeaveSeconds: timeOff.unpaidSeconds, paidLeaveDays: timeOff.paidDays, unpaidLeaveDays: timeOff.unpaidDays))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return WorkReport(interval: DateInterval(start: start, end: end), days: rows)
    }
}

enum WorkBalancePresentation {
    static func timeColor(for seconds: Int) -> Color {
        seconds > 0 ? .red : seconds < 0 ? .green : .secondary
    }

    static func color(for balance: Double, visible: Bool, decimalPlaces: Int = 2) -> Color {
        guard visible else { return .secondary }
        let value = MoneyDisplaySettings.normalizedForDisplay(balance, decimalPlaces: decimalPlaces)
        return value > 0 ? .green : value < 0 ? .red : .secondary
    }
}

enum WorkReportPresentation {
    /// 只替换数字，保留货币符号、正负号、小数与分组分隔符。
    static func maskNumbers(_ formatted: String) -> String {
        String(formatted.map { $0.isNumber ? Character("X") : $0 })
    }

    static func canShareBalance(expectedIncome: Double, timeValue: Double) -> Bool {
        // 时间价值不超过期望收入的一成时，差额过于接近日薪，仍须遮盖。
        expectedIncome <= 0 || timeValue > expectedIncome * 0.1
    }

    static func canShareBalance(_ report: WorkReport) -> Bool {
        // 汇总也须遮住，否则可减去其余日期的差额来还原这一天的工资。
        report.days.allSatisfy { $0.isFuture || canShareBalance(expectedIncome: $0.expectedIncome, timeValue: $0.total.earned) }
    }

    static func money(_ formatted: String, showcase: Bool, unlocked: Bool, privacyEnabled: Bool, isBalance: Bool = false, balanceIsIncome: Bool = false) -> String {
        if showcase {
            return isBalance && unlocked && !balanceIsIncome ? formatted : maskNumbers(formatted)
        }
        return unlocked && !privacyEnabled ? formatted : "•••"
    }

    static func duration(_ seconds: Int, showcase: Bool, expected: Bool = false, signed: Bool = false) -> String {
        let text = WorkDurationInput.formatSeconds(seconds, signed: signed)
        return showcase && !expected ? maskNumbers(text) : text
    }
}

struct WorkStatisticsView: View {
    @ObservedObject private var appearance = AppearanceSettings.shared
    @ObservedObject var model: DayPerkModel
    @State private var exportError = ""
    @Environment(\.locale) private var locale
    @State private var period: WorkReportPeriod = .week
    @State private var selectedDate: Date
    @State private var activityDate: Date?

    init(model: DayPerkModel, period: WorkReportPeriod = .week) {
        self.model = model
        _period = State(initialValue: period)
        _selectedDate = State(initialValue: Self.currentBusinessDate(model: model))
    }

    static func currentBusinessDate(model: DayPerkModel) -> Date {
        let key = model.tracking.plan.businessDayKey(Date(), calendar: model.workCalendar)
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Date() }
        // 这里只把业务日期键转回日历日期，报表聚合不再次减去业务日起点。
        return model.workCalendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) ?? Date()
    }

    private var report: WorkReport {
        WorkReport.make(days: model.reportRecords, containing: selectedDate, period: period, calendar: model.workCalendar,
                        asOf: Self.currentBusinessDate(model: model),
                        expectedIncome: { model.expectedIncome(for: $0) }, expectedWorkSeconds: { model.expectedWorkSeconds(for: $0) },
                        leave: { model.leaveSummary(for: $0) })
    }

    private var showcaseMode: Bool { model.privacy.isStatisticsShowcaseEnabled }
    private var amountsVisible: Bool { !showcaseMode && !model.privacy.isPrivacyModeEnabled && model.access.settingsUnlocked }
    private var balancesVisible: Bool { model.access.settingsUnlocked && (showcaseMode || !model.privacy.isPrivacyModeEnabled) }

    private var activityDay: Date? { period == .day ? selectedDate : activityDate }
    private var activityInterval: DateInterval {
        WorkStatusReport.interval(containing: activityDay ?? selectedDate, period: activityDay == nil ? period : .day,
            calendar: model.workCalendar, dayStartMinute: model.dayStartMinute)
    }

    private func money(_ value: Double) -> String {
        WorkReportPresentation.money(model.currency.formatAmount(value), showcase: showcaseMode,
            unlocked: model.access.settingsUnlocked, privacyEnabled: model.privacy.isPrivacyModeEnabled)
    }

    private func duration(_ seconds: Int, expected: Bool = false, signed: Bool = false) -> String {
        WorkReportPresentation.duration(seconds, showcase: showcaseMode, expected: expected, signed: signed)
    }

    var body: some View {
        let report = report
        let rows = report.rows(byWeek: period == .month, calendar: model.workCalendar)
        return GeometryReader { geometry in
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 8) {
                    Text(model.activeCurrencyCode).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Picker(L10n.text("ui.report_period.f4f09df9"), selection: $period) {
                            Text(L10n.text("ui.daily.21087896")).tag(WorkReportPeriod.day)
                            Text(L10n.text("ui.weekly.949ded34")).tag(WorkReportPeriod.week)
                            Text(L10n.text("ui.monthly.797f6f9c")).tag(WorkReportPeriod.month)
                        }.labelsHidden().pickerStyle(.segmented).controlSize(.small).fixedSize()
                        InfoHelp(text: L10n.text("report.balance_help")).frame(width: 18, height: 18)
                    }.fixedSize()
                    Spacer()
                    BrewDatePicker(title: L10n.text("ui.date_to_view.9aa34e3a"), selection: $selectedDate, calendar: model.workCalendar, showsLabel: false).controlSize(.small).fixedSize()
                    Button { selectedDate = Self.currentBusinessDate(model: model) } label: {
                        Label(L10n.text("ui.today.d5f5a7a0"), systemImage: "calendar").labelStyle(.iconOnly)
                    }.help(L10n.text("ui.today.d5f5a7a0"))
                    Button { model.refreshHistoricalData(); ActionToastCenter.shared.show(model.actionError ?? L10n.text("action.refreshed"), isError: model.actionError != nil) } label: {
                        Label(L10n.text("ui.recalculate_history.3cc565bf"), systemImage: "arrow.clockwise").labelStyle(.iconOnly)
                    }.disabled(!model.access.settingsUnlocked)
                        .help(L10n.text("ui.recalculate_completed_dates_with_cu.3c6ee144"))
                    Button { exportExcel(report) } label: {
                        Label(L10n.text("export.excel"), systemImage: "tablecells").labelStyle(.iconOnly)
                    }.help(L10n.text("export.excel")).disabled(!amountsVisible)
                    if model.workStatus.data.enabled {
                        Button { exportChart() } label: {
                            Label(L10n.text("export.chart"), systemImage: "chart.pie").labelStyle(.iconOnly)
                        }.help(L10n.text("export.chart")).disabled(!amountsVisible)
                    }
                }
                .anchorPreference(key: PanelAreaAnchors.self, value: .bounds) { ["statistics-toolbar": $0] }
                Text(dateRange + " · " + L10n.text("ui.days_worked.f3fc9fe6") + " \(report.workedDays)").font(.headline).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        metric(L10n.text("ui.expected_income.7b122310"), value: money(report.expectedIncome))
                        metric(L10n.text("ui.time_value.a472b6c3"), value: money(report.earned))
                        metric(L10n.text("ui.balance_income_value.7c914572"), value: signedMoney(report),
                               valueColor: WorkBalancePresentation.color(for: report.balance, visible: balancesVisible, decimalPlaces: model.currency.displayDecimalPlaces))
                    }
                    HStack(spacing: 12) {
                        metric(L10n.text("report.expected_work_time"), value: duration(report.expectedWorkSeconds, expected: true))
                        metric(L10n.text("ui.work_time.1a0937e5"), value: duration(report.workSeconds))
                        metric(L10n.text("report.time_difference"), value: duration(report.timeDifferenceSeconds, signed: true),
                               valueColor: WorkBalancePresentation.timeColor(for: report.timeDifferenceSeconds))
                    }
                }
                if report.paidLeaveDays + report.unpaidLeaveDays > 0 {
                HStack(spacing: 12) {
                    metric(L10n.text("leave.paid_time"), value: leaveAmount(days: report.paidLeaveDays))
                    metric(L10n.text("leave.unpaid_time"), value: leaveAmount(days: report.unpaidLeaveDays))
                    InfoHelp(text: L10n.text("leave.report_help")).frame(width: 18, height: 18)
                }
                }
                VStack(spacing: 0) {
                    columns([period == .month ? L10n.text("ui.week.5c553ec3") : L10n.text("ui.date.70d0c1b3"), L10n.text("report.expected_work_time"), L10n.text("ui.work_time.1a0937e5"), L10n.text("report.time_difference"),
                             L10n.text("ui.expected_income.7b122310"), L10n.text("ui.time_value.a472b6c3"), L10n.text("report.money_difference")], header: true)
                    Divider()
                    ForEach(rows, id: \.interval.start) { row in
                        let selected = activityDate.map { model.workCalendar.isDate($0, inSameDayAs: row.interval.start) } == true
                        let content = columns([period == .month ? weekLabel(row.interval) : dayLabel(row.interval.start),
                                 duration(row.expectedWorkSeconds, expected: true), duration(row.workSeconds), duration(row.timeDifferenceSeconds, signed: true),
                                 money(row.expectedIncome), money(row.earned), signedMoney(row)], balance: row.balance, timeDifference: row.timeDifferenceSeconds, leave: leaveLabel(row))
                            .background(selected && period == .week ? appearance.theme.color.opacity(0.14) : .clear)
                        if period == .week, model.workStatus.data.enabled {
                            Button { activityDate = selected ? nil : row.interval.start } label: { content }
                                .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
                        } else { content }
                        if row.interval.start != rows.last?.interval.start {
                            Divider().padding(.horizontal, 14)
                        }
                    }
                }.background(appearance.theme.surface.opacity(appearance.background.enabled ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 12))
                    .anchorPreference(key: PanelAreaAnchors.self, value: .bounds) { ["statistics-table": $0] }
                if model.workStatus.data.enabled {
                    WorkStatusStatisticsView(controller: model.workStatus, interval: activityInterval, plan: model.businessPlan,
                        days: model.reportRecords, calendar: model.workCalendar, day: activityDay,
                        daySelection: period == .day ? nil : $activityDate,
                        selectionBounds: report.interval.start ... report.interval.end.addingTimeInterval(-1))
                }
            }.frame(width: max(0, geometry.size.width - 48)).padding(24)
        }
        }.actionFeedback($exportError, isError: true)
            .onChange(of: period) { _, _ in activityDate = nil }
            .onChange(of: selectedDate) { _, _ in activityDate = nil }
    }

    private func leaveAmount(days: Double) -> String {
        let value = days.formatted(.number.locale(locale).precision(.fractionLength(0 ... 1)))
        return L10n.format("leave.day_count", showcaseMode ? WorkReportPresentation.maskNumbers(value) : value)
    }

    private func leaveLabel(_ row: WorkReport) -> String? {
        let labels = [("leave.paid_label", row.paidLeaveDays), ("leave.unpaid_label", row.unpaidLeaveDays)]
            .filter { $0.1 > 0 }.map { L10n.format($0.0, leaveAmount(days: $0.1)) }
        return labels.isEmpty ? nil : labels.joined(separator: " · ")
    }

    private func exportChart() {
        guard amountsVisible else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "DayPerk-" + (activityDay.map { WorkPlan.dayKey($0, calendar: model.workCalendar) } ?? period.rawValue) + ".png"
        guard let window = NSApp.keyWindow else { return }
        let interval = activityInterval
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url, amountsVisible, !model.access.isDataLocked else { return }
            do { try ReportChartExport.data(controller: model.workStatus, interval: interval, plan: model.businessPlan, days: model.reportRecords, locale: locale, calendar: model.workCalendar, day: activityDay).write(to: url, options: .atomic); ActionToastCenter.shared.show(L10n.text("action.exported")) }
            catch { exportError = error.localizedDescription }
        }
    }

    private func exportExcel(_ report: WorkReport) {
        guard amountsVisible else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: "xlsx") ?? .data]
        panel.nameFieldStringValue = "DayPerk-" + period.rawValue + "-" + WorkPlan.dayKey(report.interval.start, calendar: model.workCalendar) + "_" + WorkPlan.dayKey(report.interval.end.addingTimeInterval(-1), calendar: model.workCalendar) + ".xlsx"
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.identifier?.rawValue == "DayPerk-preferences" && $0.isVisible }) else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url, amountsVisible, !model.access.isDataLocked else { return }
            do { try ReportExcelExport.data(report: report, currency: model.activeCurrencyCode, calendar: model.workCalendar, locale: locale).write(to: url, options: .atomic); ActionToastCenter.shared.show(L10n.text("action.exported")) }
            catch { exportError = error.localizedDescription }
        }
    }

    private func signedMoney(_ report: WorkReport) -> String {
        let value = MoneyDisplaySettings.normalizedForDisplay(report.balance, decimalPlaces: model.currency.displayDecimalPlaces)
        let formatted = (value > 0 ? "+" : "") + model.currency.formatAmount(value)
        return WorkReportPresentation.money(formatted, showcase: showcaseMode, unlocked: model.access.settingsUnlocked,
            privacyEnabled: model.privacy.isPrivacyModeEnabled, isBalance: true,
            balanceIsIncome: !WorkReportPresentation.canShareBalance(report))
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = model.workCalendar.timeZone
        formatter.dateFormat = "EEE MM/dd"
        return formatter.string(from: date)
    }

    private func weekLabel(_ interval: DateInterval) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = model.workCalendar.timeZone
        formatter.dateFormat = "MM/dd"
        let end = model.workCalendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
        return "\(formatter.string(from: interval.start)) – \(formatter.string(from: end))"
    }

    /// 表头和数据共用等宽列，避免日期被额外空白撑开。
    private func columns(_ values: [String], header: Bool = false, balance: Double? = nil, timeDifference: Int = 0, leave: String? = nil) -> some View {
        HStack(spacing: 12) {
            ForEach(values.indices, id: \.self) { index in
                VStack(spacing: 4) {
                    Text(values[index])
                        // 数字和遮罩共用等宽字体，替换后不会触发更小的自动缩放。
                        .font(header || index == 0 ? nil : .system(.body, design: .monospaced))
                    if index == 0, let leave { Text(leave).font(.system(.caption2, design: .monospaced)).foregroundStyle(.cyan).lineLimit(2) }
                }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)
                    .lineLimit(1).minimumScaleFactor(0.65)
                    .foregroundStyle(header ? Color.secondary : index == 3 ? WorkBalancePresentation.timeColor(for: timeDifference) : index == values.count - 1 && balance != nil
                        ? WorkBalancePresentation.color(for: balance ?? 0, visible: balancesVisible, decimalPlaces: model.currency.displayDecimalPlaces) : Color.primary)
            }
        }.font(header ? .subheadline : .body).monospacedDigit()
            .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private var dateRange: String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = model.workCalendar.timeZone
        formatter.dateStyle = .medium
        if period == .day {
            return formatter.string(from: report.interval.start)
        }
        let end = model.workCalendar.date(byAdding: .day, value: -1, to: report.interval.end)!
        return "\(formatter.string(from: report.interval.start)) – \(formatter.string(from: end))"
    }

    private func metric(_ title: String, value: String, valueColor: Color = .primary) -> some View {
        VStack(alignment: .center, spacing: 10) {
            Text(title).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text(value).font(.system(.title3, design: .monospaced).weight(.semibold)).foregroundStyle(valueColor).lineLimit(1).minimumScaleFactor(0.6)
        }.frame(maxWidth: .infinity, alignment: .center).padding(16)
            .background(appearance.theme.surface.opacity(appearance.background.enabled ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 12))
    }
}
