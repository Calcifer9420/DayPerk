import Foundation
@testable import DayPerk
import SwiftUI
import Testing

struct WorkStatisticsTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test func weekStartsMondayAndIncludesSundayAcrossMonthBoundary() {
        let records = [WorkDayTotal(id: "2026-11-29", seconds: 3600, earned: 100),
                       WorkDayTotal(id: "2026-11-30", seconds: 7200, overtimeSeconds: 1800, earned: 200, referenceSeconds: 6000),
                       WorkDayTotal(id: "2026-12-06", seconds: 3600, earned: 150, referenceSeconds: 1800),
                       WorkDayTotal(id: "2026-12-07", seconds: 7200, earned: 250)]
        let report = WorkReport.make(days: records, containing: date(2026, 12, 6), period: .week, calendar: calendar, asOf: date(2026, 12, 6))
        #expect(report.days.count == 7)
        #expect(report.days.first?.id == "2026-11-30")
        #expect(report.days.last?.id == "2026-12-06")
        #expect(report.seconds == 10800 && report.overtimeSeconds == 1800)
        #expect(report.earned == 350 && report.workedDays == 2)
        #expect(report.unpaidOvertimeSeconds == 3000)
    }

    @Test func monthUsesRecordedValueAndExplicitOvertimeWithoutDuplication() {
        let records = [WorkDayTotal(id: "2026-11-01", seconds: 3600, overtimeSeconds: 600, earned: 111.25),
                       WorkDayTotal(id: "2026-11-30", seconds: 7200, overtimeSeconds: 7200, earned: 222.5),
                       WorkDayTotal(id: "2026-12-01", seconds: 7200, earned: 500)]
        let report = WorkReport.make(days: records, containing: date(2026, 11, 23), period: .month,
                                     calendar: calendar, asOf: date(2026, 11, 30))
        #expect(report.days.count == 30)
        #expect(report.seconds == 10800 && report.overtimeSeconds == 7800)
        #expect(report.earned == 333.75 && report.workedDays == 2)
        #expect(records[1].overtimeSeconds == 7200)
    }

    @Test func expectedIncomeAggregatesSeparatelyAndBalanceAllowsBothSigns() {
        let records = [WorkDayTotal(id: "2026-11-23", seconds: 3600, earned: 300),
                       WorkDayTotal(id: "2026-11-24", seconds: 1800, earned: 100)]
        let income: (WorkDayTotal) -> Double = { day in day.id == "2026-11-23" ? 200 : day.id == "2026-11-24" ? 250 : 0 }
        let unpaid = WorkReport.make(days: records, containing: date(2026, 11, 23), period: .day,
                                     calendar: calendar, asOf: date(2026, 11, 24), expectedIncome: income)
        #expect(unpaid.earned == 300 && unpaid.expectedIncome == 200 && unpaid.balance == -100)
        let gained = WorkReport.make(days: records, containing: date(2026, 11, 24), period: .day,
                                     calendar: calendar, asOf: date(2026, 11, 24), expectedIncome: income)
        #expect(gained.earned == 100 && gained.expectedIncome == 250 && gained.balance == 150)
        let week = WorkReport.make(days: records, containing: date(2026, 11, 23), period: .week,
                                   calendar: calendar, asOf: date(2026, 11, 24), expectedIncome: income)
        #expect(week.earned == 400 && week.expectedIncome == 450 && week.balance == 50)
        #expect(records[0].earned == 300 && records[1].earned == 100)
    }

    @Test func noWorkDayCanHaveFixedExpectedIncomeWithoutInventingTimeValue() {
        let report = WorkReport.make(days: [], containing: date(2026, 11, 23), period: .day,
                                     calendar: calendar, asOf: date(2026, 11, 23), expectedIncome: { _ in 200 })
        #expect(report.earned == 0 && report.expectedIncome == 200 && report.balance == 200)
        #expect(report.seconds == 0 && report.overtimeSeconds == 0 && report.workedDays == 0)
    }

    @Test func futureWorkdayHasZeroBalanceAndDoesNotInflateTotals() {
        let workdays: Set = ["2026-11-23", "2026-11-24", "2026-11-25", "2026-11-26", "2026-11-27"]
        let report = WorkReport.make(days: [], containing: date(2026, 11, 23), period: .week,
                                     calendar: calendar, asOf: date(2026, 11, 24),
                                     expectedIncome: { workdays.contains($0.id) ? 200 : 0 })
        #expect(report.expectedIncome == 400 && report.balance == 400)
        #expect(report.seconds == 0 && report.earned == 0 && report.workedDays == 0)
        #expect(report.days.suffix(2).allSatisfy { $0.expectedIncome == 0 })
        #expect(report.days.filter(\.isFuture).allSatisfy { $0.balance == 0 })
        #expect(report.days.first { $0.id == "2026-11-27" }?.expectedIncome == 200)
    }

    @Test func reportUsesCivilDateKeysWithoutApplyingBusinessDayOffsetAgain() throws {
        let earlyMorning = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 1)))
        let records = [WorkDayTotal(id: "2026-11-23", seconds: 3600, earned: 100),
                       WorkDayTotal(id: "2026-11-24", seconds: 7200, earned: 200)]
        let report = WorkReport.make(days: records, containing: earlyMorning, period: .day, calendar: calendar)
        #expect(report.days.first?.id == "2026-11-24")
        #expect(report.seconds == 7200 && report.earned == 200)
    }

    @Test func historicalIncomeSnapshotsAreUsedAsProvidedWithoutChangingRecordedHours() {
        let records = [WorkDayTotal(id: "2026-11-23", seconds: 3600, earned: 100),
                       WorkDayTotal(id: "2026-11-24", seconds: 7200, earned: 200)]
        let frozenIncome = ["2026-11-23": 300.0, "2026-11-24": 400.0]
        let report = WorkReport.make(days: records, containing: date(2026, 11, 23), period: .week,
                                     calendar: calendar, asOf: date(2026, 11, 24), expectedIncome: { frozenIncome[$0.id] ?? 0 })
        #expect(report.expectedIncome == 700 && report.earned == 300 && report.balance == 400)
        #expect(report.seconds == 10800 && records[0].seconds == 3600 && records[1].seconds == 7200)
    }

    @Test func dailyReportsIncludeZeroDayAndLeapMonthHasTwentyNineRows() {
        let report = WorkReport.make(days: [], containing: date(2028, 2, 29), period: .day, calendar: calendar)
        #expect(report.days.count == 1 && report.days[0].id == "2028-02-29")
        #expect(report.seconds == 0 && report.earned == 0 && report.workedDays == 0)
        let month = WorkReport.make(days: [], containing: date(2028, 2, 29), period: .month, calendar: calendar)
        #expect(month.days.count == 29)
    }

    @Test func monthlyRowsGroupMondayWeeksAndClipBothMonthBoundaries() {
        let records = [WorkDayTotal(id: "2026-11-01", seconds: 3600, earned: 300),
                       WorkDayTotal(id: "2026-11-23", seconds: 7200, earned: 100),
                       WorkDayTotal(id: "2026-11-30", seconds: 1800, earned: 75),
                       WorkDayTotal(id: "2026-12-01", seconds: 9999, earned: 999)]
        let month = WorkReport.make(days: records, containing: date(2026, 11, 24), period: .month,
                                    calendar: calendar, asOf: date(2026, 11, 24),
                                    expectedIncome: { $0.id == "2026-11-01" ? 200 : $0.id == "2026-11-23" ? 250 : 0 })
        let weeks = month.rows(byWeek: true, calendar: calendar)
        #expect(weeks.count == 6)
        #expect(weeks.first?.days.map(\.id) == ["2026-11-01"])
        #expect(weeks[1].days.first?.id == "2026-11-02" && weeks[1].days.last?.id == "2026-11-08")
        #expect(weeks.last?.days.map(\.id) == ["2026-11-30"])
        #expect(weeks.flatMap(\.days).map(\.id) == month.days.map(\.id))
        #expect(weeks.first?.balance == -100 && weeks[4].balance == 150 && weeks.last?.balance == 0)
        #expect(weeks.reduce(0) { $0 + $1.balance } == month.balance && month.balance == 50)
        #expect(month.earned == 400 && month.seconds == 10800 && month.workedDays == 2)
        #expect(weeks.reduce(0) { $0 + $1.seconds } == month.seconds)
        #expect(month.rows(byWeek: false, calendar: calendar).count == 30)
    }

    @Test func balanceColorDoesNotRevealMaskedAmounts() {
        #expect(WorkBalancePresentation.color(for: 1, visible: true) == .green)
        #expect(WorkBalancePresentation.color(for: -1, visible: true) == .red)
        #expect(WorkBalancePresentation.color(for: 0, visible: true) == .secondary)
        #expect(WorkBalancePresentation.color(for: 1, visible: false) == .secondary)
        #expect(WorkBalancePresentation.color(for: -1, visible: false) == .secondary)
    }

    @Test func reportsCompareExpectedAndActualSecondsWithoutCountingOvertimeTwice() {
        let records = [WorkDayTotal(id: "2026-11-23", seconds: 8 * 3600 + 32 * 60 + 45, overtimeSeconds: 3600, earned: 100, referenceSeconds: 8.5 * 3600),
                       WorkDayTotal(id: "2026-11-24", seconds: 7 * 3600 + 8 * 60 + 45, earned: 100, referenceSeconds: 8.5 * 3600)]
        let report = WorkReport.make(days: records, containing: date(2026, 11, 24), period: .week, calendar: calendar, asOf: date(2026, 11, 24))
        let rows = report.rows(byWeek: false, calendar: calendar)
        #expect(rows[0].workSeconds == 30765 && rows[0].expectedWorkSeconds == 30600 && rows[0].timeDifferenceSeconds == 165)
        #expect(rows[1].workSeconds == 25725 && rows[1].timeDifferenceSeconds == -4875)
        #expect(report.workSeconds == 56490 && report.expectedWorkSeconds == 61200 && report.timeDifferenceSeconds == -4710)
        #expect(WorkDurationInput.formatSeconds(rows[1].timeDifferenceSeconds, signed: true) == "-01:21:15")
        #expect(rows.allSatisfy { $0.days.count == 1 && $0.workSeconds <= 86400 && $0.expectedWorkSeconds <= 86400 })
        #expect(records[0].seconds == 30765 && records[0].overtimeSeconds == 3600)
    }

    @Test func expectedHoursUseSnapshotsOrTheScheduledShiftAndLeaveHours() {
        var plan = WorkPlan(startMinute: 630, endMinute: 1230,
            breakPeriods: [WorkBreak(startMinute: 720, endMinute: 840)], referenceSeconds: 8 * 3600)
        let historical = WorkDayTotal(id: "2026-11-23", referenceSeconds: 7 * 3600)
        #expect(plan.expectedWorkSeconds(for: historical, calendar: calendar) == 7 * 3600)
        #expect(plan.expectedWorkSeconds(for: historical, calendar: calendar, preservingExisting: false) == 8 * 3600)
        #expect(plan.expectedWorkSeconds(for: WorkDayTotal(id: "2026-11-24"), calendar: calendar) == 8 * 3600)
        #expect(plan.expectedWorkSeconds(for: WorkDayTotal(id: "2026-11-28", referenceSeconds: 8 * 3600), calendar: calendar) == 0)
        plan.overtimeDates = ["2026-11-28": 2]
        #expect(plan.expectedWorkSeconds(for: WorkDayTotal(id: "2026-11-28"), calendar: calendar) == 8 * 3600)
        plan.rhythm.scheduleRules = [WorkScheduleRule(weekdays: [6], schedule: DayWorkSchedule(startMinute: 540, endMinute: 1080, breakMinutes: 60))]
        #expect(plan.expectedWorkSeconds(for: WorkDayTotal(id: "2026-11-27"), calendar: calendar) == 8 * 3600)
        plan.rhythm.scheduleRules?[0].schedule.endMinute = 960
        #expect(plan.expectedWorkSeconds(for: WorkDayTotal(id: "2026-11-27"), calendar: calendar) == 6 * 3600)
        plan.leaveDays = ["2026-11-23": LeaveDay(afternoon: .paid), "2026-11-24": LeaveDay(morning: .unpaid)]
        #expect(plan.expectedWorkSeconds(for: WorkDayTotal(id: "2026-11-23"), calendar: calendar) == 90 * 60)
        #expect(plan.expectedWorkSeconds(for: WorkDayTotal(id: "2026-11-24"), calendar: calendar) == 390 * 60)
    }

    @Test func futureTimeDifferencesAreZeroAndMonthlyRowsReconcileToTheSecond() {
        let records = [WorkDayTotal(id: "2026-11-23", seconds: 8 * 3600 + 32 * 60 + 45),
                       WorkDayTotal(id: "2026-11-24", seconds: 7 * 3600 + 8 * 60 + 45)]
        let report = WorkReport.make(days: records, containing: date(2026, 11, 24), period: .month, calendar: calendar, asOf: date(2026, 11, 24),
            expectedWorkSeconds: { $0.id >= "2026-11-23" ? 8.5 * 3600 : 0 })
        let futureRows = report.rows(byWeek: false, calendar: calendar).filter { $0.days[0].isFuture }
        #expect(futureRows.allSatisfy { $0.workSeconds == 0 && $0.expectedWorkSeconds == 0 && $0.timeDifferenceSeconds == 0 })
        let weeks = report.rows(byWeek: true, calendar: calendar)
        #expect(weeks.reduce(0) { $0 + $1.workSeconds } == report.workSeconds)
        #expect(weeks.reduce(0) { $0 + $1.expectedWorkSeconds } == report.expectedWorkSeconds)
        #expect(weeks.reduce(0) { $0 + $1.timeDifferenceSeconds } == report.timeDifferenceSeconds)
        #expect(report.workSeconds == 56490 && report.timeDifferenceSeconds == -4710)
    }

    @Test func reportDurationFormattingAndColorsDistinguishExtraWorkFromTimeSaved() {
        #expect(WorkDurationInput.formatSeconds(0, signed: true) == "00:00:00")
        #expect(WorkDurationInput.formatSeconds(165, signed: true) == "+00:02:45")
        #expect(WorkDurationInput.formatSeconds(-4875, signed: true) == "-01:21:15")
        #expect(WorkDurationInput.formatSeconds(168 * 3600 + 30 * 60 + 1) == "168:30:01")
        #expect(WorkDurationInput.wholeSeconds(59.9) == 59 && WorkDurationInput.wholeSeconds(60) == 60)
        #expect(WorkDurationInput.wholeSeconds(.nan) == 0 && WorkDurationInput.wholeSeconds(.infinity) == 0)
        #expect(WorkBalancePresentation.timeColor(for: 2) == .red)
        #expect(WorkBalancePresentation.timeColor(for: -82) == .green)
        #expect(WorkBalancePresentation.timeColor(for: 0) == .secondary)
    }
}
