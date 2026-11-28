import Foundation
@testable import DayPerk
import Testing

struct DepartureSurplusTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return value
    }

    private func date(_ day: Int = 23, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private var plan: WorkPlan {
        WorkPlan(startMinute: 9 * 60, endMinute: 18 * 60, ratePerSecond: 1,
                 breakPeriods: [WorkBreak(startMinute: 12 * 60, endMinute: 13 * 60)],
                 defaultDailyExpectedIncome: 8 * 3600)
    }

    private func state(earned: Double = 7 * 3600 - 1) -> WorkTrackingState {
        WorkTrackingState(days: [WorkDayTotal(id: "2026-11-23", earned: earned)])
    }

    @Test func onlyClockOutWindowTriggersAndThresholdIsStrict() {
        for time in [date(23, 11, 30), date(23, 17, 29), date(23, 18, 1)] {
            var s = state(earned: 0)
            s.checkDepartureSurplus(at: time, plan: plan, calendar: calendar)
            #expect(s.securedSurplusDay == nil)
        }
        var s = state(earned: 7 * 3600)
        s.checkDepartureSurplus(at: date(23, 17, 30), plan: plan, calendar: calendar)
        #expect(s.securedSurplusDay == nil)
        s.days[0].earned -= 1
        s.checkDepartureSurplus(at: date(23, 17, 30), plan: plan, calendar: calendar)
        #expect(s.securedSurplusDay == "2026-11-23")
    }

    @Test func predictionCountsRemainingTimeEvenWhenPausedAndUsesSelectedDayRate() {
        var s = state(earned: 7 * 3600 + 1)
        #expect(!s.isWorking)
        s.checkDepartureSurplus(at: date(23, 17, 30), plan: plan, calendar: calendar)
        #expect(s.securedSurplusDay == nil)
        var p = plan
        p.dayRates["2026-11-23"] = 2
        s.days[0].earned = 6 * 3600
        s.checkDepartureSurplus(at: date(23, 17, 30), plan: p, calendar: calendar)
        #expect(s.securedSurplusDay == nil)
        s.days[0].earned -= 1
        s.checkDepartureSurplus(at: date(23, 17, 30), plan: p, calendar: calendar)
        #expect(s.securedSurplusDay == "2026-11-23")
    }

    @Test func earnedGreenSurvivesRepricingRelaunchAndDayBoundary() throws {
        var s = state()
        s.checkDepartureSurplus(at: date(23, 17, 30), plan: plan, calendar: calendar)
        s.days[0].seconds = 10 * 3600
        s.reprice(using: plan, at: date(23, 20), calendar: calendar)
        #expect(s.securedSurplusDay == "2026-11-23")
        var restored = try JSONDecoder().decode(WorkTrackingState.self, from: JSONEncoder().encode(s))
        restored.recoverAfterRelaunch()
        #expect(restored.securedSurplusDay == plan.businessDayKey(date(24, 3, 59), calendar: calendar))
        #expect(restored.securedSurplusDay != plan.businessDayKey(date(24, 4), calendar: calendar))
        restored.checkDepartureSurplus(at: date(24, 17, 30), plan: plan, calendar: calendar)
        #expect(restored.securedSurplusDay == "2026-11-24")
    }

    @Test func nonWorkdaysAndInvalidRatesDoNotTrigger() {
        for rate in [0.0, -1, .nan, .infinity] {
            var p = plan; p.ratePerSecond = rate
            var s = state(earned: 0)
            s.checkDepartureSurplus(at: date(23, 17, 30), plan: p, calendar: calendar)
            #expect(s.securedSurplusDay == nil)
        }
        var s = WorkTrackingState()
        s.checkDepartureSurplus(at: date(28, 17, 30), plan: plan, calendar: calendar)
        #expect(s.securedSurplusDay == nil)
        var p = plan
        p.overtimeDates["2026-11-28"] = 2
        p.expectedIncomes["2026-11-28"] = 8 * 3600
        s.checkDepartureSurplus(at: date(28, 17, 30), plan: p, calendar: calendar)
        #expect(s.securedSurplusDay == "2026-11-28")
    }

    @Test func overnightClockOutBelongsToPriorBusinessDay() {
        var p = plan; p.endMinute = 60
        var s = state()
        s.checkDepartureSurplus(at: date(24, 0, 30), plan: p, calendar: calendar)
        #expect(s.securedSurplusDay == "2026-11-23")
    }

    @Test func controllerCorrectionPersistsAwardWithoutChangingPastDays() throws {
        let store = UserDefaults(suiteName: "departure-surplus-\(UUID().uuidString)")!
        let c = WorkTrackingController(defaults: store, calendar: calendar, observeSystem: false)
        c.updatePlan(plan, at: date(23, 17))
        try c.correctToday(seconds: 7 * 3600, at: date(23, 17, 30))
        #expect(c.state.securedSurplusDay == nil)
        try c.correctToday(seconds: 7 * 3600 - 1, at: date(23, 17, 30))
        #expect(c.state.securedSurplusDay == "2026-11-23")
        let stored = try JSONDecoder().decode(WorkTrackingState.self, from: #require(store.data(forKey: "manualWorkTrackingV1")))
        #expect(stored.securedSurplusDay == "2026-11-23")
        let oldDay = c.state.days[0]
        c.updatePlan(plan, at: date(24, 4))
        #expect(c.state.days[0] == oldDay)
    }

    @Test func oldStoredStateDecodesWithoutAward() throws {
        let old = Data(#"{"caffeineEnabled":false,"isWorking":false,"days":[]}"#.utf8)
        let state = try JSONDecoder().decode(WorkTrackingState.self, from: old)
        #expect(state.securedSurplusDay == nil)
    }
}
