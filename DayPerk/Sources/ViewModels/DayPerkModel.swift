import Combine
import Foundation

struct DayPerkConfiguration {
    var baseSalary: Double
    var housingAllowance: Double
    var workdaysPerMonth: Int
    var startTime: Date
    var endTime: Date
    var weekdays: Set<Weekday>
    var overtimeMultiplier: Double
    var dateOverrides: [String: Bool]
    var currency: SupportedCurrency
    var payroll: PayrollDeductionConfiguration
    var followsCurrentMonth: Bool
    var dailyBreakMinutes: Int = 0
    var breakMode: WorkBreakMode = .totalHours
    var breakPeriods: [WorkBreak] = []
    var linkCaffeine = false
    var overtimeDates: [String: Double] = [:]
    var includeHousingFundInRate = false
    var includeHousingFundInEstimate = false
    var dayStartMinute = 240
    var payday = PaydayRule()
    var automation = WorkAutomationRules()
    var rhythm = WorkRhythm()
    var timeZoneID = TimeZone.current.identifier
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        return value
    }

    var workMinutesPerDay: Int {
        referenceSchedule.referenceMinutes
    }

    var effectiveBreakMinutes: Int {
        referenceSchedule.restMinutes
    }

    var referenceSchedule: DayWorkSchedule {
        let c = calendar
        return DayWorkSchedule(startMinute: c.component(.hour, from: startTime) * 60 + c.component(.minute, from: startTime),
            endMinute: c.component(.hour, from: endTime) * 60 + c.component(.minute, from: endTime),
            breakMode: breakMode, breakMinutes: dailyBreakMinutes, breaks: breakPeriods)
    }

    func referenceMinutes(for key: String) -> Int {
        rhythm.schedule(for: key, fallback: referenceSchedule).referenceMinutes
    }
}

struct WorkHoursExplanation {
    var title: String
    var detail: String
    var rows: [HelpFormulaRow] = []
}

struct HelpFormulaRow {
    var amount: String
    var label: String
    var isTotal = false
    var isUserProvidedLabel = false
    func resolvedLabel(translate: (String) -> String) -> String { isUserProvidedLabel ? label : translate(label) }
}

struct DayPerkInputError: LocalizedError {
    var message: String
    var errorDescription: String? {
        message
    }
}

/// 本地服务接口：配置与补录先校验再保存，不开放网络端口。
final class DayPerkModel: ObservableObject {
    let workStatus = WorkStatusController()
    let regional = RegionalPayrollSettings()
    @Published var regionalEstimate: RegionalPayEstimate?
    let payroll = PayrollDeductionSettings.shared
    let tracking: WorkTrackingController
    var restoreBackup: ((AppDataArchive) throws -> Void)?
    let currency = MoneyDisplaySettings.shared
    let privacy = PrivacySettings()
    let access: SalaryAccessController
    let appearance = AppearanceSettings.shared
    @Published private(set) var profile: SalaryProfile
    @Published private(set) var schedule: ReferenceSchedule
    @Published var breakdown = PayrollBreakdown.zero
    @Published private(set) var includeHousingFundInRate: Bool
    @Published private(set) var includeHousingFundInEstimate: Bool
    @Published var actionError: String?
    @Published private(set) var baseSalary: Double
    @Published private(set) var housingAllowance: Double
    @Published private(set) var breakMode: WorkBreakMode
    @Published private(set) var breakPeriods: [WorkBreak]
    @Published private(set) var linkCaffeine: Bool
    @Published private(set) var overtimeDates: [String: Double]
    @Published private(set) var dailyBreakMinutes: Int
    @Published private(set) var overtimeMultiplier: Double
    @Published private(set) var dateOverrides: [String: Bool]
    @Published private(set) var dayStartMinute: Int
    @Published private(set) var payday: PaydayRule
    @Published private(set) var rhythm: WorkRhythm
    @Published private(set) var automation: WorkAutomationRules
    @Published var leaveDays: [String: LeaveDay]
    @Published var panelContentHeights: [PanelLayoutMode: CGFloat] = [:]
    @Published private(set) var clockOutCelebration: ClockOutCelebrationState?
    private var clockOutCelebrationTimer: Timer?
    @Published private(set) var paydayCelebration: PaydayCelebrationState?
    private var paydayCelebrationTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastTaxMonth = ""
    private var referenceSecondsByMonth: [Int: Double] = [:]
    private var workdaysByMonth: [Int: Int] = [:]
    private var overtimeTotalsDuringRefresh: [Int: [Int: Double]]?

    init(authenticate: ((String, @escaping (Bool) -> Void) -> Void)? = nil, restoringBackup: Bool = false) {
        tracking = WorkTrackingController(restoringBackup: restoringBackup)
        access = SalaryAccessController(allowsInitialSetup: !restoringBackup, authenticate: authenticate)
        leaveDays = UserDataStore.shared.data(forKey: LeaveLedger.storageKey).flatMap { try? JSONDecoder().decode([String: LeaveDay].self, from: $0) } ?? [:]
        let repo = RepositoryManager.shared
        let loadedProfile = (try? repo.userProfileRepository.load(key: "current"))
            ?? SalaryProfile(name: "User", monthlySalary: 0, workdaysPerMonth: 22, currency: "CNY")
        profile = loadedProfile
        schedule = (try? repo.workScheduleRepository.load(key: "current"))
            ?? ReferenceSchedule(startTime: Date.createTime(hour: 8, minute: 30), endTime: Date.createTime(hour: 17, minute: 30))
        let savedBase = UserDataStore.shared.object(forKey: "dayperkBaseSalary") as? Double
        let bonusBase = UserDataStore.shared.double(forKey: "payrollAnnualBonusBase")
        let initialBase = savedBase ?? (bonusBase > 0 && bonusBase <= loadedProfile.monthlySalary ? bonusBase : loadedProfile.monthlySalary)
        includeHousingFundInRate = UserDataStore.shared.bool(forKey: "includeHousingFundInRate")
        includeHousingFundInEstimate = UserDataStore.shared.bool(forKey: "includeHousingFundInEstimate")
        baseSalary = initialBase
        housingAllowance = max(0, loadedProfile.monthlySalary - initialBase)
        breakMode = UserDataStore.shared.string(forKey: "dayperkBreakMode").flatMap(WorkBreakMode.init(rawValue:)) ?? .totalHours
        breakPeriods = UserDataStore.shared.data(forKey: "dayperkBreakPeriods").flatMap { try? JSONDecoder().decode([WorkBreak].self, from: $0) } ?? []
        linkCaffeine = UserDataStore.shared.object(forKey: "dayperkLinkCaffeine") as? Bool ?? false
        overtimeDates = UserDataStore.shared.data(forKey: "dayperkOvertimeDates").flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) } ?? [:]
        dailyBreakMinutes = UserDataStore.shared.integer(forKey: "dayperkDailyBreakMinutes")
        dayStartMinute = UserDataStore.shared.object(forKey: "dayperkDayStartMinute") as? Int ?? 240
        payday = UserDataStore.shared.data(forKey: "dayperkPaydayRule").flatMap { try? JSONDecoder().decode(PaydayRule.self, from: $0) } ?? PaydayRule()
        rhythm = UserDataStore.shared.data(forKey: "dayperkWorkRhythm").flatMap { try? JSONDecoder().decode(WorkRhythm.self, from: $0) } ?? WorkRhythm()
        automation = UserDataStore.shared.data(forKey: "dayperkAutomationRules").flatMap { try? JSONDecoder().decode(WorkAutomationRules.self, from: $0) } ?? WorkAutomationRules()
        overtimeMultiplier = UserDataStore.shared.object(forKey: "dayperkOvertimeMultiplier") as? Double ?? 2
        dateOverrides = UserDataStore.shared.data(forKey: "dayperkWorkdayOverrides").flatMap {
            try? JSONDecoder().decode([String: Bool].self, from: $0)
        } ?? [:]
        dateOverrides = ChinaHolidayCalendar.merging(ChinaHolidayCalendar.bundledPlans(), into: dateOverrides, imported: [:]).overrides
        access.dataWillLock = { [weak self] in self?.endClockOutCelebration(); self?.endPaydayCelebration(); self?.tracking.pauseForDataLock() }
        access.sensitiveInformationWillHide = { [weak self] in self?.endClockOutCelebration(); self?.endPaydayCelebration(); self?.tracking.pauseForDataLock() }
        access.dataDidUnlock = { [weak tracking = self.tracking] in tracking?.startAfterDataUnlock() }
        tracking.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            if let self, self.clockOutCelebration != nil, self.tracking.state.isWorking || !self.isTodaySettled { self.endClockOutCelebration() }
            self?.objectWillChange.send()
            self?.refreshIfMonthChanged()
        }.store(in: &cancellables)
        workStatus.workingRequested = { [weak self] enabled, now in self?.tracking.setWorkingForStatus(enabled, at: now) }
        tracking.shouldBridgePause = { [weak self] in
            guard let self else { return true }
            return !self.workStatus.data.enabled || self.workStatus.data.selected.isWorking
        }
        var previouslyWorking = tracking.state.isWorking
        tracking.$state.sink { [weak self] state in
            guard let self else { return }
            let now = state.lastTick ?? Date()
            if state.isWorking != previouslyWorking {
                previouslyWorking = state.isWorking
                if state.isWorking { self.beginPaydayCelebration(at: now) }
                else { self.endPaydayCelebration() }
            }
            self.workStatus.updateWorking(state.isWorking, onDuty: state.activeWorkday == self.tracking.plan.businessDayKey(now, calendar: self.workCalendar), at: now)
        }.store(in: &cancellables)
        workStatus.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        payroll.objectWillChange.debounce(for: .milliseconds(40), scheduler: DispatchQueue.main).sink { [weak self] _ in self?.refreshPayroll() }.store(in: &cancellables)
        currency.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        privacy.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            if self?.privacy.isPrivacyModeEnabled == true { self?.endClockOutCelebration(); self?.endPaydayCelebration() }
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        access.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        appearance.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        tracking.updateCalendar(regional.calendar)
        refreshPayroll()
    }

    deinit { clockOutCelebrationTimer?.invalidate(); paydayCelebrationTimer?.invalidate() }

    var workCalendar: Calendar { regional.calendar }
    var usesChinaPayroll: Bool { regional.region == .china }
    var effectiveOverrides: [String: Bool] {
        if usesChinaPayroll { return dateOverrides }
        if rhythm.observesPublicHolidays == false { return regional.manualOverrides }
        return RegionalHolidayCalendar.shared.overrides(country: regional.region.rawValue,
            subdivision: regional.selectedPolicy.subdivision, manual: regional.manualOverrides)
    }
    var activeCurrencyCode: String { usesChinaPayroll ? currency.currentCurrency.currencyCode : regional.selectedPolicy.currency }
    var reportRecords: [WorkDayTotal] { tracking.state.days.filter { ($0.currencyCode ?? "CNY") == activeCurrencyCode } }

    func saveRegionalSettings(region: PayrollRegion, input: RegionalPayInput, policy: RegionalPayrollPolicy, timeZoneID: String, benefit: WithdrawableBenefit? = nil) throws {
        if let benefit { try benefit.validate() }
        if region != .china { _ = try InternationalPayrollCalculator().estimate(input: input, policy: policy) }
        let previous = workCalendar
        let previousKind = regional.selectedPolicy.effectiveEmploymentKind
        try regional.save(region: region, input: input, policy: policy, timeZoneID: timeZoneID)
        if let benefit { try regional.saveBenefit(benefit) }
        tracking.updateCalendar(workCalendar)
        func wallTime(_ value: Date) -> Date {
            workCalendar.date(bySettingHour: previous.component(.hour, from: value), minute: previous.component(.minute, from: value), second: 0, of: Date()) ?? value
        }
        schedule.startTime = wallTime(schedule.startTime); schedule.endTime = wallTime(schedule.endTime)
        try RepositoryManager.shared.workScheduleRepository.save(schedule, key: "current")
        if policy.effectiveEmploymentKind == .domesticWorker && previousKind != .domesticWorker {
            rhythm.enabled = false; rhythm.cycleDays = nil; rhythm.observesPublicHolidays = false
            schedule.workdays = Set(Weekday.allCases.filter { $0 != .sunday })
            overtimeMultiplier = 1
            try RepositoryManager.shared.workScheduleRepository.save(schedule, key: "current")
            UserDataStore.shared.set(try JSONEncoder().encode(rhythm), forKey: "dayperkWorkRhythm")
            UserDataStore.shared.set(overtimeMultiplier, forKey: "dayperkOvertimeMultiplier")
        }
        currency.setCurrency(region == .china ? (SupportedCurrency(rawValue: profile.currency) ?? .cny) : (SupportedCurrency(rawValue: policy.currency) ?? .usd))
        refreshPayroll()
    }

    var configuration: DayPerkConfiguration {
        DayPerkConfiguration(baseSalary: baseSalary, housingAllowance: housingAllowance,
                             workdaysPerMonth: profile.workdaysPerMonth, startTime: schedule.startTime, endTime: schedule.endTime,
                             weekdays: schedule.workdays, overtimeMultiplier: overtimeMultiplier, dateOverrides: usesChinaPayroll ? dateOverrides : regional.manualOverrides,
                             currency: currency.currentCurrency, payroll: payroll.configuration, followsCurrentMonth: payroll.followsCurrentMonth, dailyBreakMinutes: dailyBreakMinutes, breakMode: breakMode, breakPeriods: breakPeriods, linkCaffeine: linkCaffeine, overtimeDates: overtimeDates, includeHousingFundInRate: includeHousingFundInRate, includeHousingFundInEstimate: includeHousingFundInEstimate, dayStartMinute: dayStartMinute, payday: payday, automation: automation, rhythm: rhythm, timeZoneID: regional.timeZoneID)
    }

    var businessPlan: WorkPlan {
        var plan = tracking.plan
        plan.dayStartMinute = dayStartMinute
        plan.rhythm = rhythm
        plan.weekdays = Set(schedule.workdays.map { $0.calendarWeekday })
        plan.dateOverrides = effectiveOverrides
        let reference = configuration.referenceSchedule
        plan.startMinute = reference.startMinute; plan.endMinute = reference.endMinute
        plan.breakPeriods = reference.breakMode == .timeRanges ? reference.breaks : []
        plan.referenceSeconds = Double(reference.referenceMinutes * 60)
        plan.leaveDays = leaveDays
        return plan
    }

    private var businessTodayKey: String {
        businessPlan.businessDayKey(Date(), calendar: workCalendar)
    }

    private var businessDate: Date {
        businessPlan.businessDayStart(for: Date(), calendar: workCalendar)
    }

    func workdays(year: Int, month: Int) -> Int {
        let key = year * 12 + month
        if let value = workdaysByMonth[key] { return value }
        let value = businessPlan.regularWorkdays(year: year, month: month, calendar: workCalendar)
        workdaysByMonth[key] = value
        return value
    }

    func dailyTimeValueRate(monthlyBasis: Double, for key: String) -> Double {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return 0 }
        let dailyIncome = monthlyBasis / Double(max(1, workdays(year: parts[0], month: parts[1])))
        return businessPlan.timeValueRate(dailyIncome: dailyIncome, for: key)
    }

    func monthlyReferenceSeconds(year: Int, month: Int) -> Double {
        let key = year * 12 + month
        if let value = referenceSecondsByMonth[key] { return value }
        let value = businessPlan.monthlyReferenceSeconds(year: year, month: month, calendar: workCalendar)
        referenceSecondsByMonth[key] = value
        return value
    }

    var currentMonthWorkdays: Int {
        workdays(year: workCalendar.component(.year, from: businessDate), month: workCalendar.component(.month, from: businessDate))
    }

    var paydayLabel: String {
        let c = workCalendar
        guard let date = payday.date(year: c.component(.year, from: businessDate), month: c.component(.month, from: businessDate), plan: businessPlan, calendar: c) else { return "—" }
        return L10n.payday(date, calendar: workCalendar)
    }

    var today: WorkDayTotal {
        let key = businessTodayKey
        var value = tracking.state.days.first { $0.id == key } ?? WorkDayTotal(id: key)
        if value.settledAt == nil {
            value.overtimeSeconds = overtimeDates[key] != nil ? value.seconds : 0
            value.referenceSeconds = tracking.plan.referenceSeconds(for: key)
        }
        return value
    }

    var isTodaySettled: Bool { today.settledAt != nil }
    var settledBalance: Double { expectedIncome(for: today) - today.earned }
    var settledBalanceTitle: String {
        if settledBalance > 0.005 { return L10n.text("ui.today_you_gained.8a4293b8") }
        if settledBalance < -0.005 { return L10n.text("ui.unpaid_overtime_cost_you.7f80cfcd") }
        return L10n.text("ui.all_square_today.0635f05c")
    }
    func finishToday() {
        endPaydayCelebration()
        let wasSettled = isTodaySettled
        let menuAmountWasVisible = tracking.state.isWorking || !access.hideWhenPaused
        tracking.finishToday { self.calculatedExpectedIncome(for: $0) }
        refreshPayroll()
        guard !wasSettled, isTodaySettled, settledBalance > 0.005, !privacy.isPrivacyModeEnabled, !access.isDataLocked else { return }
        endClockOutCelebration()
        let celebration = ClockOutCelebrationState(started: Date(), menuAmountWasVisible: menuAmountWasVisible)
        clockOutCelebration = celebration
        let timer = Timer(fire: celebration.endsAt, interval: 0, repeats: false) { [weak self] _ in
            guard self?.clockOutCelebration?.started == celebration.started else { return }
            self?.endClockOutCelebration()
        }
        clockOutCelebrationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func endClockOutCelebration() {
        guard clockOutCelebration != nil else { return }
        clockOutCelebrationTimer?.invalidate(); clockOutCelebrationTimer = nil
        clockOutCelebration = nil
    }

    private func beginPaydayCelebration(at now: Date) {
        guard !access.isDataLocked, !privacy.isPrivacyModeEnabled,
              payday.includes(now, plan: businessPlan, calendar: workCalendar) else { return }
        endClockOutCelebration()
        endPaydayCelebration()
        let celebration = PaydayCelebrationState()
        paydayCelebration = celebration
        // 加载失败或浮窗未显示时也自动释放，不让待播放状态跨日残留。
        schedulePaydayEnd(id: celebration.id, after: 15)
    }

    func paydayAnimationDidStart(id: UUID) {
        guard var celebration = paydayCelebration, celebration.id == id, celebration.started == nil else { return }
        celebration.started = Date()
        paydayCelebration = celebration
        schedulePaydayEnd(id: id, after: PaydayCelebrationState.duration + 0.2)
    }

    private func schedulePaydayEnd(id: UUID, after interval: TimeInterval) {
        paydayCelebrationTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in self?.endPaydayCelebration(id: id) }
        paydayCelebrationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func endPaydayCelebration(id: UUID? = nil) {
        guard id == nil || paydayCelebration?.id == id else { return }
        paydayCelebrationTimer?.invalidate(); paydayCelebrationTimer = nil
        paydayCelebration = nil
    }

    var monthEarned: Double {
        let prefix = String(businessTodayKey.prefix(7))
        return reportRecords.filter { $0.id.hasPrefix(prefix) }.reduce(0) { $0 + $1.earned }
    }

    var minuteRate: Double {
        (isTodaySettled ? today.ratePerSecond ?? tracking.plan.ratePerSecond : tracking.plan.ratePerSecond) * 60
    }

    func updateWorkdayOverrides(_ value: [String: Bool]) {
        if !usesChinaPayroll {
            regional.updateOverrides(value); refreshPayroll(); return
        }
        dateOverrides = value
        UserDataStore.shared.set(try? JSONEncoder().encode(value), forKey: "dayperkWorkdayOverrides")
        refreshPayroll()
    }

    /// 时间预算按参考工时计算；历史和已结算记录保留快照，加班报酬由工资预估单独处理。
    func expectedWorkSeconds(for day: WorkDayTotal) -> Double {
        tracking.plan.expectedWorkSeconds(for: day, calendar: workCalendar,
            preservingExisting: day.id < businessTodayKey || day.settledAt != nil)
    }

    func expectedIncome(for day: WorkDayTotal) -> Double {
        if day.id < businessTodayKey || day.settledAt != nil, let frozen = day.expectedIncome {
            return frozen
        }
        guard (day.currencyCode ?? activeCurrencyCode) == activeCurrencyCode else { return 0 }
        return calculatedExpectedIncome(for: day)
    }

    private func calculatedExpectedIncome(for day: WorkDayTotal, refreshHistory: Bool = false) -> Double {
        let parts = day.id.split(separator: "-").compactMap { Int($0) }
        let calendar = workCalendar
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return 0 }
        if !usesChinaPayroll { return regionalExpectedIncome(for: day) }
        var c = payroll.configuration
        c.taxYear = parts[0]; c.taxMonth = parts[1]
        let extras = overtimeIncomeByMonth(year: parts[0], refreshHistory: refreshHistory)
        c.estimatedExtraIncomeByMonth = extras
        c.estimatedExtraIncomeByMonth[parts[1]] = nil
        let baseline = chinaTrackingBasis(gross: profile.monthlySalary, configuration: c)
        let boundary = calendar.date(byAdding: .minute, value: dayStartMinute, to: date) ?? date
        let days = workdays(year: parts[0], month: parts[1])
        // 时间差额只使用基础工时预算；登记加班费另计入工资预估，避免超时仍显示白赚。
        let hasReferenceBudget = businessPlan.isRegularWorkday(boundary, calendar: calendar) || overtimeDates[day.id] != nil
        let income = hasReferenceBudget && days > 0 ? baseline / Double(days) * (activeLeave(for: day.id)?.payableFraction ?? 1) : 0
        return PayrollCalculator.money(income)
    }

    var isWorkday: Bool {
        tracking.plan.isWorkday(Date(), calendar: workCalendar)
    }

    var isOvertime: Bool {
        guard tracking.state.isWorking else { return false }
        return overtimeDates[businessTodayKey] != nil
    }

    var hasExceededReferenceHours: Bool {
        today.unpaidOvertimeSeconds > 0
    }

    var hasSecuredDepartureSurplus: Bool {
        tracking.state.securedSurplusDay == businessTodayKey
    }

    var caffeineRuleExplanation: String {
        func status(_ title: String, _ on: Bool) -> String { L10n.text(title) + ": " + L10n.text(on ? L10n.text("ui.on.8da97ddd") : L10n.text("ui.off.3fd47edc")) }
        return [status(L10n.text("ui.start_tracking_when_caffeine_turns.e1db1756"), linkCaffeine && automation.caffeineStartsWork),
                status(L10n.text("ui.extend_the_linking_window_by_thirty.b4c8c769"), automation.caffeineBuffer),
                status(L10n.text("ui.pause_when_caffeine_turns_off_outsi.fd0e9bc5"), linkCaffeine && automation.caffeineStopsWork),
                L10n.text("ui.link_only_on_workdays_or_registered.b8e2acbb"),
                L10n.text("ui.disable_each_rule_in_work_linking_m.2cf23190")].joined(separator: "\n")
    }

    var trackingRuleExplanation: String {
        func status(_ title: String, _ on: Bool) -> String { L10n.text(title) + ": " + L10n.text(on ? L10n.text("ui.on.8da97ddd") : L10n.text("ui.off.3fd47edc")) }
        return [status(L10n.text("ui.discard_sessions_stopped_within_ten.2cfa4ab1"), automation.discardShortSessions),
                status(L10n.text("ui.count_pauses_resumed_within_ten_sec.e8e13e4d"), automation.bridgeShortPauses),
                L10n.format("automation.seconds_summary", String(Int(automation.protectionInterval))),
                status(L10n.text("ui.pause_on_screen_lock_display_sleep.f3dedfeb"), automation.pauseOnSystemLock),
                L10n.text("ui.an_interruption_longer_than_five_se.1e22a9c9"),
                L10n.text("ui.set_each_rule_in_work_linking_data.35bfcb06")].joined(separator: "\n")
    }

    private func displayMoney(_ value: Double) -> String {
        privacy.isPrivacyModeEnabled ? "•••" : currency.formatAmount(value)
    }

    var rateExplanation: String {
        func formula(_ basis: Double) -> String {
            let hours = Double(configuration.referenceMinutes(for: businessTodayKey)) / 60
            let denominator = "\(currentMonthWorkdays) \(L10n.text("ui.days.49da61ce")) ÷ \(hours.formatted(.number.locale(LocalizationManager.shared.currentLocale)))h"
            return "\(L10n.text("ui.monthly_base.4dee13f7")) \(displayMoney(basis)) ÷ \(denominator) ÷ 60\n= \(L10n.format("ui.1.aee4ea58", displayMoney(minuteRate)))"
        }
        if !usesChinaPayroll {
            return formula(regionalBasis()) + "\n\n" + L10n.text("ui.only_configured_after_tax_withdrawa.353441d4")
        }
        var c = payroll.configuration
        c.taxYear = workCalendar.component(.year, from: businessDate)
        c.taxMonth = workCalendar.component(.month, from: businessDate)
        c.estimatedExtraIncomeByMonth = overtimeIncomeByMonth(year: c.taxYear)
        c.estimatedExtraIncomeByMonth[c.taxMonth] = nil
        let basis = chinaTrackingBasis(gross: profile.monthlySalary, configuration: c)
        return formula(basis) + "\n\n" + L10n.text("ui.deductions_subtract_employee_housin.7f5a057f")
    }

    var workHoursExplanation: WorkHoursExplanation {
        let shift = rhythm.schedule(for: businessTodayKey, fallback: configuration.referenceSchedule)
        let hours = Double(shift.referenceMinutes) / 60
        let rest = Double(shift.restMinutes) / 60
        func time(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
        let period = "\(time(shift.startMinute))–\(time(shift.endMinute))" + (shift.endMinute < shift.startMinute ? " (+1)" : "")
        let rows = [
            HelpFormulaRow(amount: period, label: L10n.text("ui.work_schedule.3d026629")),
            HelpFormulaRow(amount: L10n.format("ui.1.9229f247", String(describing: (hours + rest).formatted(.number.locale(LocalizationManager.shared.currentLocale)))), label: L10n.text("ui.schedule_duration.08e399ee")),
            HelpFormulaRow(amount: L10n.format("ui.1.3c2b25ef", String(describing: rest.formatted(.number.locale(LocalizationManager.shared.currentLocale)))), label: L10n.text("ui.break_duration.1a83afa6")),
            HelpFormulaRow(amount: L10n.format("ui.1.798f3920", String(describing: hours.formatted(.number.locale(LocalizationManager.shared.currentLocale)))), label: L10n.text("ui.daily_reference_hours.c7992324"), isTotal: true),
        ]
        return WorkHoursExplanation(title: L10n.format("ui.1.745f4ea0", String(describing: hours.formatted(.number.locale(LocalizationManager.shared.currentLocale)))),
                                    detail: L10n.format("ui.1_2_3_4.6f872eb4", String(describing: period), String(describing: (hours + rest).formatted(.number.locale(LocalizationManager.shared.currentLocale))), String(describing: rest.formatted(.number.locale(LocalizationManager.shared.currentLocale))), String(describing: hours.formatted(.number.locale(LocalizationManager.shared.currentLocale)))), rows: rows)
    }

    func updateRateOptions(annualBonus: Bool? = nil, deduct: Bool? = nil) {
        var c = configuration
        if let annualBonus {
            c.payroll.includeAnnualBonus = annualBonus
        }
        if let deduct {
            c.payroll.isEnabled = deduct
        }
        do {
            try Self.validate(c, requiresChinaPayroll: usesChinaPayroll)
            payroll.includeAnnualBonus = c.payroll.includeAnnualBonus
            payroll.isEnabled = c.payroll.isEnabled
            actionError = nil
            refreshPayroll()
        } catch { actionError = error.localizedDescription }
    }

    var salaryFormulaRows: [HelpFormulaRow] {
        func extraRows(net: Double) -> [HelpFormulaRow] {
            guard !estimateBenefits.isEmpty else { return [] }
            return estimateBenefits.map { HelpFormulaRow(amount: "+ " + displayMoney($0.monthlyAmount),
                label: $0.displayName, isUserProvidedLabel: !$0.usesHousingFundAmount || !$0.name.isEmpty) }
                + [HelpFormulaRow(amount: "= " + displayMoney(net + benefitForEstimate),
                    label: L10n.text("benefits.take_home_total"), isTotal: true)]
        }
        if !usesChinaPayroll, let value = regionalEstimate {
            return [HelpFormulaRow(amount: displayMoney(value.annualGross / 12), label: L10n.text("ui.annual_gross_pay_12.681b2885"))]
                + value.contributions.filter { $0.employee > 0 }.map { HelpFormulaRow(amount: "− " + displayMoney($0.employee / 12), label: $0.name) }
                + [HelpFormulaRow(amount: "− " + displayMoney((value.annualIncomeTax + value.annualRegionalTax) / 12), label: L10n.text("ui.income_tax_12.3a4adf65")),
                   HelpFormulaRow(amount: "= " + displayMoney(value.cashNet / 12), label: L10n.text("ui.estimated_monthly_net.5949c66d"), isTotal: true)]
                + extraRows(net: value.cashNet / 12)
        }
        let b = breakdown
        let current = payroll.records.first { $0.isSalary && $0.year == payroll.configuration.taxYear && $0.month == payroll.configuration.taxMonth }
        let social = current?.personalSocialInsurance ?? b.employeeSocialInsurance
        let fund = current?.personalHousingFund ?? b.housingFund
        var rows: [HelpFormulaRow] = []
        if abs(b.grossMonthlyIncome - b.overtimeGross - profile.monthlySalary) < 0.01 {
            rows.append(HelpFormulaRow(amount: displayMoney(baseSalary), label: L10n.text("ui.base_salary.91910663")))
            rows.append(HelpFormulaRow(amount: "+ " + displayMoney(housingAllowance), label: L10n.text("ui.housing_allowances.4892caa0")))
        } else {
            rows.append(HelpFormulaRow(amount: displayMoney(b.grossMonthlyIncome), label: L10n.text("ui.reported_income_this_month.71276348")))
        }
        if b.overtimeGross > 0 {
            rows.append(HelpFormulaRow(amount: "+ " + displayMoney(b.overtimeGross), label: L10n.text("ui.estimated_overtime_pay.35b587aa")))
        }
        if let current {
            if let social = current.personalSocialInsurance, let fund = current.personalHousingFund,
               abs(social + fund - current.employeeDeductions) < 0.01
            {
                rows.append(HelpFormulaRow(amount: "− " + displayMoney(social), label: L10n.text("ui.employee_social_insurance.1599ba3b")))
                rows.append(HelpFormulaRow(amount: "− " + displayMoney(fund), label: L10n.text("ui.employee_housing_fund.a018d750")))
            } else {
                rows.append(HelpFormulaRow(amount: "− " + displayMoney(current.employeeDeductions), label: L10n.text("ui.recorded_employee_contributions.be7cffad")))
            }
        } else {
            rows.append(HelpFormulaRow(amount: "− " + displayMoney(social), label: L10n.text("ui.employee_social_insurance.1599ba3b")))
            rows.append(HelpFormulaRow(amount: "− " + displayMoney(fund), label: L10n.text("ui.employee_housing_fund.a018d750")))
        }
        rows.append(HelpFormulaRow(amount: "− " + displayMoney(b.individualIncomeTax), label: L10n.text("ui.salary_tax_this_month.60d9b798")))
        rows.append(HelpFormulaRow(amount: "= " + displayMoney(b.netMonthlyIncome), label: L10n.text("ui.take_home_salary.841816fd"), isTotal: true))
        rows += extraRows(net: b.netMonthlyIncome)
        return rows
    }

    var salaryExplanation: String {
        L10n.text("ui.monthly_take_home_estimate_after_ta.6e02423e") + salaryFormulaRows.map { "\($0.amount)  \($0.label)" }.joined(separator: "\n") + L10n.text("ui.social_insurance_is_estimated_check.b072b958")
    }

    static func validate(_ c: DayPerkConfiguration, requiresChinaPayroll: Bool = true) throws {
        try c.rhythm.validate()
        try c.automation.validate()
        let numbers = [c.baseSalary, c.housingAllowance, c.overtimeMultiplier, c.payroll.contributionBase,
                       c.payroll.housingFundBase, c.payroll.housingFundRate, c.payroll.monthlySpecialAdditionalDeduction,
                       c.payroll.annualBonusBase, c.payroll.annualBonusMonths, c.payroll.policy.pensionRate,
                       c.payroll.policy.medicalRate, c.payroll.policy.unemploymentRate, c.payroll.policy.socialBaseMinimum,
                       c.payroll.policy.socialBaseMaximum, c.payroll.policy.housingBaseMinimum,
                       c.payroll.policy.housingBaseMaximum, c.payroll.policy.employerHousingFundRate]
            + [c.payroll.policy.medicalBaseMinimum, c.payroll.policy.medicalBaseMaximum, c.payroll.policy.unemploymentBaseMinimum, c.payroll.policy.unemploymentBaseMaximum, c.payroll.policy.personalMedicalFixed, c.payroll.policy.supplementaryFundRate, c.payroll.policy.employerSupplementaryFundRate, c.payroll.policy.employerPensionRate, c.payroll.policy.employerMedicalRate, c.payroll.policy.employerUnemploymentRate, c.payroll.policy.employerMaternityRate, c.payroll.policy.employerInjuryRate].compactMap { $0 }
        guard numbers.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1_000_000_000 }) else {
            throw DayPerkInputError(message: L10n.text("ui.amounts_and_rates_must_be_valid_non.9df198ca"))
        }
        guard (!requiresChinaPayroll || c.baseSalary + c.housingAllowance > 0), (1 ... 31).contains(c.workdaysPerMonth), !c.weekdays.isEmpty else {
            throw DayPerkInputError(message: L10n.text("ui.enter_positive_monthly_income_1_31.a6dd3f06"))
        }
        guard (1 ... 31).contains(c.payday.day) else { throw DayPerkInputError(message: L10n.text("ui.payday_must_be_between_1_and_31.8f5500a2")) }
        guard (0 ..< 1440).contains(c.dayStartMinute) else { throw DayPerkInputError(message: L10n.text("ui.invalid_day_start_time.8bbecfb3")) }
        try c.referenceSchedule.validate()
        guard c.dailyBreakMinutes >= 0, c.workMinutesPerDay > 0 else {
            throw DayPerkInputError(message: L10n.text("ui.reference_breaks_must_be_shorter_th.3fda3da0"))
        }
        guard c.overtimeDates.values.allSatisfy(OvertimeRateInput.isValid) else { throw DayPerkInputError(message: L10n.text("ui.overtime_multipliers_must_be_greate.c2b4b41e")) }
        let p = c.payroll.policy
        guard p.socialBaseMinimum <= p.socialBaseMaximum, p.housingBaseMinimum <= p.housingBaseMaximum else {
            throw DayPerkInputError(message: L10n.text("ui.the_minimum_contribution_base_canno.fe3381e2"))
        }
        guard (p.medicalBaseMinimum ?? p.socialBaseMinimum) <= (p.medicalBaseMaximum ?? p.socialBaseMaximum),
              (p.unemploymentBaseMinimum ?? p.socialBaseMinimum) <= (p.unemploymentBaseMaximum ?? p.socialBaseMaximum)
        else {
            throw DayPerkInputError(message: L10n.text("ui.medical_and_unemployment_minimum_ba.5d4300d1"))
        }
        guard c.payroll.housingFundRate + (p.supplementaryFundRate ?? 0) <= 1.000000001, p.employerHousingFundRate + (p.employerSupplementaryFundRate ?? 0) <= 1.000000001 else {
            throw DayPerkInputError(message: L10n.text("ui.total_employee_or_employer_housing.24c2a57b"))
        }
        guard ([p.pensionRate, p.medicalRate, p.unemploymentRate, p.employerHousingFundRate, c.payroll.housingFundRate] + [p.employerPensionRate, p.employerMedicalRate, p.employerUnemploymentRate, p.employerMaternityRate, p.employerInjuryRate].compactMap { $0 }).allSatisfy({ $0 <= 1 }),
              c.payroll.annualBonusMonths <= 24, OvertimeRateInput.isValid(c.overtimeMultiplier)
        else {
            throw DayPerkInputError(message: L10n.text("ui.rates_must_be_0_100_bonuses_at_most.37f50862"))
        }
        guard (1 ... 12).contains(c.payroll.taxMonth), (1 ... 12).contains(c.payroll.employmentStartMonth), (2020 ... 2100).contains(c.payroll.taxYear), (2020 ... 2100).contains(c.payroll.employmentStartYear ?? c.payroll.taxYear) else {
            throw DayPerkInputError(message: L10n.text("ui.check_the_tax_year_and_month.229ba88b"))
        }
        guard c.payroll.annualBonusStartDate.timeIntervalSince1970.isFinite,
              (1900 ... 2100).contains(Calendar(identifier: .gregorian).component(.year, from: c.payroll.annualBonusStartDate)) else {
            throw DayPerkInputError(message: L10n.text("ui.enter_a_valid_hire_date_for_bonus_p.a008c8cd"))
        }
        if c.payroll.isEnabled && requiresChinaPayroll {
            let code = c.currency == .system ? MoneyDisplaySettings.shared.systemCurrency : c.currency
            guard code == .cny else { throw DayPerkInputError(message: L10n.text("ui.chinese_payroll_estimates_require_c.0720a0f3")) }
        }
    }

    func saveBenefits(_ values: [WithdrawableBenefit], region: PayrollRegion, currency: String) throws {
        try regional.saveBenefits(values, region: region, currency: currency)
        if region == regional.region && currency == activeCurrencyCode { refreshPayroll(updateCurrentDay: true) }
        objectWillChange.send()
    }

    func saveScheduleRules(_ rules: [WorkScheduleRule]?) throws {
        var next = rhythm; next.scheduleRules = rules
        next.startNewRules(comparedTo: rhythm, on: WorkPlan.dayKey(Date(), calendar: workCalendar))
        guard rhythm != next else { return }
        try next.validate()
        try UserDataStore.shared.persist(["dayperkWorkRhythm": JSONEncoder().encode(next)])
        rhythm = next
        refreshPayroll(updateCurrentDay: true)
    }

    @discardableResult func correctWorkSchedules(from: Date, through: Date, schedule: DayWorkSchedule? = nil, ruleID: UUID? = nil) throws -> Int {
        let rule = rhythm.scheduleRules?.first { $0.id == ruleID }
        guard (ruleID == nil && schedule != nil) || (ruleID != nil && rule != nil && schedule == nil) else {
            throw DayPerkInputError(message: L10n.text("correction.select_rule"))
        }
        let selected = try WorkDataCorrection.dates(from: from, through: through, asOf: businessDate,
            plan: businessPlan, calendar: workCalendar, rule: rule)
        guard !selected.isEmpty, let shift = schedule ?? rule?.schedule else {
            throw DayPerkInputError(message: L10n.text("correction.no_matches"))
        }
        try shift.validate()
        var nextRhythm = rhythm
        var daySchedules = nextRhythm.daySchedules ?? [:]
        for key in selected { daySchedules[key] = shift }
        nextRhythm.daySchedules = daySchedules
        try nextRhythm.validate()
        var nextPlan = businessPlan
        nextPlan.rhythm = nextRhythm
        for day in tracking.state.days where selected.contains(day.id) && (day.currencyCode ?? "CNY") == activeCurrencyCode {
            let expected = day.expectedIncome ?? calculatedExpectedIncome(for: day)
            let payable = activeLeave(for: day.id)?.payableFraction ?? 1
            let oldFullSeconds = activeLeave(for: day.id) == nil ? (day.referenceSeconds ?? businessPlan.scheduledReferenceSeconds(for: day.id)) : businessPlan.scheduledReferenceSeconds(for: day.id)
            let dailyBasis = payable > 0 ? expected / payable : (day.ratePerSecond ?? 0) * oldFullSeconds
            nextPlan.dayRates[day.id] = dailyBasis / Double(shift.referenceMinutes * 60)
            nextPlan.expectedIncomes[day.id] = expected
            nextPlan.dayGrossRates[day.id] = (day.grossRatePerSecond ?? 0) * oldFullSeconds / Double(shift.referenceMinutes * 60)
        }
        try tracking.correctSchedules(nextPlan, days: Set(selected), preferences: ["dayperkWorkRhythm": JSONEncoder().encode(nextRhythm)])
        rhythm = nextRhythm
        refreshPayroll()
        return selected.count
    }

    private func correctionPricingPlan(for key: String) -> WorkPlan {
        var plan = tracking.plan
        guard !tracking.state.days.contains(where: { $0.id == key }) else { return plan }
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return plan }
        let basis: Double
        if usesChinaPayroll {
            var config = payroll.configuration
            config.taxYear = parts[0]; config.taxMonth = parts[1]
            config.estimatedExtraIncomeByMonth = overtimeIncomeByMonth(year: parts[0])
            config.estimatedExtraIncomeByMonth[parts[1]] = nil
            basis = chinaTrackingBasis(gross: profile.monthlySalary, configuration: config)
        } else { basis = regionalBasis() }
        plan.dayRates[key] = dailyTimeValueRate(monthlyBasis: basis, for: key)
        plan.dayGrossRates[key] = dailyTimeValueRate(monthlyBasis: usesChinaPayroll ? profile.monthlySalary : regional.input.annualBase / 12, for: key)
        plan.expectedIncomes[key] = calculatedExpectedIncome(for: WorkDayTotal(id: key))
        return plan
    }
    func previewWorkCorrection(_ key: String, seconds: Double) -> WorkDayTotal {
        tracking.previewCorrection(key, seconds: seconds, using: correctionPricingPlan(for: key))
    }
    func correctWorkTime(_ key: String, seconds: Double) throws {
        try tracking.correctDay(key, seconds: seconds, using: correctionPricingPlan(for: key))
        refreshPayroll()
    }

    func saveConfiguration(_ c: DayPerkConfiguration) throws {
        try Self.validate(c, requiresChinaPayroll: usesChinaPayroll)
        var nextRhythm = c.rhythm
        nextRhythm.startNewRules(comparedTo: rhythm, on: WorkPlan.dayKey(Date(), calendar: workCalendar))
        tracking.updatePlan(tracking.plan)
        var newProfile = profile
        newProfile.monthlySalary = c.baseSalary + c.housingAllowance
        newProfile.workdaysPerMonth = c.workdaysPerMonth
        newProfile.currency = usesChinaPayroll ? c.currency.rawValue : profile.currency
        newProfile.updatedAt = Date()
        let newSchedule = ReferenceSchedule(startTime: c.startTime, endTime: c.endTime, workdays: c.weekdays)
        try RepositoryManager.shared.userProfileRepository.save(newProfile, key: "current")
        try RepositoryManager.shared.workScheduleRepository.save(newSchedule, key: "current")
        profile = newProfile
        schedule = newSchedule
        baseSalary = c.baseSalary
        housingAllowance = c.housingAllowance
        includeHousingFundInRate = c.includeHousingFundInRate
        includeHousingFundInEstimate = c.includeHousingFundInEstimate
        UserDataStore.shared.set(includeHousingFundInRate, forKey: "includeHousingFundInRate")
        UserDataStore.shared.set(includeHousingFundInEstimate, forKey: "includeHousingFundInEstimate")
        breakMode = c.breakMode; breakPeriods = c.breakPeriods; linkCaffeine = c.linkCaffeine; overtimeDates = c.overtimeDates
        UserDataStore.shared.set(breakMode.rawValue, forKey: "dayperkBreakMode")
        try UserDataStore.shared.set(JSONEncoder().encode(breakPeriods), forKey: "dayperkBreakPeriods")
        UserDataStore.shared.set(linkCaffeine, forKey: "dayperkLinkCaffeine")
        rhythm = nextRhythm
        try UserDataStore.shared.set(JSONEncoder().encode(rhythm), forKey: "dayperkWorkRhythm")
        automation = c.automation
        try UserDataStore.shared.set(JSONEncoder().encode(automation), forKey: "dayperkAutomationRules")
        try UserDataStore.shared.set(JSONEncoder().encode(overtimeDates), forKey: "dayperkOvertimeDates")
        payday = c.payday
        try UserDataStore.shared.set(JSONEncoder().encode(payday), forKey: "dayperkPaydayRule")
        dayStartMinute = c.dayStartMinute
        UserDataStore.shared.set(dayStartMinute, forKey: "dayperkDayStartMinute")
        dailyBreakMinutes = c.dailyBreakMinutes
        UserDataStore.shared.set(dailyBreakMinutes, forKey: "dayperkDailyBreakMinutes")
        overtimeMultiplier = c.overtimeMultiplier
        if usesChinaPayroll {
            dateOverrides = ChinaHolidayCalendar.merging(ChinaHolidayCalendar.bundledPlans(), into: c.dateOverrides, imported: [:]).overrides
        } else { regional.updateOverrides(c.dateOverrides) }
        UserDataStore.shared.set(baseSalary, forKey: "dayperkBaseSalary")
        UserDataStore.shared.set(overtimeMultiplier, forKey: "dayperkOvertimeMultiplier")
        if usesChinaPayroll { try UserDataStore.shared.set(JSONEncoder().encode(dateOverrides), forKey: "dayperkWorkdayOverrides") }
        payroll.isEnabled = c.payroll.isEnabled
        payroll.contributionBase = c.payroll.contributionBase
        payroll.housingFundBase = c.payroll.housingFundBase
        payroll.housingFundRate = c.payroll.housingFundRate
        payroll.monthlySpecialAdditionalDeduction = c.payroll.monthlySpecialAdditionalDeduction
        payroll.taxMonth = c.payroll.taxMonth
        payroll.taxYear = c.payroll.taxYear
        payroll.employmentStartMonth = c.payroll.employmentStartMonth
        payroll.employmentStartYear = c.payroll.employmentStartYear ?? c.payroll.taxYear
        payroll.includeAnnualBonus = c.payroll.includeAnnualBonus
        payroll.annualBonusBase = c.payroll.annualBonusBase
        payroll.annualBonusMonths = c.payroll.annualBonusMonths
        payroll.prorateAnnualBonus = c.payroll.prorateAnnualBonus
        payroll.annualBonusStartDate = c.payroll.annualBonusStartDate
        payroll.policy = c.payroll.policy
        payroll.followsCurrentMonth = c.followsCurrentMonth
        if usesChinaPayroll { currency.setCurrency(c.currency) }
        refreshPayroll(updateCurrentDay: true)
    }

    func upsertRecord(_ record: PayrollIncomeRecord) throws {
        payroll.records = try Self.upserting(record, into: payroll.records)
        refreshPayroll()
    }

    static func upserting(_ record: PayrollIncomeRecord, into records: [PayrollIncomeRecord]) throws -> [PayrollIncomeRecord] {
        let amounts = [record.income, record.paidTax, record.employeeDeductions,
                       record.basicDeduction ?? 5000, record.specialAdditionalDeduction ?? 0,
                       record.personalSocialInsurance ?? 0, record.personalHousingFund ?? 0, record.employerHousingFund ?? 0, record.otherDeduction ?? 0]
        guard (2020 ... 2100).contains(record.year), (1 ... 12).contains(record.month),
              amounts.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1_000_000_000 }), record.paidTax <= record.income
        else {
            throw DayPerkInputError(message: L10n.text("ui.check_the_year_month_income_deducti.688150f9"))
        }
        if record.isSalary, records.contains(where: { $0.id != record.id && $0.isSalary && $0.year == record.year && $0.month == record.month }) {
            throw DayPerkInputError(message: L10n.text("ui.that_month_already_has_a_salary_rec.37bd11fe"))
        }
        var updated = records
        if let i = updated.firstIndex(where: { $0.id == record.id }) {
            updated[i] = record
        } else {
            updated.append(record)
        }
        return updated
    }

    private var taxRefreshSignature: String {
        let key = businessTodayKey
        let minutes = Int(tracking.state.days.reduce(0) { $0 + (overtimeDates[$1.id] != nil ? $1.seconds : $1.overtimeSeconds) } / 60)
        return "\(key)|\(minutes)|\(tracking.state.isWorking)"
    }

    private func overtimeIncomeByMonth(year: Int, refreshHistory: Bool = false) -> [Int: Double] {
        let cacheKey = year * 2 + (refreshHistory ? 1 : 0)
        if let cached = overtimeTotalsDuringRefresh?[cacheKey] { return cached }
        let overtimePlan = WorkPlan(overtimeDates: overtimeDates)
        var values: [Int: Double] = [:]
        for day in reportRecords {
            let parts = day.id.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3, parts[0] == year else { continue }
            let rate = dailyTimeValueRate(monthlyBasis: profile.monthlySalary, for: day.id)
            if (day.id < businessTodayKey || day.settledAt != nil), !refreshHistory {
                values[parts[1], default: 0] += overtimePlan.registeredOvertimeGross(for: day, rate: rate)
            } else if let multiplier = overtimeDates[day.id] {
                values[parts[1], default: 0] += min(day.seconds, Double(max(0, configuration.referenceMinutes(for: day.id)) * 60)) * multiplier * rate
            }
        }
        let result = values.mapValues(PayrollCalculator.money)
        overtimeTotalsDuringRefresh?[cacheKey] = result
        return result
    }

    private func refreshIfMonthChanged() {
        let key = taxRefreshSignature
        if key != lastTaxMonth {
            refreshPayroll()
        }
    }

    func refreshHistoricalData() {
        refreshPayroll(refreshHistory: true)
    }

    func refreshPayroll(refreshHistory: Bool = false, leaveChangedDays: Set<String> = [], updateCurrentDay: Bool = false) {
        // 同一次结算会多次读取同月作息，日历只遍历一次；配置刷新时统一失效。
        referenceSecondsByMonth.removeAll(keepingCapacity: true)
        workdaysByMonth.removeAll(keepingCapacity: true)
        // 历史每天共用同一年的加班汇总，避免在每条记录里重复扫描整个账本。
        overtimeTotalsDuringRefresh = [:]
        defer { overtimeTotalsDuringRefresh = nil }
        lastTaxMonth = taxRefreshSignature
        if !usesChinaPayroll { refreshRegionalPayroll(refreshHistory: refreshHistory, leaveChangedDays: leaveChangedDays, updateCurrentDay: updateCurrentDay); return }
        var estimateConfig = payroll.configuration
        let businessDate = businessPlan.businessDayStart(for: Date(), calendar: workCalendar)
        if payroll.followsCurrentMonth {
            estimateConfig.taxYear = workCalendar.component(.year, from: businessDate)
            estimateConfig.taxMonth = workCalendar.component(.month, from: businessDate)
        }
        estimateConfig.isEnabled = true
        estimateConfig.estimatedExtraIncomeByMonth = overtimeIncomeByMonth(year: estimateConfig.taxYear, refreshHistory: refreshHistory)
        estimateConfig.estimatedUnpaidLeaveByMonth = unpaidLeaveDeductions(year: estimateConfig.taxYear, monthlyGross: profile.monthlySalary)
        breakdown = MainlandChinaPayrollModule(configuration: estimateConfig).monthly(gross: profile.monthlySalary)
        do {
            let legacyFund = PayrollCalculator.trackingBasis(gross: profile.monthlySalary, configuration: estimateConfig, includeHousingFund: true).housingFund
            try regional.migrateHousingFundIncome(monthlyAmount: legacyFund, currency: activeCurrencyCode)
        } catch { actionError = error.localizedDescription; return }
        let calendar = workCalendar
        let start = calendar.component(.hour, from: schedule.startTime) * 60 + calendar.component(.minute, from: schedule.startTime)
        let end = calendar.component(.hour, from: schedule.endTime) * 60 + calendar.component(.minute, from: schedule.endTime)
        var liveConfig = payroll.configuration
        liveConfig.taxYear = calendar.component(.year, from: businessDate)
        liveConfig.taxMonth = calendar.component(.month, from: businessDate)
        liveConfig.estimatedExtraIncomeByMonth = overtimeIncomeByMonth(year: liveConfig.taxYear)
        liveConfig.estimatedExtraIncomeByMonth[liveConfig.taxMonth] = nil
        let live = chinaTrackingBasis(gross: profile.monthlySalary, configuration: liveConfig)
        var dayRates: [String: Double] = [:]
        var dayGrossRates: [String: Double] = [:]
        for day in reportRecords {
            let parts = day.id.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { continue }
            var config = payroll.configuration
            config.taxYear = parts[0]; config.taxMonth = parts[1]
            config.estimatedExtraIncomeByMonth = overtimeIncomeByMonth(year: config.taxYear, refreshHistory: refreshHistory)
            config.estimatedExtraIncomeByMonth[config.taxMonth] = nil
            let value = chinaTrackingBasis(gross: profile.monthlySalary, configuration: config)
            dayRates[day.id] = dailyTimeValueRate(monthlyBasis: value, for: day.id)
            dayGrossRates[day.id] = dailyTimeValueRate(monthlyBasis: profile.monthlySalary, for: day.id)
        }
        var expectedIncomes: [String: Double] = [:]
        for day in reportRecords {
            expectedIncomes[day.id] = refreshHistory || leaveChangedDays.contains(day.id) ? calculatedExpectedIncome(for: day, refreshHistory: true) : expectedIncome(for: day)
        }
        expectedIncomes[businessTodayKey] = calculatedExpectedIncome(for: today, refreshHistory: refreshHistory)
        tracking.updatePlan(WorkPlan(weekdays: Set(schedule.workdays.map { $0.calendarWeekday }), dateOverrides: effectiveOverrides,
                                     startMinute: start, endMinute: end, ratePerSecond: dailyTimeValueRate(monthlyBasis: live, for: businessTodayKey),
                                     overtimeMultiplier: overtimeMultiplier, breakPeriods: breakMode == .timeRanges ? breakPeriods : [], linkCaffeine: linkCaffeine, overtimeDates: overtimeDates, dayRates: dayRates, dayStartMinute: dayStartMinute, expectedIncomes: expectedIncomes, grossRatePerSecond: dailyTimeValueRate(monthlyBasis: profile.monthlySalary, for: businessTodayKey), dayGrossRates: dayGrossRates, defaultDailyExpectedIncome: live / Double(max(1, currentMonthWorkdays)), referenceSeconds: Double(max(0, configuration.workMinutesPerDay) * 60), rhythm: rhythm, currencyCode: activeCurrencyCode, automation: automation, leaveDays: leaveDays), leaveChangedDays: leaveChangedDays, updateCurrentDay: updateCurrentDay)
        if refreshHistory {
            tracking.refreshHistory()
        }
    }
}

// 日期安排与休假一起落盘，避免只保存一半而让旧状态重新出现。
extension DayPerkModel {
    func saveCalendar(overrides: [String: Bool], overtime: [String: Double], days: [String: LeaveDay], requests: [LeaveRequest], changed: Set<String>) throws {
        try LeaveLedger.validate(days); try LeaveRequests.validate(requests, calendar: workCalendar)
        let requests = try requests.filter { request in
            guard request.excludedPortions?.isEmpty == false else { return true }
            return try !LeaveRequests.materialize([request], plan: businessPlan, calendar: workCalendar).isEmpty
        }
        let overrides = usesChinaPayroll ? ChinaHolidayCalendar.merging(ChinaHolidayCalendar.bundledPlans(), into: overrides, imported: [:]).overrides : overrides
        var preferences: [String: Any] = [LeaveLedger.storageKey: try JSONEncoder().encode(days),
            LeaveRequests.storageKey: try JSONEncoder().encode(requests), "dayperkOvertimeDates": try JSONEncoder().encode(overtime)]
        if usesChinaPayroll { preferences["dayperkWorkdayOverrides"] = try JSONEncoder().encode(overrides) }
        else {
            var calendars = regional.manualCalendars; calendars[regional.calendarKey] = overrides
            preferences["dayperkRegionalDateOverrides"] = try JSONEncoder().encode(calendars)
        }
        try UserDataStore.shared.persist(preferences)
        if usesChinaPayroll { dateOverrides = overrides }
        else { regional.updateOverrides(overrides, persist: false) }
        overtimeDates = overtime; leaveDays = days
        refreshPayroll(leaveChangedDays: changed, updateCurrentDay: true)
        objectWillChange.send()
    }
}
