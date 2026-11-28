import Foundation
@testable import DayPerk
import Testing

struct WorkTrackingTests {
    @Test func caffeineOffDuringBufferedHoursKeepsWorkRunning() {
        for time in [date(23, 8, 30), date(23, 10), date(23, 17, 30)] {
            var state = WorkTrackingState()
            state.setCaffeine(true, at: time, plan: plan, calendar: calendar)
            state.setCaffeine(false, at: time.addingTimeInterval(1), plan: plan, calendar: calendar)
            #expect(state.isWorking && !state.caffeineEnabled)
        }
        var state = WorkTrackingState()
        state.setCaffeine(true, at: date(23, 17), plan: plan, calendar: calendar)
        state.setCaffeine(false, at: date(23, 18), plan: plan, calendar: calendar)
        #expect(!state.isWorking)
    }

    @Test func shortPauseRejoinsSessionButLongPauseAndSleepDoNot() {
        let start = date(23, 10)
        for gap in [0.0, 5, 10, 10.01] {
            var state = WorkTrackingState()
            state.setWorking(true, at: start, plan: plan, calendar: calendar)
            state.setWorking(false, at: start.addingTimeInterval(60), plan: plan, calendar: calendar)
            state.setWorking(true, at: start.addingTimeInterval(60 + gap), plan: plan, calendar: calendar)
            state.accrue(until: start.addingTimeInterval(120 + gap), plan: plan, calendar: calendar)
            #expect(abs(state.days[0].seconds - (gap <= 10 ? 120 + gap : 120)) < 0.001)
        }
        var state = WorkTrackingState()
        state.setWorking(true, at: start, plan: plan, calendar: calendar)
        state.suspend(at: start.addingTimeInterval(60), plan: plan, calendar: calendar)
        state.setWorking(true, at: start.addingTimeInterval(65), plan: plan, calendar: calendar)
        #expect(state.days[0].seconds == 60)
    }

    @Test func accidentalShortSessionRestoredWhenBriefPauseIsCancelled() {
        let start = date(23, 10)
        var state = WorkTrackingState()
        state.setWorking(true, at: start, plan: plan, calendar: calendar)
        state.setWorking(false, at: start.addingTimeInterval(4), plan: plan, calendar: calendar)
        #expect(state.days.isEmpty)
        state.setWorking(true, at: start.addingTimeInterval(8), plan: plan, calendar: calendar)
        state.setWorking(false, at: start.addingTimeInterval(20), plan: plan, calendar: calendar)
        #expect(state.days[0].seconds == 20 && state.days[0].earned == 20)
    }

    @Test func caffeineLinkAllowsHalfHourMarginsButStillExcludesBreaksAndDaysOff() {
        var p = plan
        p.breakPeriods = [WorkBreak(startMinute: 12 * 60, endMinute: 14 * 60)]
        #expect(!p.isWithinWorkHours(date(23, 8, 29), calendar: calendar))
        #expect(p.isWithinWorkHours(date(23, 8, 30), calendar: calendar))
        #expect(p.isWithinWorkHours(date(23, 17, 30), calendar: calendar))
        #expect(!p.isWithinWorkHours(date(23, 17, 31), calendar: calendar))
        #expect(!p.isWithinWorkHours(date(23, 12, 30), calendar: calendar))
        #expect(!p.isWithinWorkHours(date(28, 8, 30), calendar: calendar))
        var state = WorkTrackingState()
        state.setCaffeine(true, at: date(23, 8, 30), plan: p, calendar: calendar)
        #expect(state.isWorking)
        p.dateOverrides["2026-11-28"] = true
        #expect(p.isWithinWorkHours(date(28, 8, 30), calendar: calendar))
    }

    @Test func monthlyWorkdaysCountHolidaysMakeupDaysAndIgnoreOvertime() {
        var p = WorkPlan()
        #expect(p.regularWorkdays(year: 2026, month: 11, calendar: calendar) == 21)
        p.dateOverrides = ["2026-11-23": false, "2026-11-24": false, "2026-11-28": true]
        p.overtimeDates = ["2026-11-29": 3]
        #expect(p.regularWorkdays(year: 2026, month: 11, calendar: calendar) == 20)
        p.dayStartMinute = 23 * 60
        #expect(p.regularWorkdays(year: 2026, month: 11, calendar: calendar) == 20)
        #expect(WorkPlan().regularWorkdays(year: 2026, month: 12, calendar: calendar) == 23)
    }

    @Test func paydayClampsFixedDateAndSupportsLeapYearMonthEnd() throws {
        let rule = PaydayRule(usesLastDay: false, day: 31)
        let common = try #require(rule.date(year: 2026, month: 2, plan: plan, calendar: calendar))
        let leap = try #require(PaydayRule().date(year: 2028, month: 2, plan: plan, calendar: calendar))
        #expect(WorkPlan.dayKey(common, calendar: calendar) == "2026-02-28")
        #expect(WorkPlan.dayKey(leap, calendar: calendar) == "2028-02-29")
        let decoded = try JSONDecoder().decode(PaydayRule.self, from: JSONEncoder().encode(rule))
        #expect(decoded == rule)
    }

    @Test func paydayAdvancesAcrossHolidaysAndMonthBoundaryButHonorsMakeupDay() throws {
        let rule = PaydayRule(usesLastDay: false, day: 1, advanceOnRestDay: true)
        var p = WorkPlan(dateOverrides: ["2026-10-30": false], overtimeDates: ["2026-10-31": 2])
        let early = try #require(rule.date(year: 2026, month: 11, plan: p, calendar: calendar))
        #expect(WorkPlan.dayKey(early, calendar: calendar) == "2026-10-29")
        p.dateOverrides["2026-10-31"] = true
        let makeup = try #require(rule.date(year: 2026, month: 11, plan: p, calendar: calendar))
        #expect(WorkPlan.dayKey(makeup, calendar: calendar) == "2026-10-31")
        let unchanged = try #require(PaydayRule(usesLastDay: false, day: 1).date(year: 2026, month: 11, plan: p, calendar: calendar))
        #expect(WorkPlan.dayKey(unchanged, calendar: calendar) == "2026-11-01")
        #expect(rule.date(year: 2026, month: 11, plan: WorkPlan(weekdays: []), calendar: calendar) == nil)
    }

    @Test func leaveDoesNotTurnAScheduledPaydayIntoARestDay() throws {
        let rule = PaydayRule(usesLastDay: true, advanceOnRestDay: true)
        for pay in [LeavePay.paid, .unpaid] {
            var p = WorkPlan()
            var day = LeaveDay(); day.set(.full, pay: pay)
            p.leaveDays["2026-11-30"] = day
            let payday = try #require(rule.date(year: 2026, month: 11, plan: p, calendar: calendar))
            #expect(WorkPlan.dayKey(payday, calendar: calendar) == "2026-11-30")
            p.dateOverrides["2026-11-30"] = false
            let advanced = try #require(rule.date(year: 2026, month: 11, plan: p, calendar: calendar))
            #expect(WorkPlan.dayKey(advanced, calendar: calendar) == "2026-11-27")
        }
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private var plan: WorkPlan {
        WorkPlan(startMinute: 9 * 60, endMinute: 17 * 60, ratePerSecond: 1, overtimeMultiplier: 1, linkCaffeine: true, dayStartMinute: 0, automation: .enabledForTesting)
    }

    @Test func weekdayCaffeineEdgesLinkButManualPauseWinsUntilAnotherEdge() {
        var state = WorkTrackingState()
        state.setCaffeine(true, at: date(23, 10), plan: plan, calendar: calendar)
        #expect(state.isWorking && state.caffeineEnabled)
        state.setWorking(false, at: date(23, 10, 10), plan: plan, calendar: calendar)
        state.setCaffeine(true, at: date(23, 10, 20), plan: plan, calendar: calendar)
        state.accrue(until: date(23, 11), plan: plan, calendar: calendar)
        #expect(!state.isWorking && state.caffeineEnabled)
        #expect(state.days[0].seconds == 600)
        state.setCaffeine(false, at: date(23, 11), plan: plan, calendar: calendar)
        #expect(!state.isWorking && !state.caffeineEnabled)
        state.setCaffeine(true, at: date(23, 11), plan: plan, calendar: calendar)
        #expect(state.isWorking)
    }

    @Test func weekendSwitchesAreIndependentAndDateOverridesApply() {
        var state = WorkTrackingState()
        state.setCaffeine(true, at: date(28, 10), plan: plan, calendar: calendar)
        #expect(!state.isWorking)
        state.setWorking(true, at: date(28, 10), plan: plan, calendar: calendar)
        state.setCaffeine(false, at: date(28, 11), plan: plan, calendar: calendar)
        #expect(state.isWorking)
        var p = plan
        p.dateOverrides["2026-11-28"] = true
        state.setWorking(false, at: date(28, 11), plan: p, calendar: calendar)
        state.setCaffeine(true, at: date(28, 12), plan: p, calendar: calendar)
        #expect(state.isWorking)
        p.dateOverrides["2026-11-23"] = false
        #expect(!p.isWorkday(date(23, 12), calendar: calendar))
    }

    @Test func scheduleDoesNotStartBillingAndPausesDoNotEarn() {
        var state = WorkTrackingState()
        state.accrue(until: date(23, 12), plan: plan, calendar: calendar)
        #expect(state.days.isEmpty)
        state.setWorking(true, at: date(23, 12), plan: plan, calendar: calendar)
        state.setWorking(false, at: date(23, 13), plan: plan, calendar: calendar)
        state.accrue(until: date(23, 16), plan: plan, calendar: calendar)
        #expect(state.days[0].seconds == 3600 && state.days[0].earned == 3600)
        state.setWorking(true, at: date(23, 16), plan: plan, calendar: calendar)
        state.setWorking(false, at: date(23, 16, 30), plan: plan, calendar: calendar)
        #expect(state.days[0].seconds == 5400)
    }

    @Test func passiveExtraTimeHasNoOvertimePayAndMidnightSplitsDays() {
        var state = WorkTrackingState()
        var p = plan; p.overtimeMultiplier = 1.5
        state.setWorking(true, at: date(23, 16, 59), plan: p, calendar: calendar)
        state.setWorking(false, at: date(23, 17, 1), plan: p, calendar: calendar)
        #expect(state.days[0].overtimeSeconds == 0 && state.days[0].earned == 120)
        state.setWorking(true, at: date(23, 23, 59), plan: plan, calendar: calendar)
        state.setWorking(false, at: date(24, 0, 1), plan: plan, calendar: calendar)
        #expect(state.days.count == 2)
        #expect(state.days[0].seconds == 180 && state.days[1].seconds == 60)
    }

    @Test func sleepAndRelaunchCannotResumeOrBackfillBilling() throws {
        var state = WorkTrackingState()
        state.setCaffeine(true, at: date(23, 10), plan: plan, calendar: calendar)
        state.suspend(at: date(23, 11), plan: plan, calendar: calendar)
        #expect(!state.isWorking && !state.caffeineEnabled)
        state.accrue(until: date(24, 10), plan: plan, calendar: calendar)
        #expect(state.days.count == 1 && state.days[0].seconds == 3600)
        state.setCaffeine(true, at: date(24, 10), plan: plan, calendar: calendar)
        state.accrue(until: date(24, 10, 1), plan: plan, calendar: calendar)
        let saved = try JSONEncoder().encode(state)
        var loaded = try JSONDecoder().decode(WorkTrackingState.self, from: saved)
        loaded.recoverAfterRelaunch()
        loaded.accrue(until: date(25, 10), plan: plan, calendar: calendar)
        #expect(!loaded.isWorking && !loaded.caffeineEnabled)
        #expect(loaded.days[1].seconds == 60)
    }

    @Test func rateChangesRevalueHoursAndClockRollbackCannotSubtract() {
        var state = WorkTrackingState()
        state.setWorking(true, at: date(23, 10), plan: plan, calendar: calendar)
        state.accrue(until: date(23, 11), plan: plan, calendar: calendar)
        var newPlan = plan; newPlan.ratePerSecond = 2
        state.accrue(until: date(23, 12), plan: newPlan, calendar: calendar)
        #expect(state.days[0].earned == 14400)
        state.accrue(until: date(23, 10), plan: newPlan, calendar: calendar)
        #expect(state.days[0].earned == 14400)
    }

    @Test func menuBarShowsOnlyIntegerDigitsAndPrivacyMask() {
        #expect(StatusBarPresentation.amount(1234.99, privateMode: false) == "1235")
        #expect(StatusBarPresentation.amount(12.345, privateMode: false, decimalPlaces: 1) == "12.3")
        #expect(StatusBarPresentation.amount(12.346, privateMode: false, decimalPlaces: 2) == "12.35")
        #expect(StatusBarPresentation.amount(12.346, privateMode: false, decimalPlaces: 9) == "12.35")
        #expect(StatusBarPresentation.amount(0.1, privateMode: false) == "0")
        #expect(StatusBarPresentation.amount(.nan, privateMode: false) == "0")
        #expect(StatusBarPresentation.amount(1234, privateMode: true).isEmpty)
    }

    @Test func nativeSleepAssertionCanBeEnabledAndReleasedWithIsolatedStorage() throws {
        let suite = "DayPerk-work-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        let controller = WorkTrackingController(defaults: defaults, calendar: calendar, observeSystem: false)
        defer {
            controller.shutdown()
            defaults.removePersistentDomain(forName: suite)
        }
        controller.updatePlan(plan)
        controller.setCaffeine(true)
        #expect(controller.errorMessage == nil)
        #expect(controller.state.caffeineEnabled)
        controller.setCaffeine(false)
        #expect(!controller.state.caffeineEnabled)
    }

    @Test func shortSessionsRefundTimeOvertimeAndMoneyButKeepEarlierWork() {
        let start = date(23, 20)
        let baseline = WorkDayTotal(id: "2026-11-23", seconds: 100, overtimeSeconds: 20, earned: 100)
        for seconds in [0.0, 2, 9.99, 10] {
            var state = WorkTrackingState(days: [baseline])
            state.setWorking(true, at: start, plan: plan, calendar: calendar)
            state.accrue(until: start.addingTimeInterval(seconds / 2), plan: plan, calendar: calendar)
            state.setWorking(false, at: start.addingTimeInterval(seconds), plan: plan, calendar: calendar)
            #expect(state.days == [baseline])
        }
        var valid = WorkTrackingState()
        valid.setWorking(true, at: start, plan: plan, calendar: calendar)
        valid.setWorking(false, at: start.addingTimeInterval(10.01), plan: plan, calendar: calendar)
        #expect(abs(valid.days[0].seconds - 10.01) < 0.001)
    }

    @Test func caffeineQuickOffAndSleepRefundAcrossMidnight() {
        let start = date(23, 23, 59).addingTimeInterval(57)
        var state = WorkTrackingState()
        state.setCaffeine(true, at: start, plan: plan, calendar: calendar)
        state.setWorking(true, at: start, plan: plan, calendar: calendar)
        state.accrue(until: start.addingTimeInterval(5), plan: plan, calendar: calendar)
        #expect(state.days.count == 2)
        state.setCaffeine(false, at: start.addingTimeInterval(8), plan: plan, calendar: calendar)
        #expect(state.days.isEmpty)
        state.setCaffeine(true, at: start, plan: plan, calendar: calendar)
        state.setWorking(true, at: start, plan: plan, calendar: calendar)
        state.suspend(at: start.addingTimeInterval(4), plan: plan, calendar: calendar)
        #expect(state.days.isEmpty && !state.isWorking)
    }

    @Test func repricingIsReversibleAndShortRefundPreservesRepricedBaseline() {
        let start = date(23, 10)
        var state = WorkTrackingState(days: [WorkDayTotal(id: "2026-11-23", seconds: 3600, overtimeSeconds: 600, earned: 3600)])
        state.setWorking(true, at: start, plan: plan, calendar: calendar)
        state.accrue(until: start.addingTimeInterval(5), plan: plan, calendar: calendar)
        var updated = plan; updated.ratePerSecond = 2; updated.overtimeMultiplier = 1.5
        state.reprice(using: updated, at: start.addingTimeInterval(5), calendar: calendar)
        state.setWorking(false, at: start.addingTimeInterval(8), plan: updated, calendar: calendar)
        #expect(state.days[0].seconds == 3600 && state.days[0].earned == 7200)
        state.reprice(using: plan, at: start.addingTimeInterval(8), calendar: calendar)
        #expect(state.days[0].earned == 3600)
    }

    @Test func correspondingMonthRatesCanExceedMonthlySalaryWithoutClipping() {
        var p = plan; p.dayRates = ["2026-10-23": 2, "2026-11-23": 3]
        var state = WorkTrackingState(days: [
            WorkDayTotal(id: "2026-10-23", seconds: 1000, overtimeSeconds: 0),
            WorkDayTotal(id: "2026-11-23", seconds: 10000, overtimeSeconds: 1000),
        ])
        state.reprice(using: p, at: date(23, 12), calendar: calendar, refreshHistory: true)
        #expect(state.days[0].earned == 2000 && state.days[1].earned == 30000)
    }

    @Test func todayCorrectionRecalculatesAmountAndPersistsDuration() throws {
        let suite = "app.dayperk.tests.correction-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        let controller = WorkTrackingController(defaults: defaults, calendar: calendar, observeSystem: false)
        defer { controller.shutdown(); defaults.removePersistentDomain(forName: suite) }
        controller.updatePlan(plan)
        try controller.correctToday(seconds: 3600, at: date(23, 12))
        #expect(controller.state.days[0].manualAdjustment == nil && controller.state.days[0].earned == 3600)
        var changed = plan; changed.ratePerSecond = 2
        controller.updatePlan(changed, at: date(23, 12))
        #expect(controller.state.days[0].earned == 7200)
        let saved = try #require(defaults.data(forKey: "manualWorkTrackingV1"))
        #expect(try JSONDecoder().decode(WorkTrackingState.self, from: saved).days[0].earned == 7200)
        #expect(throws: DayPerkInputError.self) { try controller.correctToday(seconds: 86401) }
        #expect(throws: DayPerkInputError.self) { try controller.correctToday(seconds: .nan) }
        try controller.correctToday(seconds: 0, at: date(23, 12))
        #expect(controller.state.days[0].earned == 0 && controller.state.days[0].seconds == 0)
    }

    @Test func correctionDurationInputHasExplicitHoursMinutesSeconds() throws {
        #expect(try WorkDurationInput.parse("08:30:00") == 30600)
        #expect(try WorkDurationInput.parse("24:00:00") == 86400)
        #expect(WorkDurationInput.format(2) == "00:00:02")
        for invalid in ["1:30", "00:60:00", "24:00:01", "-1:00:00", "NaN", ""] {
            #expect(throws: DayPerkInputError.self) { try WorkDurationInput.parse(invalid) }
        }
    }

    @Test func caffeineStartsWorkOnlyInsideConfiguredWeekdayHours() {
        for hour in [8, 18, 20] {
            var state = WorkTrackingState()
            state.setCaffeine(true, at: date(23, hour), plan: plan, calendar: calendar)
            #expect(state.caffeineEnabled && !state.isWorking)
        }
        var state = WorkTrackingState()
        state.setCaffeine(true, at: date(23, 9), plan: plan, calendar: calendar)
        #expect(state.isWorking)
        state.setCaffeine(false, at: date(23, 18), plan: plan, calendar: calendar)
        #expect(!state.isWorking)
        state.setWorking(true, at: date(23, 20), plan: plan, calendar: calendar)
        #expect(state.isWorking)
    }

    @Test func specifiedBreaksDisableCaffeineAutoStartAndSeparateOvertime() {
        var p = plan; p.breakPeriods = [WorkBreak(startMinute: 12 * 60, endMinute: 14 * 60)]
        var state = WorkTrackingState()
        state.setCaffeine(true, at: date(23, 12, 30), plan: p, calendar: calendar)
        #expect(state.caffeineEnabled && !state.isWorking)
        state.setWorking(true, at: date(23, 11, 30), plan: p, calendar: calendar)
        state.setWorking(false, at: date(23, 14, 30), plan: p, calendar: calendar)
        #expect(state.days[0].seconds == 10800 && state.days[0].overtimeSeconds == 0)
        p.linkCaffeine = false
        var independent = WorkTrackingState()
        independent.setCaffeine(true, at: date(23, 10), plan: p, calendar: calendar)
        #expect(!independent.isWorking)
    }

    @Test func overtimeDateMultiplierIsFreeFormAndWeekendCanLink() {
        #expect(WorkPlan().overtimeMultiplier == 2)
        var p = plan; p.overtimeDates["2026-11-28"] = 1.75
        #expect(p.isWithinWorkHours(date(28, 10), calendar: calendar))
        let day = WorkDayTotal(id: "2026-11-28", seconds: 1000, overtimeSeconds: 1000)
        #expect(p.amount(for: day) == 1000)
        #expect(p.registeredOvertimeGross(for: day, rate: 1) == 1750)
    }

    @Test func passiveTenHourDayOnlyChangesTimeValueAndDailyMultipliersAreIndependent() {
        var p = plan
        p.ratePerSecond = 1000 / (8 * 3600)
        let passive = WorkDayTotal(id: "2026-11-23", seconds: 10 * 3600, overtimeSeconds: 7200)
        #expect(abs(p.amount(for: passive) - 1250) < 0.001)
        #expect(p.registeredOvertimeGross(for: passive, rate: p.ratePerSecond) == 0)
        p.overtimeDates = ["2026-11-23": 2, "2026-11-24": 3]
        let first = WorkDayTotal(id: "2026-11-23", seconds: 3600)
        let second = WorkDayTotal(id: "2026-11-24", seconds: 3600)
        #expect(p.registeredOvertimeGross(for: first, rate: 1) == 7200)
        #expect(p.registeredOvertimeGross(for: second, rate: 1) == 10800)
        #expect(p.amount(for: first) == p.amount(for: second))
        p.overtimeDates.removeValue(forKey: first.id)
        #expect(p.registeredOvertimeGross(for: first, rate: 1) == 0)
        #expect(p.registeredOvertimeGross(for: second, rate: 1) == 10800)
    }

    @Test func businessDayDefaultsToFourAndCivilDateKeyDoesNotShift() {
        let p = WorkPlan()
        #expect(p.dayStartMinute == 240)
        #expect(WorkPlan.dayKey(date(24, 3), calendar: calendar) == "2026-11-24")
        #expect(p.businessDayKey(date(24, 3), calendar: calendar) == "2026-11-23")
        #expect(p.businessDayKey(date(24, 4), calendar: calendar) == "2026-11-24")
        #expect(p.businessDayStart(for: date(24, 3), calendar: calendar) == date(23, 4))
        #expect(!p.isWorkday(date(23, 3), calendar: calendar))
        #expect(p.isWorkday(date(24, 3), calendar: calendar))
        var early = p; early.startMinute = 60; early.endMinute = 180
        #expect(early.isWithinWorkHours(date(24, 2), calendar: calendar))
        #expect(!early.isWithinWorkHours(date(23, 2), calendar: calendar))
    }

    @Test func accrualSplitsAtConfiguredBusinessBoundaryAndShortRefundStillWorks() {
        var p = plan; p.dayStartMinute = 240
        var state = WorkTrackingState()
        state.setWorking(true, at: date(24, 3, 59), plan: p, calendar: calendar)
        state.setWorking(false, at: date(24, 4, 1), plan: p, calendar: calendar)
        #expect(state.days.map(\.id) == ["2026-11-23", "2026-11-24"])
        #expect(state.days.map(\.seconds) == [60, 60])
        #expect(state.days.map(\.earned) == [60, 60])
        let baseline = state.days
        let start = date(25, 3, 59).addingTimeInterval(57)
        state.setWorking(true, at: start, plan: p, calendar: calendar)
        state.setWorking(false, at: start.addingTimeInterval(8), plan: p, calendar: calendar)
        #expect(state.days == baseline)
    }

    @Test func configurationChangesOnlyRepriceCurrentBusinessDayAndHistoryRefreshIsExplicit() {
        var p = plan; p.dayStartMinute = 240
        p.overtimeDates["2026-11-23"] = 2
        p.expectedIncomes = ["2026-11-23": 120, "2026-11-24": 130]
        p.grossRatePerSecond = 3
        var state = WorkTrackingState(days: [
            WorkDayTotal(id: "2026-11-23", seconds: 100, overtimeSeconds: 100, earned: 150),
            WorkDayTotal(id: "2026-11-24", seconds: 100, earned: 100),
        ])
        state.reprice(using: p, at: date(24, 12), calendar: calendar)
        #expect(state.days[0].earned == 150 && state.days[0].overtimeSeconds == 100)
        #expect(state.days[0].ratePerSecond == 1.5 && state.days[0].expectedIncome == 120)
        var changed = p; changed.ratePerSecond = 4; changed.grossRatePerSecond = 8
        changed.overtimeDates = ["2026-11-24": 3]
        changed.expectedIncomes = ["2026-11-23": 900, "2026-11-24": 800]
        state.reprice(using: changed, at: date(24, 12), calendar: calendar)
        #expect(state.days[0].earned == 150 && state.days[0].overtimeSeconds == 100)
        #expect(state.days[0].expectedIncome == 120 && state.days[0].overtimeMultiplier == 2)
        #expect(changed.registeredOvertimeGross(for: state.days[0], rate: 8) == 600)
        #expect(state.days[1].earned == 400 && state.days[1].expectedIncome == 800)
        state.reprice(using: changed, at: date(24, 12), calendar: calendar, refreshHistory: true)
        #expect(state.days[0].earned == 400 && state.days[0].overtimeSeconds == 0)
        #expect(state.days[0].expectedIncome == 900 && state.days[0].grossRatePerSecond == 8)
        #expect(changed.registeredOvertimeGross(for: state.days[0], rate: 8) == 0)
    }

    @Test func savingMatchingRuleImmediatelyUpdatesSettledTodayWithoutChangingHistory() {
        let now = date(27, 18)
        var p = plan; p.referenceSeconds = 8 * 3600
        p.expectedIncomes = ["2026-11-26": 800, "2026-11-27": 800]
        var state = WorkTrackingState(days: [
            WorkDayTotal(id: "2026-11-26", seconds: 3600, earned: 100, ratePerSecond: 1,
                expectedIncome: 800, referenceSeconds: 8 * 3600, currencyCode: "CNY", settledAt: date(26, 18)),
            WorkDayTotal(id: "2026-11-27", seconds: 3600, earned: 100, ratePerSecond: 1,
                expectedIncome: 800, referenceSeconds: 8 * 3600, currencyCode: "CNY", settledAt: now),
        ])
        p.rhythm.scheduleRules = [WorkScheduleRule(weekdays: [6], schedule: DayWorkSchedule(startMinute: 540, endMinute: 1020, breakMinutes: 60))]
        p.ratePerSecond = 2; p.expectedIncomes["2026-11-27"] = 700
        state.reprice(using: p, at: now, calendar: calendar)
        #expect(state.days[1].referenceSeconds == 8 * 3600 && state.days[1].earned == 100)
        let history = state.days[0]
        state.reprice(using: p, at: now, calendar: calendar, updateCurrentDay: true)
        #expect(state.days[1].referenceSeconds == 7 * 3600 && state.days[1].expectedIncome == 700)
        #expect(state.days[1].seconds == 3600 && state.days[1].earned == 7200 && state.days[1].settledAt == now)
        #expect(state.days[0] == history)
    }

    @Test func oldDayJSONDecodesAndMissingSnapshotsNeverRevalueHistory() throws {
        let json = #"{"id":"2026-11-22","seconds":100,"overtimeSeconds":50,"earned":123}"#
        let old = try JSONDecoder().decode(WorkDayTotal.self, from: Data(json.utf8))
        #expect(old.ratePerSecond == nil && old.expectedIncome == nil && old.overtimeMultiplier == nil && old.grossRatePerSecond == nil)
        var state = WorkTrackingState(days: [old])
        var p = plan; p.ratePerSecond = 20; p.defaultDailyExpectedIncome = 200
        state.reprice(using: p, at: date(23, 12), calendar: calendar)
        #expect(state.days[0].earned == 123 && state.days[0].overtimeSeconds == 50)
        #expect(state.days[0].ratePerSecond == 1.23 && state.days[0].expectedIncome == 0)
        let saved = try JSONEncoder().encode(state.days[0])
        #expect(try JSONDecoder().decode(WorkDayTotal.self, from: saved) == state.days[0])
        #expect(p.expectedIncome(for: "2026-11-23", calendar: calendar) == 200)
    }

    @Test func correctionBeforeDayStartTargetsPreviousBusinessDay() throws {
        let suite = "app.dayperk.tests.business-correction-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        let controller = WorkTrackingController(defaults: defaults, calendar: calendar, observeSystem: false)
        defer { controller.shutdown(); defaults.removePersistentDomain(forName: suite) }
        var p = plan; p.dayStartMinute = 240
        controller.updatePlan(p, at: date(24, 3))
        try controller.correctToday(seconds: 100, at: date(24, 3))
        #expect(controller.state.days[0].id == "2026-11-23")
        var changed = p; changed.ratePerSecond = 2
        controller.updatePlan(changed, at: date(24, 4))
        #expect(controller.state.days[0].earned == 100)
        controller.refreshHistory(at: date(24, 4))
        #expect(controller.state.days[0].earned == 200)
    }
}
