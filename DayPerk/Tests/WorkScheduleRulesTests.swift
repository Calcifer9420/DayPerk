import Foundation
import Testing
@testable import DayPerk

struct WorkScheduleRulesTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }
    private func date(_ day: Int, _ hour: Int = 12, _ minute: Int = 0, month: Int = 11, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
    private var normal: DayWorkSchedule { DayWorkSchedule(startMinute: 540, endMinute: 1080, breakMinutes: 60) }
    private var short: DayWorkSchedule { DayWorkSchedule(startMinute: 540, endMinute: 960, breakMinutes: 60) }
    private func weeklyRules() -> [WorkScheduleRule] {
        [WorkScheduleRule(name: "Friday", weekdays: [6], schedule: short),
         WorkScheduleRule(name: "Alternate Wednesday", weekdays: [4], intervalWeeks: 2, anchorDay: "2026-11-02", schedule: short)]
    }

    @Test func newlyCreatedRulesDoNotRewritePastSchedulesOrMonthlyHours() throws {
        let rule = WorkScheduleRule(weekdays: [6], effectiveFromDay: "2026-11-27", schedule: short)
        var rhythm = WorkRhythm(); rhythm.scheduleRules = [rule]
        let plan = WorkPlan(startMinute: 540, endMinute: 1080, referenceSeconds: 8 * 3600, rhythm: rhythm)
        for key in ["2026-11-06", "2026-11-13", "2026-11-20"] {
            #expect(!rule.matches(key) && rule.matchesRecurrence(key))
            #expect(plan.schedule(for: key) == normal)
            #expect(plan.scheduledReferenceSeconds(for: key) == 8 * 3600)
        }
        #expect(rule.matches("2026-11-27") && rule.matches("2026-12-04"))
        #expect(plan.schedule(for: "2026-11-27") == short)
        #expect(plan.monthlyReferenceSeconds(year: 2026, month: 11, calendar: calendar) == 166 * 3600)
        try rhythm.validate()
    }

    @Test func recurrenceAnchorAndCreationDateRemainIndependent() {
        let rule = WorkScheduleRule(weekdays: [4], intervalWeeks: 2, anchorDay: "2026-11-02", effectiveFromDay: "2026-11-27", schedule: short)
        #expect(!rule.matches("2026-11-18") && rule.matchesRecurrence("2026-11-18"))
        #expect(!rule.matches("2026-11-25") && !rule.matchesRecurrence("2026-11-25"))
        #expect(rule.matches("2026-12-02") && !rule.matches("2026-12-09"))
    }

    @Test func savingEditingAndReorderingPreserveTheOriginalEffectiveDate() {
        let legacy = WorkScheduleRule(name: "旧规则", weekdays: [4])
        var previous = WorkRhythm(); previous.scheduleRules = [legacy]
        var next = previous
        let created = WorkScheduleRule(name: "新规则", weekdays: [6])
        next.scheduleRules?.append(created)
        next.startNewRules(comparedTo: previous, on: "2026-11-27")
        #expect(next.scheduleRules?[0].effectiveFromDay == nil)
        #expect(next.scheduleRules?[1].effectiveFromDay == "2026-11-27")
        previous = next
        next.scheduleRules?.reverse()
        next.scheduleRules?[0].enabled = false
        next.scheduleRules?[0].effectiveFromDay = nil
        next.startNewRules(comparedTo: previous, on: "2026-12-04")
        #expect(next.scheduleRules?[0].effectiveFromDay == "2026-11-27")
        #expect(next.scheduleRules?[1].effectiveFromDay == nil)
    }

    @Test func effectiveDatesRoundTripAndOlderBackupsKeepTheirRuleDefinitions() throws {
        var rule = WorkScheduleRule(weekdays: [6], effectiveFromDay: "2026-11-27", schedule: short)
        let encoded = try JSONEncoder().encode(rule)
        #expect(try JSONDecoder().decode(WorkScheduleRule.self, from: encoded) == rule)
        var old = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        old.removeValue(forKey: "effectiveFromDay")
        let restored = try JSONDecoder().decode(WorkScheduleRule.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(restored.effectiveFromDay == nil && restored.id == rule.id && restored.schedule == short)
        rule.effectiveFromDay = "2026-02-30"
        #expect(throws: DayPerkInputError.self) { try rule.validate() }
    }

    @Test func draggingRulesBothDirectionsKeepsTheirContentsAndUpdatesPriority() throws {
        let first = WorkScheduleRule(name: "第一条", weekdays: [6], schedule: normal)
        let second = WorkScheduleRule(name: "第二条", weekdays: [6], schedule: short)
        let third = WorkScheduleRule(name: "第三条", enabled: false, weekdays: [4], intervalWeeks: 2, anchorDay: "2026-11-02", schedule: short)
        var rhythm = WorkRhythm(); rhythm.scheduleRules = [first, second, third]
        let movedUp = rhythm.moveScheduleRule(second.id, to: first.id)
        #expect(movedUp)
        #expect(rhythm.scheduleRules == [second, first, third])
        #expect(rhythm.schedule(for: "2026-11-06", fallback: normal) == short)
        let movedDown = rhythm.moveScheduleRule(second.id, to: third.id)
        #expect(movedDown)
        #expect(rhythm.scheduleRules == [first, third, second])
        #expect(rhythm.schedule(for: "2026-11-06", fallback: normal) == normal)
        try rhythm.validate()
        #expect(try JSONDecoder().decode(WorkRhythm.self, from: JSONEncoder().encode(rhythm)) == rhythm)
    }

    @Test func canceledOrStaleRuleDragDoesNotChangeTheOrder() {
        var rhythm = WorkRhythm(); rhythm.scheduleRules = weeklyRules()
        let original = rhythm.scheduleRules!
        let sameRow = rhythm.moveScheduleRule(original[0].id, to: original[0].id)
        let missingSource = rhythm.moveScheduleRule(UUID(), to: original[0].id)
        let missingTarget = rhythm.moveScheduleRule(original[0].id, to: UUID())
        #expect(!sameRow && !missingSource && !missingTarget)
        #expect(rhythm.scheduleRules == original)
        rhythm.scheduleRules = nil
        let empty = rhythm.moveScheduleRule(original[0].id, to: original[1].id)
        #expect(!empty)
        #expect(rhythm.scheduleRules == nil)
    }

    @Test func draggingWholeCardsMovesNeighborsWithDifferentExpandedHeights() throws {
        let down = try #require(DragReorderLayout(source: 0, translation: 120, heights: [80, 200, 60]))
        #expect(down.target == 1 && down.offset(at: 0) == 120)
        #expect(down.offset(at: 1) == -94 && down.offset(at: 2) == 0)
        let up = try #require(DragReorderLayout(source: 1, translation: -60, heights: [80, 200, 60]))
        #expect(up.target == 0 && up.offset(at: 1) == -60)
        #expect(up.offset(at: 0) == 214 && up.offset(at: 2) == 0)
        let shortMove = try #require(DragReorderLayout(source: 1, translation: -20, heights: [80, 200, 60]))
        #expect(shortMove.target == 1 && shortMove.offset(at: 0) == 0)
        #expect(DragReorderLayout(source: 0, translation: 10000, heights: [80, 200, 60])?.target == 2)
        #expect(DragReorderLayout(source: 2, translation: -10000, heights: [80, 200, 60])?.target == 0)
        #expect(DragReorderLayout(source: 0, translation: .nan, heights: [80]) == nil)
        #expect(DragReorderLayout(source: 0, translation: 10, heights: [0]) == nil)
    }

    @Test func rulesOverrideCycleButAnExactDateWinsAndReorderingChangesTheWinner() throws {
        var rhythm = WorkRhythm(enabled: true, anchorDay: "2026-11-02", weeks: [[2, 3, 4, 5, 6]])
        rhythm.cycleSchedules = [WorkRhythm.weekSlot(0, weekday: 6): short]
        #expect(rhythm.schedule(for: "2026-11-06", fallback: normal) == short)
        let longer = DayWorkSchedule(startMinute: 540, endMinute: 1140, breakMinutes: 60)
        rhythm.scheduleRules = [WorkScheduleRule(weekdays: [6], schedule: longer), WorkScheduleRule(weekdays: [6], schedule: normal)]
        #expect(rhythm.schedule(for: "2026-11-06", fallback: normal) == longer)
        rhythm.scheduleRules?.swapAt(0, 1)
        #expect(rhythm.schedule(for: "2026-11-06", fallback: normal) == normal)
        rhythm.scheduleRules?[0].enabled = false
        #expect(rhythm.schedule(for: "2026-11-06", fallback: normal) == longer)
        rhythm.daySchedules = ["2026-11-06": short]
        #expect(rhythm.schedule(for: "2026-11-06", fallback: normal) == short)
        try rhythm.validate()
    }

    @Test func alternatingWeekRuleIsStableBeforeItsAnchorAcrossYearsAndDST() {
        let rule = WorkScheduleRule(weekdays: [4], intervalWeeks: 2, anchorDay: "2026-03-04", schedule: short)
        for day in ["2026-03-04", "2026-03-18", "2026-02-18", "2026-12-23", "2027-01-06"] { #expect(rule.matches(day)) }
        for day in ["2026-03-11", "2026-03-25", "2026-02-25", "2026-12-30", "2026-03-19", "invalid"] { #expect(!rule.matches(day)) }
        let calendar = calendar
        var rhythm = WorkRhythm(); rhythm.scheduleRules = [rule]
        let plan = WorkPlan(rhythm: rhythm)
        #expect(plan.schedule(for: WorkPlan.dayKey(date(18, 23, month: 3), calendar: calendar)) == short)
    }

    @Test func weeklyAndDailyCycleSlotsUseTheSameAnchorAsTheirWorkdays() throws {
        var rhythm = WorkRhythm(enabled: true, anchorDay: "2026-03-06", weeks: [[2, 3, 4, 5, 6]])
        rhythm.cycleDays = [true, true, false]
        rhythm.cycleSchedules = [WorkRhythm.daySlot(0): short, WorkRhythm.daySlot(1): normal]
        for day in ["2026-03-03", "2026-03-06", "2026-03-09", "2026-03-12"] {
            #expect(rhythm.schedule(for: day, fallback: normal) == short)
        }
        #expect(rhythm.isWorkday(date(9, month: 3), calendar: calendar))
        #expect(!rhythm.isWorkday(date(8, month: 3), calendar: calendar))
        rhythm.cycleDays = nil; rhythm.anchorDay = "2026-03-02"
        rhythm.weeks = [[2, 3, 4, 5, 6], [2, 3, 4, 5, 6, 7]]
        rhythm.cycleSchedules?[WorkRhythm.weekSlot(1, weekday: 7)] = short
        #expect(rhythm.isWorkday(date(14, month: 3), calendar: calendar))
        #expect(rhythm.schedule(for: "2026-03-14", fallback: normal) == short)
        #expect(rhythm.schedule(for: "2026-02-28", fallback: normal) == short)
        rhythm.enabled = false
        #expect(rhythm.schedule(for: "2026-03-14", fallback: normal) == normal)
        try rhythm.validate()
    }

    @Test func fridayAndAlternatingWednesdayReduceMonthlyHoursButNotRestDays() throws {
        var rhythm = WorkRhythm(); rhythm.scheduleRules = weeklyRules()
        var plan = WorkPlan(dateOverrides: ["2026-11-26": false], defaultDailyExpectedIncome: 800, referenceSeconds: 8 * 3600, rhythm: rhythm)
        plan.rhythm.daySchedules = ["2026-11-27": DayWorkSchedule(startMinute: 540, endMinute: 1020, breakMinutes: 60)]
        #expect(plan.regularWorkdays(year: 2026, month: 11, calendar: calendar) == 20)
        // 21 个工作日：4 个周五及 2 个隔周周三各少 2 小时，节假日少 8 小时，指定日再加回 1 小时。
        #expect(plan.monthlyReferenceSeconds(year: 2026, month: 11, calendar: calendar) == 149 * 3600)
        #expect(plan.expectedIncome(for: "2026-11-04", calendar: calendar) == 800)
        #expect(plan.expectedIncome(for: "2026-11-11", calendar: calendar) == 800)
        #expect(plan.expectedIncome(for: "2026-11-27", calendar: calendar) == 800)
        plan.rhythm.scheduleRules?.insert(WorkScheduleRule(weekdays: [7], schedule: short), at: 0)
        #expect(!plan.isScheduledWorkday(date(7), calendar: calendar))
        #expect(plan.expectedIncome(for: "2026-11-07", calendar: calendar) == 0)
        #expect(plan.monthlyReferenceSeconds(year: 2026, month: 11, calendar: calendar) == 149 * 3600)
    }

    @Test func shortShiftDrivesOvertimeAutomationAndHistoricalSnapshotsTogether() {
        var rhythm = WorkRhythm(); rhythm.scheduleRules = [WorkScheduleRule(weekdays: [6], schedule: short)]
        let plan = WorkPlan(ratePerSecond: 1, referenceSeconds: 8 * 3600, rhythm: rhythm)
        #expect(plan.isWithinWorkHours(date(6, 15, 59), calendar: calendar))
        #expect(!plan.isWithinWorkHours(date(6, 16, 1), calendar: calendar))
        #expect(plan.hasReachedShiftEnd(date(6, 16, 1), calendar: calendar))
        #expect(plan.isNearRestStart(date(6, 15, 45), calendar: calendar))
        #expect(!plan.isNearRestStart(date(6, 17, 45), calendar: calendar))
        var day = WorkDayTotal(id: "2026-11-06", seconds: 7 * 3600)
        plan.stamp(&day, calendar: calendar)
        #expect(day.referenceSeconds == 6 * 3600 && day.unpaidOvertimeSeconds == 3600)
        var snapshot = WorkDayTotal(id: "2026-11-06", seconds: 7 * 3600, referenceSeconds: 8 * 3600, settledAt: date(6, 18))
        plan.stamp(&snapshot, calendar: calendar, preservingExisting: true)
        #expect(snapshot.referenceSeconds == 8 * 3600 && snapshot.unpaidOvertimeSeconds == 0)
        let report = WorkReport.make(days: [day], containing: date(6), period: .week, calendar: calendar, asOf: date(8))
        #expect(report.unpaidOvertimeSeconds == 3600)
    }

    @Test func halfDayLeaveKeepsHalfDayPaySeparateFromItsActualScheduledHours() throws {
        let asymmetric = DayWorkSchedule(startMinute: 630, endMinute: 1080, breakMode: .timeRanges,
            breaks: [WorkBreak(startMinute: 720, endMinute: 780)])
        var rhythm = WorkRhythm(); rhythm.scheduleRules = [WorkScheduleRule(weekdays: [6], schedule: asymmetric)]
        var plan = WorkPlan(defaultDailyExpectedIncome: 800, referenceSeconds: 8 * 3600, rhythm: rhythm)
        plan.leaveDays = ["2026-11-06": LeaveDay(morning: .unpaid, boundaryMinute: 720)]
        #expect(plan.scheduledReferenceSeconds(for: "2026-11-06") == 6.5 * 3600)
        #expect(plan.referenceSeconds(for: "2026-11-06") == 5 * 3600)
        #expect(plan.expectedIncome(for: "2026-11-06", calendar: calendar) == 400)
        plan.leaveDays["2026-11-06"] = LeaveDay(afternoon: .paid, boundaryMinute: 720)
        #expect(plan.referenceSeconds(for: "2026-11-06") == 1.5 * 3600)
        #expect(plan.expectedIncome(for: "2026-11-06", calendar: calendar) == 800)
        let request = LeaveRequest(base: LeaveRange(start: date(6), end: date(9)))
        #expect(try LeaveRequests.summary(request, plan: plan, calendar: calendar).paidDays == 2)
    }

    @Test func shortAndLongShiftsChangeOnlyTimeValueRateAndOnlyUnpaidLeaveReducesIncome() {
        var rhythm = WorkRhythm()
        rhythm.scheduleRules = [WorkScheduleRule(weekdays: [6], schedule: short),
            WorkScheduleRule(weekdays: [4], schedule: DayWorkSchedule(startMinute: 540, endMinute: 1200, breakMinutes: 60))]
        var plan = WorkPlan(defaultDailyExpectedIncome: 800, referenceSeconds: 8 * 3600, rhythm: rhythm)
        for key in ["2026-11-04", "2026-11-05", "2026-11-06"] {
            #expect(plan.expectedIncome(for: key, calendar: calendar) == 800)
            let seconds = plan.scheduledReferenceSeconds(for: key)
            #expect(abs(plan.timeValueRate(dailyIncome: 800, for: key) * seconds - 800) < 0.001)
        }
        #expect(plan.timeValueRate(dailyIncome: 800, for: "2026-11-06") > plan.timeValueRate(dailyIncome: 800, for: "2026-11-05"))
        #expect(plan.timeValueRate(dailyIncome: 800, for: "2026-11-04") < plan.timeValueRate(dailyIncome: 800, for: "2026-11-05"))
        plan.leaveDays["2026-11-06"] = LeaveDay(morning: .paid, afternoon: .paid)
        #expect(plan.expectedIncome(for: "2026-11-06", calendar: calendar) == 800)
        plan.leaveDays["2026-11-06"] = LeaveDay(morning: .unpaid)
        #expect(plan.expectedIncome(for: "2026-11-06", calendar: calendar) == 400)
        plan.leaveDays["2026-11-06"] = LeaveDay(morning: .unpaid, afternoon: .unpaid)
        #expect(plan.expectedIncome(for: "2026-11-06", calendar: calendar) == 0)
    }

    @Test func nightRuleUsesTheBusinessDateAfterMidnight() {
        let night = DayWorkSchedule(startMinute: 1320, endMinute: 420, breakMode: .timeRanges,
            breaks: [WorkBreak(startMinute: 120, endMinute: 180)])
        var rhythm = WorkRhythm(); rhythm.scheduleRules = [WorkScheduleRule(weekdays: [6], schedule: night)]
        let plan = WorkPlan(dayStartMinute: 720, rhythm: rhythm)
        #expect(plan.businessDayKey(date(7, 6), calendar: calendar) == "2026-11-06")
        #expect(plan.isWithinWorkHours(date(7, 6), calendar: calendar))
        #expect(!plan.isWithinWorkHours(date(7, 2, 30), calendar: calendar))
        #expect(plan.isNearRestStart(date(7, 6, 45), calendar: calendar))
    }

    @Test func oldConfigurationsRetainDefaultHoursAndNewFieldsRoundTrip() throws {
        let old = Data(#"{"enabled":false,"anchorDay":"2026-01-05","weeks":[[2,3,4,5,6]]}"#.utf8)
        var rhythm = try JSONDecoder().decode(WorkRhythm.self, from: old)
        #expect(rhythm.cycleSchedules == nil && rhythm.scheduleRules == nil)
        #expect(rhythm.schedule(for: "2026-11-06", fallback: normal) == normal)
        rhythm.scheduleRules = weeklyRules()
        rhythm.cycleSchedules = [WorkRhythm.daySlot(0): short]
        #expect(try JSONDecoder().decode(WorkRhythm.self, from: JSONEncoder().encode(rhythm)) == rhythm)
    }

    @Test func backupRestoresCycleTimesAndRulePriorityAndRejectsInvalidRulesAtomically() throws {
        let domain = "app.dayperk.tests.schedule-backup." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let imageURL = FileManager.default.temporaryDirectory.appendingPathComponent(domain + ".png")
        var rhythm = WorkRhythm(enabled: true); rhythm.scheduleRules = weeklyRules().reversed()
        rhythm.cycleSchedules = [WorkRhythm.weekSlot(0, weekday: 6): short]
        defaults.set(try JSONEncoder().encode(rhythm), forKey: "dayperkWorkRhythm")
        let backup = try AppDataBackup.create(defaults: defaults, backgroundURL: imageURL)
        defaults.set(Data(), forKey: "dayperkWorkRhythm")
        try AppDataBackup.restore(backup, defaults: defaults, domain: domain, backgroundURL: imageURL)
        #expect(try JSONDecoder().decode(WorkRhythm.self, from: #require(defaults.data(forKey: "dayperkWorkRhythm"))) == rhythm)
        rhythm.scheduleRules?[0].intervalWeeks = 0
        defaults.set(try JSONEncoder().encode(rhythm), forKey: "dayperkWorkRhythm")
        let invalid = try AppDataBackup.create(defaults: defaults, backgroundURL: imageURL)
        defaults.set("keep", forKey: "dayperkWorkRhythm")
        #expect(throws: (any Error).self) { try AppDataBackup.restore(invalid, defaults: defaults, domain: domain, backgroundURL: imageURL) }
        #expect(defaults.string(forKey: "dayperkWorkRhythm") == "keep")
    }

    @Test func invalidWeekdaysIntervalsAnchorsAndHoursCannotBeSaved() {
        var rule = WorkScheduleRule(weekdays: [], schedule: normal)
        #expect(throws: DayPerkInputError.self) { try rule.validate() }
        rule.weekdays = [8]
        #expect(throws: DayPerkInputError.self) { try rule.validate() }
        rule.weekdays = [6]; rule.intervalWeeks = 53
        #expect(throws: DayPerkInputError.self) { try rule.validate() }
        rule.intervalWeeks = 2; rule.anchorDay = "2026-02-30"
        #expect(throws: DayPerkInputError.self) { try rule.validate() }
        rule.anchorDay = "2026-11-02"; rule.schedule.endMinute = rule.schedule.startMinute
        #expect(throws: DayPerkInputError.self) { try rule.validate() }
        var rhythm = WorkRhythm(); rhythm.cycleSchedules = ["day:56": normal]
        #expect(throws: DayPerkInputError.self) { try rhythm.validate() }
    }

    @MainActor @Test func lockDoubleClickAndHidePauseAtTheRuleBoundaryWithoutDebounceBackfill() throws {
        for action in 0 ... 2 {
            let defaults = try #require(UserDefaults(suiteName: "app.dayperk.tests.schedule-privacy." + UUID().uuidString))
            let controller = WorkTrackingController(defaults: defaults, calendar: calendar, observeSystem: false)
            defer { controller.shutdown() }
            var rhythm = WorkRhythm(); rhythm.scheduleRules = [WorkScheduleRule(weekdays: [6], schedule: normal)]
            let plan = WorkPlan(startMinute: 540, endMinute: 1200, ratePerSecond: 1, referenceSeconds: 10 * 3600,
                rhythm: rhythm, automation: .enabledForTesting)
            var now = date(6, 17, 45)
            controller.updatePlan(plan, at: now.addingTimeInterval(-5)); controller.setWorking(true, at: now.addingTimeInterval(-5))
            let access = SalaryAccessController(defaults: defaults, now: { now }) { _, done in done(false) }
            let privacy = PrivacySettings(defaults: defaults)
            access.dataWillLock = { controller.pauseForDataLock(at: now) }
            access.sensitiveInformationWillHide = { controller.pauseForDataLock(at: now) }
            var opens = 0
            if action == 0 { access.lockAllData() }
            else if action == 1 {
                let clicks = StatusItemClickHandler()
                clicks.handle(clickCount: 1, single: { opens += 1 }, double: { access.lockAllData() })
                clicks.handle(clickCount: 2, single: { opens += 1 }, double: { access.lockAllData() })
            } else { access.setSensitiveInformationHidden(true, privacy: privacy) }
            #expect(opens == 0 && !controller.state.isWorking && controller.state.days[0].seconds == 5)
            #expect(controller.state.pendingPause == nil && controller.state.pendingClockOut == nil)
            now = now.addingTimeInterval(5); controller.setWorking(true, at: now)
            controller.updatePlan(plan, at: now.addingTimeInterval(1))
            #expect(controller.state.days[0].seconds == 6)
        }
    }

    @MainActor @Test func hidingRespectsTheOptInAndTheBreakWindow() throws {
        for (enabled, hour) in [(false, 17), (true, 14)] {
            let defaults = try #require(UserDefaults(suiteName: "app.dayperk.tests.schedule-hide." + UUID().uuidString))
            let controller = WorkTrackingController(defaults: defaults, calendar: calendar, observeSystem: false)
            defer { controller.shutdown() }
            var rules = WorkAutomationRules(); rules.lockPausesWork = enabled
            let plan = WorkPlan(startMinute: 540, endMinute: 1080, ratePerSecond: 1, automation: rules)
            let now = date(6, hour, 45)
            controller.updatePlan(plan, at: now); controller.setWorking(true, at: now)
            let access = SalaryAccessController(defaults: defaults)
            access.sensitiveInformationWillHide = { controller.pauseForDataLock(at: now) }
            let privacy = PrivacySettings(defaults: defaults)
            access.setSensitiveInformationHidden(true, privacy: privacy)
            #expect(privacy.isPrivacyModeEnabled && controller.state.isWorking)
        }
    }

    @MainActor @Test func privacyAfterAnExistingPauseOrClockOutCancelsItsPendingBackfill() throws {
        for clockedOut in [false, true] {
            let defaults = try #require(UserDefaults(suiteName: "app.dayperk.tests.pending-privacy." + UUID().uuidString))
            let controller = WorkTrackingController(defaults: defaults, calendar: calendar, observeSystem: false)
            defer { controller.shutdown() }
            let plan = WorkPlan(startMinute: 540, endMinute: 1080, ratePerSecond: 1, automation: .enabledForTesting)
            var now = date(6, 17, 45)
            controller.updatePlan(plan, at: now.addingTimeInterval(-20)); controller.setWorking(true, at: now.addingTimeInterval(-20))
            if clockedOut { controller.finishToday(at: now) }
            else { controller.setWorking(false, at: now) }
            #expect(controller.state.pendingPause != nil || controller.state.pendingClockOut != nil)
            now = now.addingTimeInterval(1)
            let access = SalaryAccessController(defaults: defaults)
            access.sensitiveInformationWillHide = { controller.pauseForDataLock(at: now) }
            access.setSensitiveInformationHidden(true, privacy: PrivacySettings(defaults: defaults))
            #expect(controller.state.pendingPause == nil && controller.state.pendingClockOut == nil)
            now = now.addingTimeInterval(2); controller.setWorking(true, at: now)
            controller.updatePlan(plan, at: now.addingTimeInterval(1))
            #expect(controller.state.days[0].seconds == 21)
        }
    }
}
