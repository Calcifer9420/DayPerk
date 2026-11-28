import Foundation

extension DayPerkModel {
    private func regionalResult(bonus: Bool, extraMonthly: Double = 0, unpaidLeave: Double = 0) throws -> RegionalPayEstimate {
        var input = regional.input
        if !bonus { input.annualBonus = 0 }
        if unpaidLeave > 0 {
            let periods = input.frequency.periods(hoursPerWeek: input.hoursPerWeek)
            if periods > 0 { input.amount = max(0, input.amount - unpaidLeave * 12 / periods) }
        }
        // 加班只增加当年应税工资，不重算已声明的固定缴费基数。
        let policy = regional.selectedPolicy
        let baseline = try InternationalPayrollCalculator().estimate(input: input, policy: policy)
        guard extraMonthly > 0 else { return baseline }
        let extra = extraMonthly * 12
        let periods = input.frequency.periods(hoursPerWeek: input.hoursPerWeek)
        guard periods > 0 else { return baseline }
        input.amount += extra / periods
        let increased = try InternationalPayrollCalculator().estimate(input: input, policy: policy)
        return RegionalPayEstimate(annualGross: baseline.annualGross + extra,
            annualIncomeTax: increased.annualIncomeTax, annualRegionalTax: increased.annualRegionalTax,
            contributions: baseline.contributions)
    }

    func regionalBasis(extraMonthly: Double = 0) -> Double {
        guard let result = try? regionalResult(bonus: payroll.includeAnnualBonus, extraMonthly: extraMonthly) else { return 0 }
        return result.monthlyTimeValueBasis(deduct: payroll.isEnabled, benefits: withdrawableBenefits)
    }

    func regionalExpectedIncome(for day: WorkDayTotal) -> Double {
        let c = workCalendar
        let parts = day.id.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = c.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) else { return 0 }
        let days = workdays(year: parts[0], month: parts[1])
        let baseline = regionalBasis()
        // 登记加班日同样有基础工时预算；倍率影响加班报酬，不放大可白赚的时间。
        let hasReferenceBudget = tracking.plan.isScheduledWorkday(date, calendar: c) || overtimeDates[day.id] != nil
        let value = hasReferenceBudget && days > 0 ? baseline / Double(days) * (activeLeave(for: day.id)?.payableFraction ?? 1) : 0
        return PayrollCalculator.money(value)
    }

    func refreshRegionalPayroll(refreshHistory: Bool, leaveChangedDays: Set<String> = [], updateCurrentDay: Bool = false) {
        do {
            let calendar = workCalendar
            let business = tracking.plan.businessDayStart(for: Date(), calendar: calendar)
            let year = calendar.component(.year, from: business), month = calendar.component(.month, from: business)
            let policy = regional.selectedPolicy
            // 超出政策适用年份时保留时长，金额归零并明确提示，避免沿用过期税率。
            let civilKey = WorkPlan.dayKey(business, calendar: calendar)
            guard policy.country == .custom || (civilKey >= policy.validFrom && civilKey <= policy.validThrough) else {
                throw DayPerkInputError(message: L10n.text("ui.the_selected_policy_does_not_cover.be4d7242"))
            }
            let reference = Double(max(0, configuration.workMinutesPerDay) * 60)
            var plan = tracking.plan
            plan.weekdays = Set(schedule.workdays.map { $0.calendarWeekday })
            plan.rhythm = rhythm; plan.leaveDays = leaveDays
            plan.dateOverrides = effectiveOverrides
            plan.startMinute = calendar.component(.hour, from: schedule.startTime) * 60 + calendar.component(.minute, from: schedule.startTime)
            plan.endMinute = calendar.component(.hour, from: schedule.endTime) * 60 + calendar.component(.minute, from: schedule.endTime)
            plan.referenceSeconds = reference; plan.dayStartMinute = dayStartMinute
            plan.linkCaffeine = linkCaffeine; plan.automation = automation
            plan.breakPeriods = breakMode == .timeRanges ? breakPeriods : []
            plan.overtimeDates = overtimeDates; plan.overtimeMultiplier = overtimeMultiplier
            plan.currencyCode = policy.currency
            let divisor = policy.parameters["restDaySalaryDivisor"] ?? 0
            plan.registeredDailyGross = divisor > 0 ? regional.input.annualBase / 12 / divisor : nil
            plan.ratePerSecond = dailyTimeValueRate(monthlyBasis: regionalBasis(), for: civilKey)
            plan.grossRatePerSecond = dailyTimeValueRate(monthlyBasis: regional.input.annualBase / 12, for: civilKey)
            plan.defaultDailyExpectedIncome = regionalBasis() / Double(max(1, workdays(year: year, month: month)))
            plan.dayRates = [:]; plan.dayGrossRates = [:]; plan.expectedIncomes = [:]
            for day in reportRecords {
                let components = day.id.split(separator: "-").compactMap { Int($0) }
                guard components.count == 3 else { continue }
                let dayReference = Double(max(0, configuration.referenceMinutes(for: day.id)) * 60)
                plan.dayRates[day.id] = dailyTimeValueRate(monthlyBasis: regionalBasis(), for: day.id)
                plan.dayGrossRates[day.id] = divisor > 0 && dayReference > 0 ? regional.input.annualBase / 12 / divisor / dayReference
                    : dailyTimeValueRate(monthlyBasis: regional.input.annualBase / 12, for: day.id)
                plan.expectedIncomes[day.id] = !refreshHistory && !leaveChangedDays.contains(day.id) && day.id < civilKey ? day.expectedIncome : nil
            }
            tracking.updatePlan(plan)
            for day in reportRecords { plan.expectedIncomes[day.id] = !refreshHistory && !leaveChangedDays.contains(day.id) && day.id < civilKey ? day.expectedIncome : regionalExpectedIncome(for: day) }
            let extra = reportRecords.filter { $0.id.hasPrefix(String(civilKey.prefix(7))) }.reduce(0) { $0 + plan.registeredOvertimeGross(for: $1, rate: plan.grossRatePerSecond) }
            let deduction = unpaidLeaveDeductions(year: year, monthlyGross: regional.input.annualBase / 12)[month] ?? 0
            let result = try regionalResult(bonus: false, extraMonthly: extra, unpaidLeave: deduction)
            regionalEstimate = result
            breakdown = PayrollBreakdown(grossMonthlyIncome: result.annualGross / 12, pensionInsurance: 0, medicalInsurance: 0,
                unemploymentInsurance: 0, employeeSocialInsurance: result.employeeContributions / 12,
                individualIncomeTax: (result.annualIncomeTax + result.annualRegionalTax) / 12,
                netMonthlyIncome: result.cashNet / 12, housingFund: 0, overtimeGross: extra)
            tracking.updatePlan(plan, leaveChangedDays: leaveChangedDays, updateCurrentDay: updateCurrentDay)
            if refreshHistory { tracking.refreshHistory() }
            actionError = nil
        } catch {
            actionError = error.localizedDescription; regionalEstimate = nil; breakdown = .zero
            var plan = tracking.plan; plan.ratePerSecond = 0; plan.defaultDailyExpectedIncome = 0
            plan.dayRates = [:]; plan.expectedIncomes = [:]; plan.currencyCode = activeCurrencyCode
            tracking.updatePlan(plan)
        }
        objectWillChange.send()
    }
}
