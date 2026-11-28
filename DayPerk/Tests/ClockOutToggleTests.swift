import Foundation
import Testing
@testable import DayPerk

struct ClockOutToggleTests {
    @Test func customProtectionWindowControlsClockOutUndoAndShortSessionDiscard() {
        for limit in [3, 20] {
            var p = plan; p.automation.tapProtectionSeconds = limit
            var s = WorkTrackingState(); s.setWorking(true, at: start, plan: p, calendar: calendar)
            s.finishToday(at: start.addingTimeInterval(60), plan: p, calendar: calendar)
            s.setWorking(true, at: start.addingTimeInterval(65), plan: p, calendar: calendar)
            #expect(s.days[0].seconds == (limit == 20 ? 65 : 60))
            var short = WorkTrackingState(); short.setWorking(true, at: start, plan: p, calendar: calendar)
            short.setWorking(false, at: start.addingTimeInterval(5), plan: p, calendar: calendar)
            #expect((short.days.first?.seconds ?? 0) == (limit == 20 ? 0 : 5))
        }
    }
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private var start: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 16))! }
    private var plan: WorkPlan { WorkPlan(startMinute: 9 * 60, endMinute: 17 * 60, ratePerSecond: 2, dayStartMinute: 240) }
    @Test func tenSecondClockOutUndoBillsGapAndSurvivesStorageRoundTrip() throws {
        for gap in [0.0, 5, 10] {
            var s = WorkTrackingState(); s.setWorking(true, at: start, plan: plan, calendar: calendar)
            s.finishToday(at: start.addingTimeInterval(60), plan: plan, calendar: calendar)
            s = try JSONDecoder().decode(WorkTrackingState.self, from: JSONEncoder().encode(s))
            s.setWorking(true, at: start.addingTimeInterval(60 + gap), plan: plan, calendar: calendar)
            #expect(s.isWorking && s.days[0].settledAt == nil)
            #expect(s.days[0].seconds == 60 + gap && s.days[0].earned == (60 + gap) * 2)
            s.accrue(until: start.addingTimeInterval(90), plan: plan, calendar: calendar)
            #expect(s.days[0].seconds == 90)
        }
    }
    @Test func longerBreakAndDisabledProtectionDoNotBackfill() {
        for (gap, enabled) in [(10.01, true), (5, false)] {
            var p = plan; p.automation.bridgeShortPauses = enabled
            var s = WorkTrackingState(); s.setWorking(true, at: start, plan: p, calendar: calendar)
            s.finishToday(at: start.addingTimeInterval(60), plan: p, calendar: calendar)
            s.setWorking(true, at: start.addingTimeInterval(60 + gap), plan: p, calendar: calendar)
            #expect(s.days[0].seconds == 60)
        }
    }
    @Test func anotherBusinessDayAndManualCorrectionCannotReviveOldClockOut() throws {
        let c = WorkTrackingController(defaults: UserDefaults(suiteName: "app.dayperk.tests.clockout." + UUID().uuidString)!, calendar: calendar, observeSystem: false)
        c.updatePlan(plan, at: start); c.setWorking(true, at: start); c.finishToday(at: start.addingTimeInterval(60))
        try c.correctToday(seconds: 500, at: start.addingTimeInterval(62)); c.setWorking(true, at: start.addingTimeInterval(65))
        #expect(c.state.days[0].seconds == 500)
        var s = WorkTrackingState(); let boundary = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 4))!
        s.setWorking(true, at: boundary.addingTimeInterval(-65), plan: plan, calendar: calendar)
        s.finishToday(at: boundary.addingTimeInterval(-5), plan: plan, calendar: calendar)
        s.setWorking(true, at: boundary.addingTimeInterval(1), plan: plan, calendar: calendar)
        #expect(s.days[0].seconds == 60 && s.days[0].settledAt != nil)
    }
    @Test func clockOutLabelSwitchesAtTheActualShiftEndIncludingOvernightSchedules() {
        #expect(!plan.hasReachedShiftEnd(start.addingTimeInterval(3599), calendar: calendar))
        #expect(plan.hasReachedShiftEnd(start.addingTimeInterval(3600), calendar: calendar))
        var p = plan; p.startMinute = 20 * 60; p.endMinute = 2 * 60
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 1, minute: 59))!
        #expect(!p.hasReachedShiftEnd(day, calendar: calendar))
        #expect(p.hasReachedShiftEnd(day.addingTimeInterval(60), calendar: calendar))
    }
    @Test func restDaysAndFullLeaveDisableClockOutButMakeupWorkAndOvertimeRemainAvailable() {
        let saturday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 28, hour: 16))!
        #expect(plan.canClockOut(start, calendar: calendar))
        #expect(!plan.canClockOut(saturday, calendar: calendar))
        var holiday = plan
        holiday.dateOverrides["2026-11-23"] = false
        #expect(!holiday.canClockOut(start, calendar: calendar))
        var makeup = plan
        makeup.dateOverrides["2026-11-28"] = true
        #expect(makeup.canClockOut(saturday, calendar: calendar))
        var overtime = plan
        overtime.overtimeDates["2026-11-28"] = 2
        #expect(overtime.canClockOut(saturday, calendar: calendar))
        var leave = plan
        leave.leaveDays["2026-11-23"] = LeaveDay(morning: .paid, afternoon: .paid)
        #expect(!leave.canClockOut(start, calendar: calendar))
        leave.leaveDays["2026-11-23"] = LeaveDay(morning: .unpaid)
        #expect(leave.canClockOut(start, calendar: calendar))
    }
    @Test func systemLockCancelsClockOutBackfillAndDstUsesLocalShiftEnd() {
        var s = WorkTrackingState(); s.setWorking(true, at: start, plan: plan, calendar: calendar)
        s.finishToday(at: start.addingTimeInterval(60), plan: plan, calendar: calendar)
        s.suspend(at: start.addingTimeInterval(62), plan: plan, calendar: calendar)
        s.setWorking(true, at: start.addingTimeInterval(65), plan: plan, calendar: calendar)
        #expect(s.days[0].seconds == 60)
        var local = calendar; local.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let end = local.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 17))!
        #expect(!plan.hasReachedShiftEnd(end.addingTimeInterval(-1), calendar: local))
        #expect(plan.hasReachedShiftEnd(end, calendar: local))
    }
    @Test func decimalInputsFollowTheSelectedLanguage() {
        #expect(LocalizedNumberInput.value("11454,25", locale: Locale(identifier: "fr")) == 11454.25)
        #expect(LocalizedNumberInput.value("12,5", locale: Locale(identifier: "de")) == 12.5)
        #expect(LocalizedNumberInput.value("12.5", locale: Locale(identifier: "en")) == 12.5)
        #expect(LocalizedNumberInput.value("12,5", locale: Locale(identifier: "en")) == nil)
        #expect(LocalizedNumberInput.value("1,234.5", locale: Locale(identifier: "en")) == nil)
    }
}
