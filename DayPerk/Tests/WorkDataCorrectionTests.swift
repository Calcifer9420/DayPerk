import Foundation
import Testing
@testable import DayPerk

struct WorkDataCorrectionTests {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Shanghai")!; return c }
    private func date(_ day: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 12))! }

    @Test func explicitCorrectionCanApplyANewRuleToMatchingDatesBeforeCreation() throws {
        let shift = DayWorkSchedule(startMinute: 540, endMinute: 960, breakMinutes: 60)
        let rule = WorkScheduleRule(weekdays: [6], effectiveFromDay: "2026-11-27", schedule: shift)
        var rhythm = WorkRhythm(); rhythm.scheduleRules = [rule]
        var plan = WorkPlan(rhythm: rhythm)
        let before = plan.schedule(for: "2026-11-20")
        let selected = try WorkDataCorrection.dates(from: date(1), through: date(27), asOf: date(27), plan: plan, calendar: calendar, rule: rule)
        #expect(selected == ["2026-11-06", "2026-11-13", "2026-11-20", "2026-11-27"])
        #expect(plan.schedule(for: "2026-11-20") == before && before != shift)
        plan.rhythm.daySchedules = ["2026-11-20": shift]
        #expect(plan.schedule(for: "2026-11-20") == shift)
        #expect(plan.schedule(for: "2026-11-13") == before)
        #expect(plan.schedule(for: "2026-11-19") == before)
    }

    @Test func ruleCoverageRequiresWeekdayAndAlternateWeekAndSkipsHolidays() throws {
        var plan = WorkPlan(dateOverrides: ["2026-11-18": false])
        var rule = WorkScheduleRule(weekdays: [4], intervalWeeks: 2, anchorDay: "2026-11-02")
        #expect(try WorkDataCorrection.dates(from: date(1), through: date(30), asOf: date(30), plan: plan, calendar: calendar, rule: rule) == ["2026-11-04"])
        plan.overtimeDates["2026-11-18"] = 2
        #expect(try WorkDataCorrection.dates(from: date(1), through: date(30), asOf: date(30), plan: plan, calendar: calendar, rule: rule) == ["2026-11-04", "2026-11-18"])
        rule.enabled = false
        #expect(try WorkDataCorrection.dates(from: date(1), through: date(30), asOf: date(30), plan: plan, calendar: calendar, rule: rule).isEmpty)
        #expect(throws: DayPerkInputError.self) { try WorkDataCorrection.dates(from: date(20), through: date(19), asOf: date(30), plan: plan, calendar: calendar) }
        #expect(throws: DayPerkInputError.self) { try WorkDataCorrection.dates(from: date(20), through: date(30), asOf: date(27), plan: plan, calendar: calendar) }
    }

    @Test func historicalActualCorrectionKeepsSnapshotsAndSurvivesCurrentSessionRollback() throws {
        let store = UserDataStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("historical-hours-" + UUID().uuidString))
        let old = WorkDayTotal(id: "2026-11-23", seconds: 3600, earned: 100, ratePerSecond: 100 / 3600,
            expectedIncome: 800, referenceSeconds: 8 * 3600, currencyCode: "CNY", settledAt: date(23))
        store.set(try JSONEncoder().encode(WorkTrackingState(days: [old])), forKey: "manualWorkTrackingV1")
        let controller = WorkTrackingController(defaults: store, calendar: calendar, observeSystem: false)
        defer { controller.shutdown() }
        let now = date(24)
        controller.updatePlan(WorkPlan(ratePerSecond: 2), at: now)
        controller.setWorking(true, at: now)
        try controller.correctDay(old.id, seconds: 7200, at: now.addingTimeInterval(1))
        #expect(controller.state.isWorking)
        let changed = try #require(controller.state.days.first { $0.id == old.id })
        #expect(changed.seconds == 7200 && changed.earned == 200)
        #expect(changed.expectedIncome == 800 && changed.referenceSeconds == 8 * 3600 && changed.settledAt == old.settledAt)
        controller.setWorking(false, at: now.addingTimeInterval(2))
        #expect(controller.state.days.first { $0.id == old.id } == changed)
        #expect(throws: DayPerkInputError.self) { try controller.correctDay("2026-11-25", seconds: 3600, at: now) }
        #expect(throws: DayPerkInputError.self) { try controller.correctDay(old.id, seconds: 86401, at: now) }
        let loaded = try JSONDecoder().decode(WorkTrackingState.self, from: #require(store.data(forKey: "manualWorkTrackingV1")))
        #expect(loaded.days.first { $0.id == old.id } == changed)
    }

    @Test func targetedScheduleCorrectionChangesOnlySelectedSnapshotAndPreservesPayAndActualHours() {
        let now = date(27)
        var plan = WorkPlan(ratePerSecond: 800 / (8 * 3600), defaultDailyExpectedIncome: 800)
        var state = WorkTrackingState(days: [WorkDayTotal(id: "2026-11-04", seconds: 8 * 3600), WorkDayTotal(id: "2026-11-11", seconds: 6 * 3600)])
        state.reprice(using: plan, at: now, calendar: calendar, refreshHistory: true)
        let untouched = state.days[1]
        plan.rhythm.daySchedules = ["2026-11-04": .init(startMinute: 540, endMinute: 960, breakMinutes: 60)]
        plan.dayRates["2026-11-04"] = 800 / (6 * 3600)
        plan.expectedIncomes["2026-11-04"] = 800
        state.reprice(using: plan, at: now, calendar: calendar, correctedDays: ["2026-11-04"])
        #expect(state.days[0].seconds == 8 * 3600 && state.days[0].referenceSeconds == 6 * 3600 && state.days[0].expectedIncome == 800)
        #expect(abs(state.days[0].earned - 800 * 8 / 6) < 0.001)
        #expect(state.days[1] == untouched)
        let report = WorkReport.make(days: state.days, containing: date(4), period: .week, calendar: calendar, asOf: now)
        #expect(report.expectedWorkSeconds == 6 * 3600 && report.workSeconds == 8 * 3600)
        #expect(report.timeDifferenceSeconds == 2 * 3600)
    }
}
