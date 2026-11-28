import Foundation
import Testing
@testable import DayPerk

struct LeaveTests {
    @Test func compensatoryTimeOffReusesPaidLeaveAndManualMakeupWorkdays() throws {
        var schedule = WorkPlan(dateOverrides: ["2026-11-28": true], defaultDailyExpectedIncome: 800)
        let request = LeaveRequest(base: LeaveRange(start: date(27), end: date(30), kind: .compensatory))
        let days = try LeaveRequests.materialize([request], plan: schedule, calendar: calendar)
        #expect(Set(days.keys) == ["2026-11-27", "2026-11-28", "2026-11-30"])
        #expect(days.values.allSatisfy { $0.isCompensatory && $0.paidFraction == 1 && $0.unpaidFraction == 0 })
        schedule.leaveDays = days
        #expect(schedule.isScheduledWorkday(date(28), calendar: calendar))
        #expect(schedule.overtimeDates["2026-11-28"] == nil)
        #expect(schedule.expectedIncome(for: "2026-11-28", calendar: calendar) == 800)
        #expect(schedule.referenceSeconds(for: "2026-11-28") == 0)
        #expect(try LeaveRequests.summary(request, plan: schedule, calendar: calendar).paidDays == 3)
    }

    @Test func halfDayCompensatoryAndOtherLeaveKeepTheirKindsWhenEditedAndMigrated() throws {
        let request = LeaveRequest(base: LeaveRange(start: date(23), end: date(23)), segments: [
            LeaveRange(start: date(23), end: date(23), portion: .morning, kind: .compensatory),
            LeaveRange(start: date(23), end: date(23), portion: .afternoon, pay: .unpaid)])
        let days = try LeaveRequests.materialize([request], plan: plan, calendar: calendar)
        let day = try #require(days["2026-11-23"])
        #expect(day.morningKind == .compensatory && day.afternoonKind == nil && !day.isCompensatory)
        #expect(day.paidFraction == 0.5 && day.unpaidFraction == 0.5)
        #expect(try LeaveRequests.materialize(LeaveRequests.migrate(days, plan: plan, calendar: calendar), plan: plan, calendar: calendar) == days)
        #expect(try JSONDecoder().decode(LeaveRequest.self, from: JSONEncoder().encode(request)) == request)
        var draft = LeaveRequestDraft(); draft.base = request.segments[0]
        draft.beginAdjustment()
        #expect(draft.selection.kind == .compensatory && draft.selection.pay == .paid)
        draft.beginSelection()
        #expect(draft.base.kind == nil && draft.base.pay == .paid)
    }

    @Test func olderLeaveDataDefaultsToOtherTimeOffWithoutChangingPay() throws {
        let old = Data(#"{"morning":"paid","afternoon":"paid","boundaryMinute":720}"#.utf8)
        let day = try JSONDecoder().decode(LeaveDay.self, from: old)
        #expect(day.morningKind == nil && day.afternoonKind == nil && !day.isCompensatory)
        #expect(day.payableFraction == 1 && day.paidFraction == 1)
        #expect(throws: DayPerkInputError.self) { try LeaveLedger.validate(["2026-11-23": LeaveDay(morning: .paid, afternoonKind: .compensatory)]) }
    }
    @Test func officialMainlandHolidayIsExcludedEvenWithoutManualOverrides() throws {
        let holidays = ChinaHolidayCalendar.merging(ChinaHolidayCalendar.bundledPlans(), into: [:], imported: [:]).overrides
        #expect(holidays["2026-10-01"] == false)
        var schedule = plan; schedule.dateOverrides = holidays
        let request = LeaveRequest(base: LeaveRange(start: date(1, month: 10), end: date(9, month: 10)))
        let days = try LeaveRequests.materialize([request], plan: schedule, calendar: calendar)
        for (key, working) in holidays where !working { #expect(days[key] == nil) }
        #expect(days["2026-10-08"]?.paidFraction == 1)
    }
    @Test func cardTotalsExcludeWeekendsHolidaysAndCustomRestAcrossWeeksAndMonths() throws {
        var schedule = plan
        schedule.dateOverrides = ["2026-11-24": false, "2026-11-26": false, "2026-11-28": true]
        let request = LeaveRequest(base: LeaveRange(start: date(23), end: date(4, month: 12)), segments: [
            LeaveRange(start: date(30), end: date(2, month: 12), portion: .morning, pay: .unpaid),
            LeaveRange(start: date(29), end: date(29), pay: .unpaid)])
        let days = try LeaveRequests.materialize([request], plan: schedule, calendar: calendar)
        #expect(days["2026-11-24"] == nil && days["2026-11-26"] == nil && days["2026-11-29"] == nil)
        #expect(days["2026-11-28"]?.paidFraction == 1)
        let total = try LeaveRequests.summary(request, plan: schedule, calendar: calendar)
        #expect(total.paidDays == 6 && total.unpaidDays == 1.5)
        let restOnly = LeaveRequest(base: LeaveRange(start: date(21), end: date(22)))
        #expect(try LeaveRequests.materialize([restOnly], plan: schedule, calendar: calendar).isEmpty)
        #expect(try LeaveRequests.summary(restOnly, plan: schedule, calendar: calendar).paidDays == 0)
    }
    @Test func addingSegmentsConfirmsThePeriodAndPreviousSegmentBeforeAdvancing() throws {
        var draft = LeaveRequestDraft(); draft.beginSelection()
        draft.base = LeaveRange(start: date(2), end: date(1, month: 12))
        var saved: LeaveRequest?
        try draft.confirm(addSegment: true) { saved = $0 }
        #expect(saved?.base == draft.base && saved?.segments.isEmpty == true)
        #expect(draft.confirmedBase == draft.base && draft.changes.count == 1)
        draft.selection.start = date(9); draft.selection.end = date(13)
        draft.selection.portion = .morning; draft.selection.pay = .unpaid
        let first = draft.selection
        try draft.confirm(addSegment: true) { saved = $0 }
        #expect(saved?.segments == [first])
        #expect(draft.changes.count == 2 && draft.changes[0] == first)
        #expect(draft.selectedSegmentID == draft.changes[1].id)
        #expect(draft.base.start == date(2) && draft.base.end == date(1, month: 12))
        #expect(draft.selectionBounds == date(2) ... date(1, month: 12))
    }

    @Test func deletingAChildRestoresBaseAndDeletingTheCardRemovesOnlyThatRequest() throws {
        let base = LeaveRange(start: date(2), end: date(1, month: 12))
        let segment = LeaveRange(start: date(9), end: date(13), portion: .morning, pay: .unpaid)
        var request = LeaveRequest(base: base, segments: [segment])
        let other = LeaveRequest(base: LeaveRange(start: date(7, month: 12), end: date(8, month: 12)))
        let adjusted = try LeaveRequests.materialize([request, other], plan: plan, calendar: calendar)
        #expect(adjusted["2026-11-09"]?.unpaidFraction == 0.5)
        request.segments.removeAll()
        let restored = try LeaveRequests.materialize([request, other], plan: plan, calendar: calendar)
        #expect(restored["2026-11-09"]?.paidFraction == 1)
        let removed = try LeaveRequests.materialize([other], plan: plan, calendar: calendar)
        #expect(removed["2026-11-09"] == nil && removed["2026-12-07"]?.paidFraction == 1)
        request.segments = [LeaveRange(start: date(30, month: 10), end: date(3))]
        #expect(throws: DayPerkInputError.self) { try LeaveRequests.materialize([request], plan: plan, calendar: calendar) }
    }

    @Test func failedSegmentConfirmationDoesNotAdvanceOrDiscardTheDraft() throws {
        var draft = LeaveRequestDraft(); draft.base = LeaveRange(start: date(2), end: date(10))
        #expect(throws: DayPerkInputError.self) {
            try draft.confirm(addSegment: true) { _ in throw DayPerkInputError(message: "invalid") }
        }
        #expect(draft.changes.isEmpty && draft.confirmedBase == nil)
        let original = ["2026-11-23": LeaveDay(morning: .unpaid, afternoon: .paid)]
        let migrated = LeaveRequests.migrate(original, plan: plan, calendar: calendar)
        #expect(try LeaveRequests.materialize(migrated, plan: plan, calendar: calendar) == original.mapValues { day in
            var result = day; result.boundaryMinute = 720; return result
        })
    }
    @Test func anUntouchedNewSegmentDoesNotOverwriteTheConfirmedPreviousSegment() throws {
        var draft = LeaveRequestDraft(); draft.base = LeaveRange(start: date(2), end: date(10))
        try draft.confirm(addSegment: true) { _ in }
        draft.selection.portion = .morning; draft.selection.pay = .unpaid
        let previous = draft.selection
        try draft.confirm(addSegment: true) { _ in }
        var saved: LeaveRequest?
        try draft.confirm(finish: true) { saved = $0 }
        #expect(saved?.segments == [previous])
        #expect(draft.changes == [previous] && !draft.isSelecting)
    }
    @Test func backupValidatesDateOnlyRangesInTheirWorkTimeZone() throws {
        var pacific = calendar; pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let start = pacific.date(from: DateComponents(year: 2026, month: 11, day: 2))!
        let end = pacific.date(from: DateComponents(year: 2026, month: 11, day: 10))!
        let request = LeaveRequest(base: LeaveRange(start: start, end: end),
            segments: [LeaveRange(start: end.addingTimeInterval(12 * 3600), end: end.addingTimeInterval(12 * 3600), pay: .unpaid)])
        let suite = "app.dayperk.tests.leave.timezone." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(pacific.timeZone.identifier, forKey: "dayperkWorkTimeZone")
        defaults.set(try JSONEncoder().encode([request]), forKey: LeaveRequests.storageKey)
        let archive = try AppDataBackup.create(defaults: defaults,
            backgroundURL: FileManager.default.temporaryDirectory.appendingPathComponent(suite + ".png"))
        #expect(try AppDataBackup.validate(archive)[LeaveRequests.storageKey] != nil)
    }
    @Test func leaveSelectionRequiresOptInAndStartsAsPaidFullDays() {
        var draft = LeaveRequestDraft()
        #expect(!draft.isSelecting)
        draft.base.portion = .morning; draft.base.pay = .unpaid
        draft.changes = [LeaveRange(start: Date(), end: Date())]
        draft.beginSelection()
        #expect(draft.isSelecting)
        #expect(draft.base.start == draft.base.end)
        #expect(draft.base.portion == .full && draft.base.pay == .paid && draft.changes.isEmpty)
        draft.isSelecting = false
        #expect(!draft.isSelecting)
    }
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }
    private func date(_ day: Int, _ hour: Int = 12, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }
    private var plan: WorkPlan {
        WorkPlan(startMinute: 10 * 60 + 30, endMinute: 20 * 60 + 30, ratePerSecond: 1,
            breakPeriods: [WorkBreak(startMinute: 12 * 60, endMinute: 14 * 60)], dayStartMinute: 0,
            defaultDailyExpectedIncome: 800, referenceSeconds: 8 * 3600)
    }

    @Test func thirtyCalendarDaysAreSavedOnceWithPaidFullDayDefaults() throws {
        var draft = LeaveRequestDraft()
        draft.base.start = date(2); draft.base.end = date(1, month: 12)
        let days = try LeaveLedger.applying(draft, to: [:], plan: plan, calendar: calendar)
        #expect(days.count == 22)
        #expect(days.values.allSatisfy { $0.morning == .paid && $0.afternoon == .paid })
        let periods = LeaveLedger.periods(days, plan: plan, calendar: calendar)
        #expect(periods.count == 1 && periods[0].workdays == 22)
        #expect(WorkPlan.dayKey(periods[0].start, calendar: calendar) == "2026-11-02")
        #expect(WorkPlan.dayKey(periods[0].end, calendar: calendar) == "2026-12-01")
    }

    @Test func arbitrarySubrangesCanChangePayAndHalfDaysWithoutThirtyEdits() throws {
        var draft = LeaveRequestDraft()
        draft.base.start = date(2); draft.base.end = date(1, month: 12)
        draft.changes = [LeaveRange(start: date(9), end: date(13), portion: .morning, pay: .unpaid),
                         LeaveRange(start: date(16), end: date(18), portion: .full, pay: .unpaid)]
        let outside = ["2026-10-30": LeaveDay(afternoon: .paid)]
        let days = try LeaveLedger.applying(draft, to: outside, plan: plan, calendar: calendar)
        #expect(days.count == 23 && days["2026-10-30"] == outside["2026-10-30"])
        for day in 9 ... 13 {
            let value = try #require(days[String(format: "2026-11-%02d", day)])
            #expect(value.morning == .unpaid && value.afternoon == nil && value.unpaidFraction == 0.5)
        }
        #expect(days["2026-11-16"]?.unpaidFraction == 1)
        #expect(days["2026-11-19"]?.paidFraction == 1)
        #expect(try LeaveLedger.applying(draft, to: days, plan: plan, calendar: calendar) == days)
        draft.changes.append(LeaveRange(start: date(1), end: date(4), pay: .unpaid))
        #expect(throws: DayPerkInputError.self) { try LeaveLedger.applying(draft, to: days, plan: plan, calendar: calendar) }
    }

    @Test func sameDaySelectionIsOneDayAndTwoHalfDayChangesCanCoexist() throws {
        var draft = LeaveRequestDraft()
        draft.base.start = date(23); draft.base.end = date(23)
        #expect(try LeaveLedger.applying(draft, to: [:], plan: plan, calendar: calendar).count == 1)
        draft.changes = [LeaveRange(start: date(23), end: date(23), portion: .morning, pay: .unpaid),
                         LeaveRange(start: date(23), end: date(23), portion: .afternoon, pay: .paid)]
        let day = try #require(LeaveLedger.applying(draft, to: [:], plan: plan, calendar: calendar)["2026-11-23"])
        #expect(day.morning == .unpaid && day.afternoon == .paid && day.unpaidFraction == 0.5)
    }

    @Test func paidAfternoonKeepsFullPayButOnlyNinetyMinutesOfWorkRemain() {
        var value = plan
        value.leaveDays = ["2026-11-23": LeaveDay(afternoon: .paid)]
        #expect(value.expectedIncome(for: "2026-11-23", calendar: calendar) == 800)
        #expect(value.referenceSeconds(for: "2026-11-23") == 90 * 60)
        #expect(value.isWithinWorkHours(date(23, 11), calendar: calendar))
        #expect(!value.isWithinWorkHours(date(23, 15), calendar: calendar))
        var day = WorkDayTotal(id: "2026-11-23", seconds: 90 * 60)
        value.stamp(&day, calendar: calendar)
        #expect(day.unpaidOvertimeSeconds == 0)
    }

    @Test func unpaidMorningDeductsHalfPayAlthoughOnlyNinetyMinutesAreAbsent() {
        var value = plan
        value.leaveDays = ["2026-11-23": LeaveDay(morning: .unpaid)]
        #expect(value.expectedIncome(for: "2026-11-23", calendar: calendar) == 400)
        #expect(value.referenceSeconds(for: "2026-11-23") == 6.5 * 3600)
        #expect(!value.isWithinWorkHours(date(23, 11), calendar: calendar))
        #expect(value.isWithinWorkHours(date(23, 15), calendar: calendar))
        // 请假不改变原始时薪的月参考分母。
        #expect(value.monthlyReferenceSeconds(year: 2026, month: 11, calendar: calendar) == plan.monthlyReferenceSeconds(year: 2026, month: 11, calendar: calendar))
    }

    @Test func splitRangesCrossMonthsSkipRestDaysAndRejectOverlapsAtomically() throws {
        let ranges = [LeaveRange(start: date(27), end: date(1, month: 12), portion: .full, pay: .paid),
                      LeaveRange(start: date(3, month: 12), end: date(3, month: 12), portion: .morning, pay: .unpaid)]
        let saved = try LeaveLedger.adding(ranges, to: [:], plan: plan, calendar: calendar)
        #expect(Set(saved.keys) == ["2026-11-27", "2026-11-30", "2026-12-01", "2026-12-03"])
        #expect(saved["2026-12-03"]?.unpaidFraction == 0.5)
        #expect(throws: DayPerkInputError.self) { try LeaveLedger.adding(ranges, to: saved, plan: plan, calendar: calendar) }
        #expect(saved.count == 4)
        #expect(throws: DayPerkInputError.self) { try LeaveLedger.adding([LeaveRange(start: date(29), end: date(29))], to: [:], plan: plan, calendar: calendar) }
    }

    @Test func oppositeHalfDaysCombineAndAllowDifferentPayTypes() throws {
        let saved = try LeaveLedger.adding([
            LeaveRange(start: date(23), end: date(23), portion: .morning, pay: .unpaid),
            LeaveRange(start: date(23), end: date(23), portion: .afternoon, pay: .paid)
        ], to: [:], plan: plan, calendar: calendar)
        var value = plan; value.leaveDays = saved
        #expect(saved["2026-11-23"]?.absenceFraction == 1)
        #expect(value.referenceSeconds(for: "2026-11-23") == 0)
        #expect(value.expectedIncome(for: "2026-11-23", calendar: calendar) == 400)
        #expect(WorkDayTotal(id: "2026-11-23", seconds: 60, referenceSeconds: 0).unpaidOvertimeSeconds == 60)
    }

    @Test func overnightBoundaryIsEditableAndUsesTheShiftBusinessDate() {
        var value = WorkPlan(weekdays: Set(1 ... 7), startMinute: 22 * 60, endMinute: 7 * 60, dayStartMinute: 12 * 60,
            defaultDailyExpectedIncome: 800, referenceSeconds: 8 * 3600)
        value.rhythm.daySchedules = ["2026-11-23": DayWorkSchedule(startMinute: 22 * 60, endMinute: 7 * 60,
            breakMode: .timeRanges, breaks: [WorkBreak(startMinute: 2 * 60, endMinute: 3 * 60)])]
        value.leaveDays = ["2026-11-23": LeaveDay(afternoon: .paid, boundaryMinute: 3 * 60)]
        #expect(value.referenceSeconds(for: "2026-11-23") == 4 * 3600)
        #expect(value.isWithinWorkHours(date(24, 1), calendar: calendar))
        #expect(!value.isWithinWorkHours(date(24, 4), calendar: calendar))
    }

    @Test func changingLeaveOnlyRestampsAffectedBudgetsAndKeepsActualHistory() {
        let original = WorkDayTotal(id: "2026-11-23", seconds: 3600, earned: 123, ratePerSecond: 123 / 3600,
            expectedIncome: 800, referenceSeconds: 8 * 3600, currencyCode: "CNY", settledAt: date(23, 20))
        var state = WorkTrackingState(); state.days = [original]
        var value = plan; value.leaveDays = [original.id: LeaveDay(morning: .unpaid)]
        state.reprice(using: value, at: date(24), calendar: calendar, leaveChangedDays: [original.id])
        #expect(state.days[0].seconds == original.seconds && state.days[0].earned == original.earned)
        #expect(state.days[0].ratePerSecond == original.ratePerSecond && state.days[0].settledAt == original.settledAt)
        #expect(state.days[0].expectedIncome == 400 && state.days[0].referenceSeconds == 6.5 * 3600)
    }

    @Test func mainlandUnpaidHalfDayReducesGrossBeforeTaxWithoutChangingDeclaredBases() {
        var config = PayrollDeductionConfiguration(); config.taxYear = 2026; config.taxMonth = 11
        config.contributionBase = 11454; config.housingFundBase = 11454
        let before = PayrollCalculator.calculate(grossMonthlyIncome: 11454, configuration: config)
        config.estimatedUnpaidLeaveByMonth = [11: 11454 / 21 / 2]
        let after = PayrollCalculator.calculate(grossMonthlyIncome: 11454, configuration: config)
        #expect(after.grossMonthlyIncome == PayrollCalculator.money(11454 - 11454 / 21 / 2))
        #expect(after.employeeSocialInsurance == before.employeeSocialInsurance && after.housingFund == before.housingFund)
        #expect(after.individualIncomeTax <= before.individualIncomeTax && after.netMonthlyIncome < before.netMonthlyIncome)
        config.records = [PayrollIncomeRecord(year: 2026, month: 11, isSalary: true, income: 9000, paidTax: 100, employeeDeductions: 1000)]
        #expect(PayrollCalculator.calculate(grossMonthlyIncome: 11454, configuration: config).grossMonthlyIncome == 9000)
    }

    @Test func leaveFlowsToWeekMonthAndExcelWithoutInventingWorkHours() {
        let expected: (WorkDayTotal) -> Double = { $0.id == "2026-11-23" ? 400 : 0 }
        for period in [WorkReportPeriod.week, .month] {
            let report = WorkReport.make(days: [], containing: date(23), period: period, calendar: calendar, asOf: date(25),
                expectedIncome: expected, leave: { $0 == "2026-11-23" ? LeaveSummary(unpaidSeconds: 90 * 60, unpaidDays: 0.5) : LeaveSummary() })
            #expect(report.unpaidLeaveDays == 0.5)
            #expect(report.unpaidLeaveSeconds == 90 * 60 && report.paidLeaveSeconds == 0)
            #expect(report.expectedIncome == 400 && report.seconds == 0 && report.unpaidOvertimeSeconds == 0)
            let file = ReportExcelExport.data(report: report, currency: "CNY", calendar: calendar, locale: Locale(identifier: "en"))
            #expect(String(decoding: file, as: UTF8.self).contains("SUM(J2:J"))
        }
    }

    @Test func leaveBackupRoundTripAndValidation() throws {
        let name = "app.dayperk.tests.leave." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        let days = ["2026-11-23": LeaveDay(morning: .unpaid, afternoon: .paid, boundaryMinute: 12 * 60, afternoonKind: .compensatory)]
        defaults.set(try JSONEncoder().encode(days), forKey: LeaveLedger.storageKey)
        let requests = LeaveRequests.migrate(days, plan: plan, calendar: calendar)
        defaults.set(try JSONEncoder().encode(requests), forKey: LeaveRequests.storageKey)
        let image = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".png")
        let archive = try AppDataBackup.create(defaults: defaults, backgroundURL: image)
        defaults.removeObject(forKey: LeaveLedger.storageKey)
        defaults.removeObject(forKey: LeaveRequests.storageKey)
        try AppDataBackup.restore(archive, defaults: defaults, domain: name, backgroundURL: image)
        #expect(try JSONDecoder().decode([String: LeaveDay].self, from: #require(defaults.data(forKey: LeaveLedger.storageKey))) == days)
        #expect(try JSONDecoder().decode([LeaveRequest].self, from: #require(defaults.data(forKey: LeaveRequests.storageKey))) == requests)
        #expect(throws: DayPerkInputError.self) { try LeaveLedger.validate(["invalid": LeaveDay(morning: .paid)]) }
    }
}
